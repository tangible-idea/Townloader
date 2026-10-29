import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/saved_link.dart';
import '../services/links_store.dart';

class MapsException implements Exception {
  MapsException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// 세션이 끝났거나 지워졌으면 true. 다시 로그인해야 한다.
  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// 로그인한 세션. [token] 은 Worker 가 발급한 것이고 구글·Apple 토큰이 아니다.
class MapsSession {
  const MapsSession({required this.token, required this.provider, this.email});

  factory MapsSession.fromJson(Map<String, dynamic> json) => MapsSession(
    token: json['token'] as String,
    provider: json['provider'] as String? ?? '',
    email: json['email'] as String?,
  );

  final String token;
  final String provider;
  final String? email;

  Map<String, Object?> toJson() => {
    'token': token,
    'provider': provider,
    'email': email,
  };
}

/// 공개한 카테고리 하나.
class MapShare {
  const MapShare({required this.id, required this.category, required this.url});

  factory MapShare.fromJson(Map<String, dynamic> json) => MapShare(
    id: json['id'] as String,
    category: json['category'] as String,
    url: json['url'] as String,
  );

  final String id;
  final String category;
  final String url;
}

/// 공유 링크로 받은 지도. 장소와 원문 링크만 있다.
class PublicMap {
  const PublicMap({required this.category, required this.links});

  /// 글마다 [SavedLink] 하나로 만들어 지도 화면을 그대로 쓴다. 예전 응답처럼 `posts` 가
  /// 없으면 같은 원문 주소의 장소를 글 하나로 묶는다.
  factory PublicMap.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String? ?? '';
    final rawPosts = json['posts'] as List? ?? const [];
    final posts = <SavedLink>[
      for (final raw in rawPosts)
        if (raw is Map<String, dynamic>)
          SavedLink(
            code: raw['url'] as String? ?? '',
            url: raw['url'] as String? ?? '',
            category: category,
            savedAt: DateTime.fromMillisecondsSinceEpoch(0),
            status: LinkStatus.ready,
            title: raw['title'] as String?,
            author: raw['author'] as String?,
            caption: raw['caption'] as String?,
            coverUrl: raw['coverUrl'] as String?,
            imageUrls: [
              for (final url in raw['imageUrls'] as List? ?? const [])
                if (url is String) url,
            ],
          ),
    ];
    final byUrl = <String, SavedLink>{for (final post in posts) post.url: post};
    for (final raw in json['places'] as List? ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final url = raw['url'] as String? ?? '';
      final postIndex = raw['post'];
      final owner =
          postIndex is int && postIndex < posts.length
              ? posts[postIndex]
              : byUrl[url];
      final photo = raw['photo'] as String?;
      final imageIndex =
          owner == null || photo == null ? -1 : owner.imageUrls.indexOf(photo);
      final place = SavedPlace(
        name: raw['name'] as String? ?? '',
        lat: (raw['lat'] as num).toDouble(),
        lng: (raw['lng'] as num).toDouble(),
        source: PlaceSource.tag,
        address: raw['address'] as String?,
        category: raw['category'] as String?,
        phone: raw['phone'] as String?,
        photoUrl: imageIndex < 0 ? photo : null,
        placeUrl: raw['placeUrl'] as String?,
        rating: (raw['rating'] as num?)?.toDouble(),
        reviewCount: (raw['reviewCount'] as num?)?.toInt(),
        imageIndex: imageIndex < 0 ? null : imageIndex,
        approximate: raw['approximate'] == true,
      );
      final key = owner?.url ?? url;
      final link = byUrl[key];
      byUrl[key] =
          link == null
              ? SavedLink(
                code: url,
                url: url,
                category: category,
                savedAt: DateTime.fromMillisecondsSinceEpoch(0),
                status: LinkStatus.ready,
                author: raw['author'] as String?,
                places: [place],
              )
              : link.copyWith(places: [...link.places, place]);
    }
    return PublicMap(category: category, links: byUrl.values.toList());
  }

  final String category;
  final List<SavedLink> links;
}

/// 지도 공유·동기화 Worker(`maps/`)를 부른다.
class MapsClient {
  MapsClient({String? baseUrl, http.Client? httpClient})
    : _baseUrl = baseUrl ?? AppConfig.mapsUrl,
      _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  static const Duration timeout = Duration(seconds: 30);

  /// 공유 링크면 지도 ID 를, 아니면 null 을 돌려준다.
  String? shareIdOf(Uri uri) {
    final base = Uri.parse(_baseUrl);
    if (uri.host != base.host) return null;
    final match = RegExp(r'^/m/([A-Za-z0-9]{6,32})/?$').firstMatch(uri.path);
    return match?.group(1);
  }

  /// 구글·Apple 이 준 ID 토큰을 Worker 세션으로 바꾼다.
  Future<MapsSession> signIn({
    required String provider,
    required String idToken,
  }) async {
    final json = await _send(
      'POST',
      '/api/session',
      body: {'provider': provider, 'idToken': idToken},
    );
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    return MapsSession(
      token: json['token'] as String,
      provider: provider,
      email: user['email'] as String?,
    );
  }

  Future<void> signOut(MapsSession session) =>
      _send('DELETE', '/api/session', session: session);

  Future<void> deleteAccount(MapsSession session) =>
      _send('DELETE', '/api/account', session: session);

  /// 서버에 저장한 링크. 처음 로그인했으면 null.
  Future<LinksData?> download(MapsSession session) async {
    final json = await _send('GET', '/api/data', session: session);
    final data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    return LinksData(
      categories: [
        for (final name in data['categories'] as List? ?? const [])
          if (name is String) name,
      ],
      links: [
        for (final link in data['links'] as List? ?? const [])
          if (link is Map<String, dynamic>) SavedLink.fromJson(link),
      ],
    );
  }

  Future<void> upload(MapsSession session, LinksData data) => _send(
    'PUT',
    '/api/data',
    session: session,
    body: {
      'categories': data.categories,
      'links': [for (final link in data.links) link.toJson()],
    },
  );

  Future<List<MapShare>> shares(MapsSession session) async {
    final json = await _send('GET', '/api/shares', session: session);
    return [
      for (final share in json['shares'] as List? ?? const [])
        if (share is Map<String, dynamic>) MapShare.fromJson(share),
    ];
  }

  /// [category] 를 public 으로 바꾸고 공유 링크를 받는다. 이미 공개했으면 같은 링크다.
  Future<MapShare> share(MapsSession session, String category) async =>
      MapShare.fromJson(
        await _send(
          'POST',
          '/api/shares',
          session: session,
          body: {'category': category},
        ),
      );

  Future<void> unshare(MapsSession session, String id) =>
      _send('DELETE', '/api/shares/$id', session: session);

  /// 공유 링크의 지도. 로그인하지 않아도 된다.
  Future<PublicMap> publicMap(String id) async =>
      PublicMap.fromJson(await _send('GET', '/m/$id.json'));

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    MapsSession? session,
    Object? body,
  }) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers['accept'] = 'application/json';
    if (session != null) {
      request.headers['authorization'] = 'Bearer ${session.token}';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw MapsException('서버 응답이 너무 늦습니다. 잠시 후 다시 시도해 주세요.');
    } catch (_) {
      throw MapsException('서버에 연결하지 못했습니다. 네트워크를 확인해 주세요.');
    }

    if (response.statusCode != 200) {
      throw MapsException(switch (response.statusCode) {
        401 => '로그인이 만료되었습니다. 다시 로그인해 주세요.',
        404 => '공유가 끝났거나 없는 지도입니다.',
        413 => '저장한 링크가 너무 많아 동기화하지 못했습니다.',
        _ => '서버 오류입니다 (HTTP ${response.statusCode}).',
      }, statusCode: response.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  void close() => _http.close();
}
