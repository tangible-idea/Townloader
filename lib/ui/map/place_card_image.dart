import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

/// 지도 위에 띄우는 장소 카드(사진 + 이름 + 한 줄 + 꼬리)를 PNG 로 그린다.
///
/// Mapbox Flutter SDK 는 지도 좌표에 위젯을 붙일 수 없어서, 카드를 그림으로 만들어
/// 아이콘으로 올린다. 화면 배율([pixelRatio])로 그리면 iOS·Android 모두 카드가 논리
/// 크기 그대로 보인다(SDK 가 PNG 를 화면 배율 이미지로 읽는다).
class PlaceCardImage {
  PlaceCardImage({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Map<String, Future<ui.Image?>> _photos = {};

  static const double width = 128;
  static const double _pad = 6;
  static const double _photoHeight = 84;
  static const double _radius = 12;
  static const double _tail = 9;

  Future<Uint8List> render({
    required String title,
    required String subtitle,
    required String? photoUrl,
    required double pixelRatio,
  }) async {
    final photo = photoUrl == null ? null : await _photo(photoUrl, pixelRatio);

    final titlePainter = _text(
      title,
      13.5,
      FontWeight.w700,
      const Color(0xFF1B1B1F),
    );
    final subtitlePainter = _text(
      subtitle,
      11.5,
      FontWeight.w500,
      const Color(0xFF5F6368),
    );
    const innerWidth = width - _pad * 2;
    titlePainter.layout(maxWidth: innerWidth - 4);
    subtitlePainter.layout(maxWidth: innerWidth - 4);

    final cardHeight =
        _pad +
        _photoHeight +
        7 +
        titlePainter.height +
        2 +
        subtitlePainter.height +
        8;
    final height = cardHeight + _tail;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);

    // 그림자 → 카드 → 꼬리 순서로 그린다. 꼬리 끝이 좌표를 가리킨다.
    final card = RRect.fromRectAndRadius(
      const Offset(0, 0) & Size(width, cardHeight),
      const Radius.circular(_radius),
    );
    final tail = Path()
      ..moveTo(width / 2 - _tail, cardHeight - 1)
      ..lineTo(width / 2, height)
      ..lineTo(width / 2 + _tail, cardHeight - 1)
      ..close();
    final shape = Path()
      ..addRRect(card)
      ..addPath(tail, Offset.zero);
    canvas.drawShadow(shape, const Color(0x55000000), 3, false);
    canvas.drawPath(shape, Paint()..color = const Color(0xFFFFFFFF));

    final photoRect = RRect.fromRectAndRadius(
      const Offset(_pad, _pad) & const Size(innerWidth, _photoHeight),
      const Radius.circular(_radius - 4),
    );
    canvas.save();
    canvas.clipRRect(photoRect);
    if (photo != null) {
      paintImage(
        canvas: canvas,
        rect: photoRect.outerRect,
        image: photo,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else {
      canvas.drawRect(
        photoRect.outerRect,
        Paint()..color = const Color(0xFFE8EEF0),
      );
    }
    canvas.restore();

    var y = _pad + _photoHeight + 7;
    titlePainter.paint(canvas, Offset(_pad + 2, y));
    y += titlePainter.height + 2;
    subtitlePainter.paint(canvas, Offset(_pad + 2, y));

    final image = await recorder.endRecording().toImage(
      (width * pixelRatio).ceil(),
      (height * pixelRatio).ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  static TextPainter _text(
    String text,
    double size,
    FontWeight weight,
    Color color,
  ) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.25,
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  );

  /// 같은 사진은 한 번만 받는다. 받지 못하면 회색 칸으로 그린다.
  Future<ui.Image?> _photo(String url, double pixelRatio) =>
      _photos.putIfAbsent(url, () async {
        try {
          final response = await _http.get(Uri.parse(url));
          if (response.statusCode != 200) return null;
          final codec = await ui.instantiateImageCodec(
            response.bodyBytes,
            targetWidth: (width * pixelRatio).round(),
          );
          return (await codec.getNextFrame()).image;
        } on Exception {
          return null;
        }
      });

  void close() => _http.close();
}
