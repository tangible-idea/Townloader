import 'ig_asset.dart';
import 'ig_user.dart';
import 'media_source.dart';

/// 게시물의 종류. HikerAPI 의 `media_type` 과 `product_type` 을 합쳐서 판정한다.
enum PostKind { photo, video, reel, carousel, story }

extension PostKindLabel on PostKind {
  String get label => switch (this) {
    PostKind.photo => '사진',
    PostKind.video => '동영상',
    PostKind.reel => '릴스',
    PostKind.carousel => '캐러셀',
    PostKind.story => '스토리',
  };

  String localizedLabel([bool isKo = true]) => isKo
      ? label
      : switch (this) {
          PostKind.photo => 'Photo',
          PostKind.video => 'Video',
          PostKind.reel => 'Reel',
          PostKind.carousel => 'Carousel',
          PostKind.story => 'Story',
        };
}

/// 게시물 안의 항목 하나. 캐러셀이면 슬라이드 한 장, 그 외에는 항목이 하나뿐이다.
class IgItem {
  IgItem({
    required this.id,
    required this.kind,
    required List<IgAsset> variants,
    this.thumbnailUrl,
    this.durationSeconds,
  }) : variants = List.unmodifiable(
         [...variants]
           ..sort((a, b) => b.qualityScore.compareTo(a.qualityScore)),
       );

  final String id;
  final AssetKind kind;

  /// 화질 내림차순으로 정렬된 다운로드 후보들.
  final List<IgAsset> variants;
  final String? thumbnailUrl;
  final double? durationSeconds;

  bool get isVideo => kind == AssetKind.video;
  bool get hasAssets => variants.isNotEmpty;

  IgAsset? get best => variants.isEmpty ? null : variants.first;
  IgAsset? get smallest => variants.isEmpty ? null : variants.last;

  IgItem copyWith({
    String? id,
    AssetKind? kind,
    List<IgAsset>? variants,
    String? thumbnailUrl,
    double? durationSeconds,
  }) {
    return IgItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      variants: variants ?? this.variants,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}

/// 게시물에 붙은 위치 태그. 글쓴이가 직접 고른 장소라 좌표가 정확하다.
class IgLocation {
  const IgLocation({
    required this.name,
    required this.lat,
    required this.lng,
    this.address,
  });

  final String name;
  final double lat;
  final double lng;
  final String? address;
}

/// 다운로드 대상이 되는 게시물 하나.
class IgPost {
  IgPost({
    required this.pk,
    required this.kind,
    required List<IgItem> items,
    this.source = MediaSource.instagram,
    this.code,
    this.user,
    this.caption,
    this.takenAt,
    this.likeCount,
    this.viewCount,
    this.playCount,
    this.commentCount,
    this.location,
  }) : items = List.unmodifiable(items);

  final String pk;
  final MediaSource source;
  final String? code;
  final PostKind kind;
  final IgUser? user;
  final String? caption;
  final DateTime? takenAt;
  final int? likeCount;
  final int? viewCount;
  final int? playCount;
  final int? commentCount;
  final IgLocation? location;
  final List<IgItem> items;

  IgPost copyWith({
    String? pk,
    MediaSource? source,
    String? code,
    PostKind? kind,
    IgUser? user,
    String? caption,
    DateTime? takenAt,
    int? likeCount,
    int? viewCount,
    int? playCount,
    int? commentCount,
    IgLocation? location,
    List<IgItem>? items,
  }) {
    return IgPost(
      pk: pk ?? this.pk,
      source: source ?? this.source,
      code: code ?? this.code,
      kind: kind ?? this.kind,
      user: user ?? this.user,
      caption: caption ?? this.caption,
      takenAt: takenAt ?? this.takenAt,
      likeCount: likeCount ?? this.likeCount,
      viewCount: viewCount ?? this.viewCount,
      playCount: playCount ?? this.playCount,
      commentCount: commentCount ?? this.commentCount,
      location: location ?? this.location,
      items: items ?? this.items,
    );
  }

  /// 다운로드 가능한 항목이 하나도 없으면 화면에 실패로 표시한다.
  bool get hasDownloadableAssets => items.any((item) => item.hasAssets);

  String get authorName => user?.username ?? source.label.toLowerCase();

  String? get permalink {
    final c = code;
    if (c == null) return null;
    if (source == MediaSource.threads) {
      return 'https://www.threads.com/@$authorName/post/$c';
    }
    return switch (kind) {
      PostKind.reel => 'https://www.instagram.com/reel/$c/',
      PostKind.story => 'https://www.instagram.com/stories/$authorName/$pk/',
      _ => 'https://www.instagram.com/p/$c/',
    };
  }

  /// 목록 화면에서 대표로 보여줄 썸네일.
  String? get coverUrl {
    for (final item in items) {
      final thumb = item.thumbnailUrl;
      if (thumb != null) return thumb;
      if (!item.isVideo) {
        final asset = item.best;
        if (asset != null) return asset.url;
      }
    }
    return null;
  }
}
