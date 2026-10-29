import '../models/ig_asset.dart';
import '../models/ig_post.dart';
import '../models/ig_user.dart';
import '../models/threads_thread.dart';

/// HikerAPI 의 원시 미디어 JSON 을 앱 모델로 옮긴다.
///
/// 같은 게시물이라도 엔드포인트(v1/v2/gql, 피드/스토리)마다 필드 구성이 조금씩
/// 다르다. 그래서 모든 필드를 선택적으로 읽고, 하나라도 쓸 수 있는 URL 이 나오면
/// 다운로드 후보로 넣는 방식으로 처리한다.
class MediaParser {
  MediaParser._();

  /// `media_type` 은 1=사진, 2=동영상, 8=캐러셀이다.
  static const int _typePhoto = 1;
  static const int _typeVideo = 2;
  static const int _typeCarousel = 8;

  static IgPost? parsePost(Map<String, dynamic>? json) {
    if (json == null) return null;

    final pk = _id(json['pk']) ?? _id(json['id']);
    if (pk == null) return null;

    final mediaType = _int(json['media_type']) ?? _typePhoto;
    final productType = (json['product_type'] as String?)?.toLowerCase() ?? '';
    final kind = _kindOf(mediaType, productType);

    final items = mediaType == _typeCarousel
        ? _carouselItems(json, fallbackId: pk)
        : [_singleItem(json, id: pk)];

    return IgPost(
      pk: pk,
      code: json['code'] as String?,
      kind: kind,
      user: IgUser.fromJson(json['user'] as Map<String, dynamic>?),
      caption: _caption(json),
      takenAt: _dateTime(json['taken_at_ts'] ?? json['taken_at']),
      likeCount: _int(json['like_count']),
      viewCount: _int(json['view_count']),
      playCount: _int(json['play_count']),
      commentCount: _int(json['comment_count']),
      location: _location(json['location']),
      items: items.where((item) => item.hasAssets).toList(),
    );
  }

  /// 위치 태그. 이름과 좌표가 다 있어야 쓴다(좌표 없이 이름만 오는 태그도 있다).
  static IgLocation? _location(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final name = (value['name'] as String?)?.trim();
    final lat = _double(value['lat']);
    final lng = _double(value['lng']);
    if (name == null || name.isEmpty || lat == null || lng == null) return null;
    final address = (value['address'] as String?)?.trim();
    return IgLocation(
      name: name,
      lat: lat,
      lng: lng,
      address: address == null || address.isEmpty ? null : address,
    );
  }

  /// 게시물 목록 응답을 한 번에 변환한다. 해석에 실패한 항목은 건너뛴다.
  static List<IgPost> parsePosts(Iterable<dynamic> raw) {
    final posts = <IgPost>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final post = parsePost(entry);
      if (post != null && post.hasDownloadableAssets) posts.add(post);
    }
    return posts;
  }

  static PostKind _kindOf(int mediaType, String productType) {
    if (productType == 'story') return PostKind.story;
    if (mediaType == _typeCarousel) return PostKind.carousel;
    if (mediaType == _typeVideo) {
      return productType == 'clips' ? PostKind.reel : PostKind.video;
    }
    return PostKind.photo;
  }

  /// 캐러셀 자식들. 응답에 따라 `resources` 또는 `carousel_media` 로 온다.
  static List<IgItem> _carouselItems(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    final raw = json['resources'] ?? json['carousel_media'];
    if (raw is! List || raw.isEmpty) {
      // 자식 목록이 비어 있으면 부모에 붙은 URL 이라도 살린다.
      return [_singleItem(json, id: fallbackId)];
    }

    final items = <IgItem>[];
    for (var index = 0; index < raw.length; index++) {
      final child = raw[index];
      if (child is! Map<String, dynamic>) continue;
      final id = _id(child['pk']) ?? _id(child['id']) ?? '$fallbackId-$index';
      items.add(_singleItem(child, id: id));
    }
    return items;
  }

  /// 미디어 객체 하나에서 다운로드 가능한 변형들을 뽑아낸다.
  static IgItem _singleItem(Map<String, dynamic> json, {required String id}) {
    final mediaType = _int(json['media_type']) ?? _typePhoto;
    final isVideo = mediaType == _typeVideo;
    final thumbnailUrl = json['thumbnail_url'] as String?;
    final duration = _double(json['video_duration']);

    final variants = isVideo
        ? _videoVariants(json, duration: duration)
        : _photoVariants(json, thumbnailUrl: thumbnailUrl);

    return IgItem(
      id: id,
      kind: isVideo ? AssetKind.video : AssetKind.photo,
      variants: variants,
      thumbnailUrl: thumbnailUrl ?? (isVideo ? null : variants.firstOrNull?.url),
      durationSeconds: duration,
    );
  }

  static List<IgAsset> _videoVariants(
    Map<String, dynamic> json, {
    double? duration,
  }) {
    final assets = <IgAsset>[];
    final seen = <String>{};

    // 해상도별 목록이 있으면 그대로 쓴다. 스토리 응답에는 이 필드가 없다.
    final versions = json['video_versions'];
    if (versions is List) {
      for (final entry in versions) {
        if (entry is! Map<String, dynamic>) continue;
        final url = entry['url'] as String?;
        if (url == null || url.isEmpty || !seen.add(url)) continue;
        assets.add(
          IgAsset(
            kind: AssetKind.video,
            url: url,
            width: _int(entry['width']),
            height: _int(entry['height']),
            bandwidth: _int(entry['bandwidth']),
            durationSeconds: duration,
          ),
        );
      }
    }

    // 단일 `video_url` 은 대개 최고 화질과 같은 파일이라 중복 URL 은 걸러진다.
    final single = json['video_url'] as String?;
    if (single != null && single.isNotEmpty && seen.add(single)) {
      assets.add(
        IgAsset(
          kind: AssetKind.video,
          url: single,
          width: _int(json['original_width']),
          height: _int(json['original_height']),
          durationSeconds: duration,
        ),
      );
    }

    return assets;
  }

  static List<IgAsset> _photoVariants(
    Map<String, dynamic> json, {
    String? thumbnailUrl,
  }) {
    final assets = <IgAsset>[];
    final seen = <String>{};

    final versions = json['image_versions'] ?? json['image_versions2'];
    final candidates = versions is Map<String, dynamic>
        ? versions['candidates'] // v2 형태는 candidates 배열로 한 겹 더 감싼다
        : versions;

    if (candidates is List) {
      for (final entry in candidates) {
        if (entry is! Map<String, dynamic>) continue;
        final url = entry['url'] as String?;
        if (url == null || url.isEmpty || !seen.add(url)) continue;
        assets.add(
          IgAsset(
            kind: AssetKind.photo,
            url: url,
            width: _int(entry['width']),
            height: _int(entry['height']),
          ),
        );
      }
    }

    // 스토리 사진에는 image_versions 가 없고 thumbnail_url 이 곧 원본이다.
    if (assets.isEmpty && thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      assets.add(IgAsset(kind: AssetKind.photo, url: thumbnailUrl));
    }

    return assets;
  }

  static String? _caption(Map<String, dynamic> json) {
    final text = json['caption_text'];
    if (text is String && text.trim().isNotEmpty) return text.trim();

    final caption = json['caption'];
    if (caption is Map<String, dynamic>) {
      final inner = caption['text'];
      if (inner is String && inner.trim().isNotEmpty) return inner.trim();
    }
    return null;
  }

  /// 큰 정수가 double 로 뭉개지지 않도록 ID 는 항상 문자열로 다룬다.
  static String? _id(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    if (text.isEmpty || text == 'null') return null;
    // `3975089864169193671_528817151` 형태에서는 앞부분만 쓴다.
    final underscore = text.indexOf('_');
    return underscore > 0 ? text.substring(0, underscore) : text;
  }

  static int? _int(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };

  static double? _double(Object? value) => switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };

  /// `/v2/media/comments` 응답을 스레드 트리의 댓글 노드로 바꾼다.
  ///
  /// 첫 묶음(약 15개)만 오고, 댓글마다 대댓글 몇 개가 `preview_child_comments` 로
  /// 미리 실린다. 대댓글은 한 단계 더 들여 쓴다. 글이 없는 댓글(스티커 등)은 뺀다.
  static ({List<ThreadNode> nodes, bool hasMore}) parseComments(
    Map<String, dynamic>? json,
  ) {
    final response = json?['response'];
    final body = response is Map<String, dynamic> ? response : json;
    final comments = body?['comments'];
    final nodes = <ThreadNode>[];
    if (comments is List) {
      for (final comment in comments.whereType<Map<String, dynamic>>()) {
        final node = _commentNode(comment, depth: 1);
        if (node == null) continue;
        nodes.add(node);
        final children = comment['preview_child_comments'];
        if (children is List) {
          for (final child in children.whereType<Map<String, dynamic>>()) {
            final childNode = _commentNode(child, depth: 2);
            if (childNode != null) nodes.add(childNode);
          }
        }
      }
    }
    return (nodes: nodes, hasMore: body?['has_more_comments'] == true);
  }

  static ThreadNode? _commentNode(
    Map<String, dynamic> json, {
    required int depth,
  }) {
    final pk = json['pk']?.toString();
    final text = (json['text'] as String?)?.trim();
    if (pk == null || pk.isEmpty || text == null || text.isEmpty) return null;
    return ThreadNode(
      post: IgPost(
        pk: pk,
        kind: PostKind.photo,
        user: IgUser.fromJson(json['user'] as Map<String, dynamic>?),
        caption: text,
        takenAt: _dateTime(json['created_at_utc'] ?? json['created_at']),
        items: const [],
      ),
      role: ThreadRole.reply,
      depth: depth,
    );
  }

  /// `taken_at` 은 엔드포인트에 따라 유닉스 초 또는 ISO 8601 문자열로 온다.
  static DateTime? _dateTime(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt() * 1000,
        isUtc: true,
      ).toLocal();
    }
    if (value is String && value.isNotEmpty) {
      final epoch = int.tryParse(value);
      if (epoch != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          epoch * 1000,
          isUtc: true,
        ).toLocal();
      }
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
