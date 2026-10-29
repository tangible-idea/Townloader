import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/saved_link.dart';

class PlacesException implements Exception {
  PlacesException(this.message, {this.rateLimited = false});

  final String message;

  /// 하루 분석 횟수를 다 썼으면 true.
  final bool rateLimited;

  @override
  String toString() => message;
}

/// 프록시(Cloudflare Worker)의 `/places` 로 글 하나의 장소를 찾는다.
/// 요청 형식은 `proxy/src/places.ts` 의 `PlacesRequest` 와 같다.
class PlacesClient {
  PlacesClient({String? baseUrl, String? appToken, http.Client? httpClient})
    : _baseUrl = baseUrl ?? AppConfig.proxyUrl,
      _appToken = appToken ?? AppConfig.proxyAppToken,
      _http = httpClient ?? http.Client();

  final String _baseUrl;
  final String _appToken;
  final http.Client _http;
  final Map<String, Future<KakaoPlaceDetail?>> _panelCache = {};

  static const Duration timeout = Duration(seconds: 90);

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<List<SavedPlace>> findPlaces(Map<String, Object?> request) async {
    if (!isConfigured) {
      throw PlacesException('장소를 찾는 서버가 이 빌드에 설정되어 있지 않습니다.');
    }
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_baseUrl/places'),
            headers: {
              'content-type': 'application/json',
              'x-app-token': _appToken,
            },
            body: jsonEncode(request),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw PlacesException('장소를 찾는 데 시간이 너무 오래 걸립니다.');
    } on Exception {
      throw PlacesException('장소를 찾는 서버에 연결하지 못했습니다.');
    }

    if (response.statusCode == 429) {
      throw PlacesException('오늘 분석할 수 있는 횟수를 다 썼습니다.', rateLimited: true);
    }
    if (response.statusCode != 200) {
      throw PlacesException('장소를 찾지 못했습니다 (HTTP ${response.statusCode}).');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final places = data is Map ? data['places'] : null;
    if (places is! List) throw PlacesException('장소 응답을 읽지 못했습니다.');
    return [
      for (final place in places)
        if (place is Map<String, dynamic>) SavedPlace.fromJson(place),
    ];
  }

  /// 카카오맵 장소 검색에서 장소의 대표 사진·업종·별점·전화번호·상세 페이지 주소를 채운다.
  /// 이미 채워졌거나 못 찾으면 원래 [place] 를 그대로 돌려준다.
  Future<SavedPlace> enrichPlace(SavedPlace place) async {
    if (place.approximate) return place;
    var current = place;
    if (!current.hasKakaoDetails) {
      final area = _areaTokens(current.address);
      for (final query in _queryVariants(current.name)) {
        final hit = await _searchKakaoMap(query, area);
        if (hit != null) {
          current = current.copyWith(
            address: current.address ?? hit.address,
            category: hit.category,
            phone: hit.phone,
            photoUrl: hit.photoUrl,
            placeUrl: hit.placeUrl,
            rating: hit.rating,
            reviewCount: hit.reviewCount,
          );
          break;
        }
      }
    }
    if (current.summary == null) {
      final id = current.kakaoId;
      if (id != null) {
        final detail = await fetchPlaceDetailById(id);
        final oneLiner = detail?.oneLiner;
        if (oneLiner != null) {
          current = current.copyWith(summary: oneLiner);
        }
      }
    }
    return current;
  }

  /// [place] 의 카카오맵 상세 패널(AI 요약, 영업시간, 메뉴, 방문자 후기, 블로그 리뷰)을 가져온다.
  Future<KakaoPlaceDetail?> fetchPlaceDetail(SavedPlace place) async {
    var target = place;
    if (target.kakaoId == null && !target.approximate) {
      target = await enrichPlace(target);
    }
    final id = target.kakaoId;
    if (id == null) return null;
    return fetchPlaceDetailById(id);
  }

  Future<KakaoPlaceDetail?> fetchPlaceDetailById(String confirmId) =>
      _panelCache.putIfAbsent(confirmId, () => _loadPanel(confirmId));

  Future<KakaoPlaceDetail?> _loadPanel(String confirmId) async {
    try {
      final uri = Uri.https(
        'place-api.map.kakao.com',
        '/places/panel3/$confirmId',
      );
      final response = await _http
          .get(
            uri,
            headers: {
              'referer': 'https://place.map.kakao.com/$confirmId',
              'user-agent': 'Mozilla/5.0',
              'accept': 'application/json',
              'pf': 'web',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return KakaoPlaceDetail.fromJson(decoded);
    } on Exception {
      return null;
    }
  }

  Future<_KakaoHit?> _searchKakaoMap(String query, List<String> area) async {
    try {
      final uri = Uri.https(
        'search.map.kakao.com',
        '/mapsearch/map.daum',
        {'callback': 'j', 'msFlag': 'A', 'sort': '0', 'q': query},
      );
      final response = await _http
          .get(
            uri,
            headers: const {
              'referer': 'https://map.kakao.com/',
              'user-agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final text = utf8.decode(response.bodyBytes);
      final start = text.indexOf('(');
      final end = text.lastIndexOf(')');
      if (start < 0 || end <= start) return null;
      final decoded = jsonDecode(text.substring(start + 1, end));
      final list = decoded is Map ? decoded['place'] : null;
      if (list is! List) return null;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final name = (raw['name'] as String? ?? '').trim();
        final addr = (raw['address'] as String? ?? '').trim();
        final newAddr = (raw['new_address'] as String? ?? '').trim();
        if (!_similar(query, name) || !_matchesArea('$addr $newAddr', area)) {
          continue;
        }
        final rawImg = _pickImage(raw);
        final rating = _toDouble(raw['rating_average']);
        final reviews =
            _toInt(raw['reviewCount']) ?? _toInt(raw['rating_count']);
        final id = (raw['confirmid'] as String? ?? '').trim();
        final cate = (raw['last_cate_name'] as String? ?? '').trim();
        final cate2 = (raw['cate_name_depth2'] as String? ?? '').trim();
        final tel = (raw['tel'] as String? ?? '').trim();
        return _KakaoHit(
          address: newAddr.isNotEmpty
              ? newAddr
              : (addr.isNotEmpty ? addr : null),
          category: cate.isNotEmpty
              ? cate
              : (cate2.isNotEmpty ? cate2 : null),
          phone: tel.isNotEmpty ? tel : null,
          photoUrl: _kakaoThumb(rawImg),
          placeUrl: id.isNotEmpty ? 'https://place.map.kakao.com/$id' : null,
          rating: rating != null && rating > 0 ? rating : null,
          reviewCount: reviews != null && reviews > 0 ? reviews : null,
        );
      }
      return null;
    } on Exception {
      return null;
    }
  }

  static String? _pickImage(Map<String, dynamic> raw) {
    final img = (raw['img'] as String? ?? '').trim();
    if (img.isNotEmpty) return img;
    final info = raw['image_info'];
    if (info is Map) {
      final urls = info['image_main_urls'];
      if (urls is List) {
        for (final u in urls) {
          if (u is String && u.trim().isNotEmpty) return u.trim();
        }
      }
    }
    return null;
  }

  static String? _kakaoThumb(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final httpsUrl = rawUrl.replaceFirst(RegExp('^http://'), 'https://');
    return 'https://img1.kakaocdn.net/cthumb/local/R400x0/?fname=${Uri.encodeComponent(httpsUrl)}';
  }

  static double? _toDouble(Object? value) => switch (value) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _toInt(Object? value) => switch (value) {
    final int n => n,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static List<String> _queryVariants(String name) {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return [
      for (var n = words.length; n >= 1; n--)
        if (words.take(n).join().length >= 2) words.take(n).join(' '),
    ];
  }

  static List<String> _areaTokens(String? address) {
    if (address == null || address.isEmpty) return const [];
    final tokens = address
        .split(RegExp(r'\s+'))
        .where(
          (w) =>
              RegExp(r'(동|읍|면|리|가|구|군)$').hasMatch(w) ||
              RegExp(r'동\d*가$').hasMatch(w),
        )
        .toList();
    return tokens.reversed.toList();
  }

  static bool _matchesArea(String found, List<String> area) =>
      area.isEmpty || area.any(found.contains);

  static bool _similar(String query, String found) {
    final a = _normalize(query);
    final b = _normalize(found);
    if (a.isEmpty || b.isEmpty) return false;
    if (a.contains(b) || b.contains(a)) return true;
    Set<String> grams(String s) => {
      for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2),
    };
    final ga = grams(a);
    final gb = grams(b);
    if (ga.isEmpty || gb.isEmpty) return false;
    final shared = ga.where(gb.contains).length;
    final denom = ga.length < gb.length ? ga.length : gb.length;
    return shared / denom >= 0.6;
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

  /// 저장한 글의 짧은 대표 제목. 못 지으면 null 이고, 오류도 null 로 넘긴다(제목은 없어도 된다).
  Future<String?> title({
    required String code,
    required bool isKo,
    String? caption,
    List<String> places = const [],
    List<String> lines = const [],
  }) async {
    if (!isConfigured) return null;
    try {
      final response = await _http
          .post(
            Uri.parse('$_baseUrl/title'),
            headers: {
              'content-type': 'application/json',
              'x-app-token': _appToken,
            },
            body: jsonEncode({
              'code': code,
              'lang': isKo ? 'ko' : 'en',
              'caption': caption ?? '',
              'places': places,
              'lines': lines,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final title = data is Map ? data['title'] : null;
      return title is String && title.trim().isNotEmpty ? title.trim() : null;
    } on Exception {
      return null;
    }
  }

  void close() => _http.close();
}

class _KakaoHit {
  const _KakaoHit({
    this.address,
    this.category,
    this.phone,
    this.photoUrl,
    this.placeUrl,
    this.rating,
    this.reviewCount,
  });

  final String? address;
  final String? category;
  final String? phone;
  final String? photoUrl;
  final String? placeUrl;
  final double? rating;
  final int? reviewCount;
}

/// 카카오맵 상세 패널(`place-api.map.kakao.com/places/panel3/{id}`) 응답.
class KakaoPlaceDetail {
  const KakaoPlaceDetail({
    this.aiTitle,
    this.aiSummary,
    this.aiKeywords = const [],
    this.priceLevel,
    this.openStatus,
    this.openHours = const [],
    this.photos = const [],
    this.menus = const [],
    this.tags = const [],
    this.strengths = const [],
    this.visitorReviews = const [],
    this.blogReviews = const [],
  });

  factory KakaoPlaceDetail.fromJson(Map<String, dynamic> json) {
    final aiMate = json['ai_mate'];
    String? aiTitle;
    String? aiSummary;
    String? priceLevel;
    final aiKeywords = <String>[];
    if (aiMate is Map) {
      final summary = aiMate['summary'];
      final bottom = aiMate['bottom_sheet'];
      aiTitle = _nonEmpty(summary is Map ? summary['title'] : null) ??
          _nonEmpty(bottom is Map ? bottom['title'] : null);
      aiSummary = _nonEmpty(bottom is Map ? bottom['summary'] : null);
      final price = aiMate['price_level'];
      priceLevel = _nonEmpty(price is Map ? price['symbol'] : null);
      final blogSummaries = aiMate['blog_summaries'];
      if (blogSummaries is List) {
        for (final group in blogSummaries) {
          if (group is! Map) continue;
          final kws = group['keywords'];
          if (kws is List) {
            for (final kw in kws) {
              final s = _nonEmpty(kw);
              if (s != null && !aiKeywords.contains(s)) aiKeywords.add(s);
            }
          }
        }
      }
    }

    String? openStatus;
    final openHours = <String>[];
    final hours = json['open_hours'];
    if (hours is Map) {
      final headline = hours['headline'];
      if (headline is Map) {
        final parts = [
          _nonEmpty(headline['display_text']),
          _nonEmpty(headline['display_text_info']),
        ].whereType<String>().toList();
        if (parts.isNotEmpty) openStatus = parts.join(' · ');
      }
      final week = hours['week_from_today'];
      final periods = week is Map ? week['week_periods'] : null;
      if (periods is List) {
        for (final period in periods) {
          final days = period is Map ? period['days'] : null;
          if (days is! List) continue;
          for (final day in days) {
            if (day is! Map) continue;
            final label = _nonEmpty(day['day_of_the_week_desc']);
            if (label == null) continue;
            final onDays = day['on_days'];
            final time = onDays is Map
                ? _nonEmpty(onDays['start_end_time_desc'])
                : null;
            final lastOrder = onDays is Map &&
                    onDays['last_order_times_desc'] is List &&
                    (onDays['last_order_times_desc'] as List).isNotEmpty
                ? _nonEmpty((onDays['last_order_times_desc'] as List).first)
                : null;
            final line = [
              label,
              time ?? _nonEmpty(day['off_days_desc']) ?? '휴무',
              if (lastOrder != null) '($lastOrder)',
            ].join(' ');
            openHours.add(line);
          }
        }
      }
    }

    final photos = <String>[];
    final photoWrap = json['photos'];
    final rawPhotos = photoWrap is Map ? photoWrap['photos'] : null;
    if (rawPhotos is List) {
      for (final item in rawPhotos.take(10)) {
        if (item is! Map) continue;
        final thumb = PlacesClient._kakaoThumb(_nonEmpty(item['url']));
        if (thumb != null && !photos.contains(thumb)) photos.add(thumb);
      }
    }

    final menus = <KakaoMenuItem>[];
    final menuWrap = json['menu'];
    final menuInner = menuWrap is Map ? menuWrap['menus'] : null;
    final menuItems = menuInner is Map ? menuInner['items'] : null;
    if (menuItems is List) {
      for (final item in menuItems.take(8)) {
        if (item is! Map) continue;
        final name = _nonEmpty(item['name']);
        if (name == null) continue;
        menus.add(
          KakaoMenuItem(
            name: name,
            price: PlacesClient._toInt(item['price']),
            description: _nonEmpty(item['desc']),
            recommend: item['is_recommend'] == true,
          ),
        );
      }
    }

    final tags = <String>[];
    final addInfo = json['place_add_info'];
    final rawTags = addInfo is Map ? addInfo['tags'] : null;
    if (rawTags is List) {
      for (final tag in rawTags.take(10)) {
        final s = _nonEmpty(tag);
        if (s != null && !tags.contains(s)) tags.add(s);
      }
    }

    final strengths = <KakaoStrength>[];
    final visitorReviews = <KakaoVisitorReview>[];
    final kReview = json['kakaomap_review'];
    if (kReview is Map) {
      final descById = <int, String>{};
      final descs = kReview['strength_description'];
      if (descs is List) {
        for (final d in descs) {
          if (d is! Map) continue;
          final id = PlacesClient._toInt(d['id']);
          final name = _nonEmpty(d['name']);
          if (id != null && name != null) descById[id] = name;
        }
      }
      final scoreSet = kReview['score_set'];
      final counts = scoreSet is Map ? scoreSet['strength_counts'] : null;
      if (counts is List) {
        for (final c in counts) {
          if (c is! Map) continue;
          final id = PlacesClient._toInt(c['id']);
          final count = PlacesClient._toInt(c['count']);
          final name = id == null ? null : descById[id];
          if (name != null && count != null && count > 0) {
            strengths.add(KakaoStrength(name: name, count: count));
          }
        }
      }
      final rawReviews = kReview['reviews'];
      if (rawReviews is List) {
        for (final r in rawReviews.take(10)) {
          if (r is! Map) continue;
          final contents = _nonEmpty(r['contents']);
          if (contents == null) continue;
          final meta = r['meta'];
          final owner = meta is Map ? meta['owner'] : null;
          final nickname = owner is Map ? _nonEmpty(owner['nickname']) : null;
          final rPhotos = <String>[];
          if (r['photos'] is List) {
            for (final p in (r['photos'] as List).take(4)) {
              if (p is! Map) continue;
              final thumb = PlacesClient._kakaoThumb(_nonEmpty(p['url']));
              if (thumb != null) rPhotos.add(thumb);
            }
          }
          visitorReviews.add(
            KakaoVisitorReview(
              author: nickname ?? '방문자',
              rating: PlacesClient._toInt(r['star_rating']) ?? 5,
              contents: contents,
              date: _shortDate(_nonEmpty(r['registered_at'])),
              photos: rPhotos,
            ),
          );
        }
      }
    }

    final blogReviews = <KakaoBlogReview>[];
    final bReview = json['blog_review'];
    final rawBlogs = bReview is Map ? bReview['reviews'] : null;
    if (rawBlogs is List) {
      for (final b in rawBlogs.take(8)) {
        if (b is! Map) continue;
        final title = _nonEmpty(b['title']);
        final contents = _nonEmpty(b['contents']);
        if (title == null && contents == null) continue;
        final bPhotos = <String>[];
        if (b['photos'] is List) {
          for (final p in (b['photos'] as List).take(4)) {
            if (p is! Map) continue;
            final thumb = PlacesClient._kakaoThumb(_nonEmpty(p['url']));
            if (thumb != null) bPhotos.add(thumb);
          }
        }
        blogReviews.add(
          KakaoBlogReview(
            title: title ?? '',
            contents: contents ?? '',
            author: _nonEmpty(b['author']) ?? '블로그',
            date: _shortDate(_nonEmpty(b['registered_at'])),
            url: _nonEmpty(b['origin_url']),
            photos: bPhotos,
          ),
        );
      }
    }

    return KakaoPlaceDetail(
      aiTitle: aiTitle,
      aiSummary: aiSummary,
      aiKeywords: aiKeywords,
      priceLevel: priceLevel,
      openStatus: openStatus,
      openHours: openHours,
      photos: photos,
      menus: menus,
      tags: tags,
      strengths: strengths,
      visitorReviews: visitorReviews,
      blogReviews: blogReviews,
    );
  }

  final String? aiTitle;
  final String? aiSummary;
  final List<String> aiKeywords;
  final String? priceLevel;
  final String? openStatus;
  final List<String> openHours;
  final List<String> photos;
  final List<KakaoMenuItem> menus;
  final List<String> tags;
  final List<KakaoStrength> strengths;
  final List<KakaoVisitorReview> visitorReviews;
  final List<KakaoBlogReview> blogReviews;

  /// 카드 한 줄에 보여 줄 요약 문구.
  String? get oneLiner {
    if (aiTitle != null && aiTitle!.isNotEmpty) return aiTitle;
    if (visitorReviews.isNotEmpty) {
      return visitorReviews.first.contents.replaceAll(RegExp(r'\s+'), ' ');
    }
    if (blogReviews.isNotEmpty && blogReviews.first.title.isNotEmpty) {
      return blogReviews.first.title;
    }
    return null;
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _shortDate(String? raw) {
    if (raw == null || raw.length < 10) return raw;
    return raw.substring(0, 10);
  }
}

class KakaoMenuItem {
  const KakaoMenuItem({
    required this.name,
    this.price,
    this.description,
    this.recommend = false,
  });

  final String name;
  final int? price;
  final String? description;
  final bool recommend;
}

class KakaoStrength {
  const KakaoStrength({required this.name, required this.count});

  final String name;
  final int count;
}

class KakaoVisitorReview {
  const KakaoVisitorReview({
    required this.author,
    required this.rating,
    required this.contents,
    this.date,
    this.photos = const [],
  });

  final String author;
  final int rating;
  final String contents;
  final String? date;
  final List<String> photos;
}

class KakaoBlogReview {
  const KakaoBlogReview({
    required this.title,
    required this.contents,
    required this.author,
    this.date,
    this.url,
    this.photos = const [],
  });

  final String title;
  final String contents;
  final String author;
  final String? date;
  final String? url;
  final List<String> photos;
}
