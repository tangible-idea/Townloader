import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/places_client.dart';
import '../models/ig_post.dart';
import '../models/saved_link.dart';
import 'text_recognizer.dart';

/// 글 하나에서 장소를 찾는다.
///
/// 사진은 기기 안에서 글자만 읽고(OCR), 위치 태그·본문·읽은 글자 줄을 `/places` 로 보낸다.
/// 사진 자체는 서버로 보내지 않는다.
class LinkAnalyzer {
  LinkAnalyzer({
    PlacesClient? places,
    TextRecognizer recognizer = const TextRecognizer(),
    http.Client? httpClient,
  }) : _places = places ?? PlacesClient(),
       _recognizer = recognizer,
       _http = httpClient ?? http.Client();

  final PlacesClient _places;
  final TextRecognizer _recognizer;
  final http.Client _http;

  /// 캐러셀은 최대 20장. 서버도 그 이상은 받지 않는다.
  static const int maxImages = 20;

  /// 사진을 한 번에 몇 장씩 받아 읽을지.
  static const int _batch = 4;

  /// 글마다 첫 사진에서 읽은 큰 글씨 줄. 제목을 지을 때 쓴다(사진에 제목이 적힌 글이 많다).
  final Map<String, List<String>> _headlines = {};

  /// [post] 의 사진 순서대로 쓸 썸네일 주소. [SavedPlace.imageIndex] 가 이 순번이다.
  static List<String> imageUrlsOf(IgPost post) => [
    for (final item in post.items.take(maxImages))
      item.thumbnailUrl ?? item.best?.url ?? '',
  ];

  Future<List<SavedPlace>> analyze(IgPost post, {required bool isKo}) async {
    final urls = imageUrlsOf(post);
    final images = <Map<String, Object?>>[];
    for (var start = 0; start < urls.length; start += _batch) {
      final batch = [
        for (var i = start; i < urls.length && i < start + _batch; i++) i,
      ];
      final results = await Future.wait(batch.map((i) => _readImage(urls[i])));
      for (final (offset, lines) in results.indexed) {
        if (lines.isEmpty) continue;
        if (batch[offset] == 0) {
          _headlines[post.code ?? post.pk] = headlinesOf(lines);
        }
        images.add({
          'index': batch[offset],
          'lines': [for (final line in lines) line.toJson()],
        });
      }
    }

    final location = post.location;
    final found = await _places.findPlaces({
      'code': post.code ?? post.pk,
      'lang': isKo ? 'ko' : 'en',
      'tag': location == null
          ? null
          : {
              'name': location.name,
              'lat': location.lat,
              'lng': location.lng,
              'address': location.address,
            },
      'caption': post.caption ?? '',
      'images': images,
    });
    return Future.wait(found.map(_places.enrichPlace));
  }

  /// 이미 저장된 장소에 카카오맵 사진·업종·별점 등을 채운다.
  Future<SavedPlace> enrichPlace(SavedPlace place) =>
      _places.enrichPlace(place);

  /// 글자가 큰 줄부터 몇 줄. 표지 사진의 제목이 대개 가장 크다.
  static List<String> headlinesOf(List<OcrLine> lines) {
    final sorted = [...lines]..sort((a, b) => b.height.compareTo(a.height));
    return [for (final line in sorted.take(4)) line.text];
  }

  /// 저장한 글의 짧은 대표 제목. 이번 실행에서 분석한 글이면 표지 글씨도 함께 보낸다.
  Future<String?> title(SavedLink link, {required bool isKo}) =>
      _places.title(
        code: link.code,
        isKo: isKo,
        caption: link.caption,
        places: [for (final place in link.places) place.name],
        lines: _headlines.remove(link.code) ?? const [],
      );

  /// 사진 한 장의 글자 줄. 받지 못하거나 읽지 못하면 빈 목록이다.
  Future<List<OcrLine>> _readImage(String url) async {
    if (url.isEmpty) return const [];
    final Uint8List bytes;
    try {
      final response = await _http.get(Uri.parse(url));
      if (response.statusCode != 200) return const [];
      bytes = response.bodyBytes;
    } on Exception {
      return const [];
    }
    return _recognizer.recognize(bytes);
  }

  void close() {
    _places.close();
    _http.close();
  }
}
