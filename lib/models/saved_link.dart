/// 장소를 어디서 찾았는지.
enum PlaceSource {
  /// 인스타그램 위치 태그.
  tag,

  /// 사진에 적힌 글자.
  image,

  /// 본문.
  caption;

  static PlaceSource parse(Object? value) => PlaceSource.values.firstWhere(
    (source) => source.name == value,
    orElse: () => PlaceSource.caption,
  );
}

/// 저장한 글에서 찾은 장소 하나. `/places` 응답 형식과 같다.
class SavedPlace {
  const SavedPlace({
    required this.name,
    required this.lat,
    required this.lng,
    required this.source,
    this.address,
    this.category,
    this.phone,
    this.photoUrl,
    this.placeUrl,
    this.rating,
    this.reviewCount,
    this.summary,
    this.imageIndex,
    this.approximate = false,
  });

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
    name: json['name'] as String? ?? '',
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    source: PlaceSource.parse(json['source']),
    address: json['address'] as String?,
    category: json['category'] as String?,
    phone: json['phone'] as String?,
    photoUrl: json['photoUrl'] as String?,
    placeUrl: json['placeUrl'] as String?,
    rating: (json['rating'] as num?)?.toDouble(),
    reviewCount: (json['reviewCount'] as num?)?.toInt(),
    summary: json['summary'] as String?,
    imageIndex: json['imageIndex'] as int?,
    approximate: json['approximate'] == true,
  );

  final String name;
  final double lat;
  final double lng;
  final PlaceSource source;
  final String? address;

  /// 카카오맵 업종(예: "카페", "고궁,궁").
  final String? category;

  /// 전화번호.
  final String? phone;

  /// 카카오맵에서 가져온 장소 대표 사진 썸네일 주소.
  final String? photoUrl;

  /// 카카오맵 장소 상세 페이지 주소.
  final String? placeUrl;

  /// 카카오맵 별점(0보다 클 때만).
  final double? rating;

  /// 카카오맵 후기·평가 수(0보다 클 때만).
  final int? reviewCount;

  /// 카카오맵 AI 한줄 요약 또는 대표 후기 한 줄.
  final String? summary;

  /// 장소 이름이 적힌 사진의 순번. 사진에서 찾은 장소만 있다.
  final int? imageIndex;

  /// 장소를 못 찾고 동네 좌표로 대신했으면 true.
  final bool approximate;

  /// 카카오맵 상세 정보가 이미 채워졌는지.
  bool get hasKakaoDetails =>
      photoUrl != null ||
      category != null ||
      placeUrl != null ||
      phone != null ||
      rating != null;

  /// [placeUrl] 에서 카카오맵 장소 ID(`confirm_id`)를 뽑는다.
  String? get kakaoId {
    final url = placeUrl;
    if (url == null || url.isEmpty) return null;
    final match = RegExp(r'place\.map\.kakao\.com/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  SavedPlace copyWith({
    String? address,
    String? category,
    String? phone,
    String? photoUrl,
    String? placeUrl,
    double? rating,
    int? reviewCount,
    String? summary,
  }) => SavedPlace(
    name: name,
    lat: lat,
    lng: lng,
    source: source,
    address: address ?? this.address,
    category: category ?? this.category,
    phone: phone ?? this.phone,
    photoUrl: photoUrl ?? this.photoUrl,
    placeUrl: placeUrl ?? this.placeUrl,
    rating: rating ?? this.rating,
    reviewCount: reviewCount ?? this.reviewCount,
    summary: summary ?? this.summary,
    imageIndex: imageIndex,
    approximate: approximate,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'source': source.name,
    'address': address,
    if (category != null) 'category': category,
    if (phone != null) 'phone': phone,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (placeUrl != null) 'placeUrl': placeUrl,
    if (rating != null) 'rating': rating,
    if (reviewCount != null) 'reviewCount': reviewCount,
    if (summary != null) 'summary': summary,
    'imageIndex': imageIndex,
    'approximate': approximate,
  };
}

enum LinkStatus { analyzing, ready, failed }

/// Links 탭에 저장한 글 하나와 그 글에서 찾은 장소들.
class SavedLink {
  const SavedLink({
    required this.code,
    required this.url,
    required this.category,
    required this.savedAt,
    this.status = LinkStatus.analyzing,
    this.title,
    this.author,
    this.caption,
    this.coverUrl,
    this.imageUrls = const [],
    this.places = const [],
    this.error,
  });

  factory SavedLink.fromJson(Map<String, dynamic> json) => SavedLink(
    code: json['code'] as String,
    url: json['url'] as String,
    category: json['category'] as String? ?? '',
    savedAt:
        DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
    // 분석 도중 앱이 꺼졌으면 다시 분석하도록 실패로 둔다.
    status: switch (json['status']) {
      'ready' => LinkStatus.ready,
      _ => LinkStatus.failed,
    },
    title: json['title'] as String?,
    author: json['author'] as String?,
    caption: json['caption'] as String?,
    coverUrl: json['coverUrl'] as String?,
    imageUrls: [
      for (final url in json['imageUrls'] as List? ?? const [])
        if (url is String) url,
    ],
    places: [
      for (final place in json['places'] as List? ?? const [])
        if (place is Map<String, dynamic>) SavedPlace.fromJson(place),
    ],
    error: json['error'] as String?,
  );

  /// 게시물 단축코드. 같은 글을 두 번 저장하지 않는 기준이다.
  final String code;
  final String url;
  final String category;
  final DateTime savedAt;
  final LinkStatus status;

  /// 글을 대표하는 짧은 제목("예쁜 보은 카페 모음.ZIP"). 분석이 끝나면 AI 가 짓는다.
  final String? title;
  final String? author;
  final String? caption;
  final String? coverUrl;

  /// 캐러셀 사진들의 썸네일. [SavedPlace.imageIndex] 로 장소마다 사진을 붙인다.
  final List<String> imageUrls;
  final List<SavedPlace> places;
  final String? error;

  /// 장소에 붙일 사진. 카카오맵 장소 사진이 있으면 먼저 쓰고, 없으면 장소가 적힌 사진이나
  /// 글의 대표 사진을 쓴다.
  String? photoFor(SavedPlace place) {
    if (place.photoUrl != null && place.photoUrl!.isNotEmpty) {
      return place.photoUrl;
    }
    final index = place.imageIndex;
    if (index != null && index >= 0 && index < imageUrls.length) {
      return imageUrls[index];
    }
    return coverUrl;
  }

  SavedLink copyWith({
    String? category,
    LinkStatus? status,
    String? title,
    String? author,
    String? caption,
    String? coverUrl,
    List<String>? imageUrls,
    List<SavedPlace>? places,
    String? error,
    bool clearError = false,
  }) => SavedLink(
    code: code,
    url: url,
    category: category ?? this.category,
    savedAt: savedAt,
    status: status ?? this.status,
    title: title ?? this.title,
    author: author ?? this.author,
    caption: caption ?? this.caption,
    coverUrl: coverUrl ?? this.coverUrl,
    imageUrls: imageUrls ?? this.imageUrls,
    places: places ?? this.places,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, Object?> toJson() => {
    'code': code,
    'url': url,
    'category': category,
    'savedAt': savedAt.toIso8601String(),
    'status': status.name,
    'title': title,
    'author': author,
    'caption': caption,
    'coverUrl': coverUrl,
    'imageUrls': imageUrls,
    'places': [for (final place in places) place.toJson()],
    'error': error,
  };
}
