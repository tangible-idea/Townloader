import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/services.dart';

import '../../services/image_disk_cache.dart';

/// 지도 위에 띄우는 장소 카드(말풍선 + 사진 + 이름 + 한 줄)를 PNG 로 그린다.
///
/// Mapbox Flutter SDK 는 지도 좌표에 위젯을 붙일 수 없어서, 카드를 그림으로 만들어
/// 아이콘으로 올린다. 화면 배율([pixelRatio])로 그리면 iOS·Android 모두 카드가 논리
/// 크기 그대로 보인다(SDK 가 PNG 를 화면 배율 이미지로 읽는다).
///
/// 말풍선은 나인패치 그림([_Bubble])을 늘려서 깐다. 카드 폭은 이름 길이에 맞춰
/// [_minContent]~[_maxContent] 사이에서 정해지고, 늘어나도 모서리·그림자·꼬리는
/// 그대로다.
class PlaceCardImage {
  /// 사진 하나가 이보다 늦으면 회색 칸으로 그려 다른 카드를 붙잡지 않는다.
  static const _photoTimeout = Duration(seconds: 8);

  final Map<String, Future<ui.Image?>> _photos = {};

  /// 사진·글자가 들어가는 칸의 폭.
  static const double _minContent = 112;
  static const double _maxContent = 168;
  static const double _photoHeight = 84;
  static const double _photoRadius = 8;

  Future<Uint8List> render({
    required String title,
    required String subtitle,
    required String? photoUrl,
    Color? markColor,
    IconData placeholderIcon = Icons.landscape_outlined,
    required double pixelRatio,
    bool waitForPhoto = true,
  }) async {
    final bubble = await _Bubble.image;
    // [waitForPhoto] 가 false 면 이미 받아 둔 사진만 쓰고, 아니면 업종 아이콘 칸으로 그린다.
    final photo = photoUrl == null
        ? null
        : waitForPhoto
        ? await _photo(photoUrl, pixelRatio)
        : await _photo(
            photoUrl,
            pixelRatio,
          ).timeout(_readyWait, onTimeout: () => null);

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
      _subtitleColor,
    );
    // 글자 칸은 양옆 2 씩 들여 쓴다. 먼저 가장 넓게 재고, 칸 폭을 정한 뒤 다시 잰다.
    titlePainter.layout(maxWidth: _maxContent - 4);
    subtitlePainter.layout(maxWidth: _maxContent - 4);
    final textWidth = titlePainter.width > subtitlePainter.width
        ? titlePainter.width
        : subtitlePainter.width;
    final contentWidth = (textWidth + 4)
        .clamp(_minContent, _maxContent)
        .ceilToDouble();
    titlePainter.layout(maxWidth: contentWidth - 4);
    subtitlePainter.layout(maxWidth: contentWidth - 4);

    final lineHeight = subtitlePainter.height;
    final contentHeight =
        _photoHeight + 7 + titlePainter.height + 2 + lineHeight + 2;
    final width = contentWidth + _Bubble.insetX;
    final height = contentHeight + _Bubble.insetY;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // 말풍선은 물리 픽셀 단위로 깔아 조각 사이에 실금이 생기지 않게 한다.
    _Bubble.paint(
      canvas,
      bubble,
      (width * pixelRatio).round(),
      (height * pixelRatio).round(),
      pixelRatio,
    );
    canvas.scale(pixelRatio);

    const left = _Bubble.contentLeft;
    const top = _Bubble.contentTop;
    final photoRect = RRect.fromRectAndRadius(
      const Offset(left, top) & Size(contentWidth, _photoHeight),
      const Radius.circular(_photoRadius),
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
      _paintPlaceholder(canvas, photoRect.outerRect, placeholderIcon);
    }
    canvas.restore();

    var y = top + _photoHeight + 7;
    titlePainter.paint(canvas, Offset(left + 2, y));
    y += titlePainter.height + 2;
    // 글 색은 몸통 오른쪽 위 모서리에 책갈피처럼 접어 보인다.
    if (markColor != null) {
      final body = _Bubble.body(width, height);
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(_Bubble.radius)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(body.right - _markSize, body.top)
          ..lineTo(body.right, body.top)
          ..lineTo(body.right, body.top + _markSize)
          ..close(),
        Paint()..color = markColor,
      );
      canvas.restore();
    }
    subtitlePainter.paint(
      canvas,
      Offset(left + 2, y + (lineHeight - subtitlePainter.height) / 2),
    );

    final image = await recorder.endRecording().toImage(
      (width * pixelRatio).round(),
      (height * pixelRatio).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// 이미 받아 둔(디스크에 있는) 사진이면 이 안에 읽힌다. 그보다 늦으면 받는 중으로 본다.
  static const _readyWait = Duration(milliseconds: 150);

  /// [photoUrl] 사진을 받아 둔다. 받았으면 true. 이 뒤의 [render] 는 바로 사진을 쓴다.
  Future<bool> loadPhoto(String photoUrl, double pixelRatio) async =>
      await _photo(photoUrl, pixelRatio) != null;

  /// 꼬리 끝이 그림 아래 가장자리에서 떨어진 거리(논리 픽셀). 아이콘을 이만큼 내려야
  /// 꼬리 끝이 좌표를 가리킨다.
  static const double tipInset = _Bubble.padBottom;

  static const _subtitleColor = Color(0xFF5F6368);

  static const double _markSize = 22;

  /// 사진이 없거나 못 받았을 때. 앱의 PhotoPlaceholder 와 같은 모양(그라데이션 + [icon],
  /// 지도에서는 업종 아이콘)이다.
  static void _paintPlaceholder(Canvas canvas, Rect rect, IconData icon) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, const [
          Color(0xFFF0F3F4),
          Color(0xFFE2E8EA),
        ]),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 30,
          color: const Color(0x735F6368),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );
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

  /// 같은 사진은 한 번만 받고, 디스크에 남겨 다음에 지도를 열 때는 바로 읽는다.
  /// 받지 못하면 회색 칸으로 그린다.
  Future<ui.Image?> _photo(String url, double pixelRatio) =>
      _photos.putIfAbsent(url, () async {
        try {
          final file = await ImageDiskCache.instance
              .fileFor(url)
              .timeout(_photoTimeout);
          final codec = await ui.instantiateImageCodec(
            await file.readAsBytes(),
            targetWidth: (_maxContent * pixelRatio).round(),
          );
          return (await codec.getNextFrame()).image;
        } catch (_) {
          await ImageDiskCache.instance.evict(url).catchError((_) {});
          return null;
        }
      });
}

/// 말풍선 나인패치 `assets/map/bubble.png` (scripts/make_map_bubble.py 로 만든다).
///
/// 숫자는 모두 논리 픽셀이고 그림은 [scale] 배율로 저장돼 있다. 가로는 꼬리 양옆의
/// 두 구간을 똑같이 늘려 꼬리가 늘 가운데에 남고, 세로는 몸통 가운데 한 구간만 늘린다.
abstract final class _Bubble {
  static const scale = 3.0;
  static const width = 82.0;
  static const height = 65.0;

  /// 늘이는 구간 [시작, 끝).
  static const stretchX = [(18.0, 30.0), (52.0, 64.0)];
  static const stretchY = [(18.0, 40.0)];

  /// 몸통 안쪽에서 사진·글자가 시작하는 곳과, 내용 칸 바깥 여백의 합.
  static const contentLeft = 11.0;
  static const contentTop = 11.0;
  static const contentRight = 11.0; // width - 71
  static const contentBottom = 18.0; // height - 47 (꼬리·그림자 포함)
  static const insetX = contentLeft + contentRight;
  static const insetY = contentTop + contentBottom;
  static const padBottom = 3.0;

  /// 몸통(그림자·꼬리 뺀 둥근 사각형)의 모서리 반지름과, [width]×[height] 로 늘렸을
  /// 때의 몸통 자리. scripts/make_map_bubble.py 의 PAD·RADIUS·TAIL_H 와 같다.
  static const radius = 12.0;
  static Rect body(double width, double height) =>
      Rect.fromLTRB(5, 5, width - 5, height - padBottom - 9);

  static final Future<ui.Image> image = () async {
    final data = await rootBundle.load('assets/map/bubble.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }();

  /// [bubble] 을 물리 픽셀 [targetWidth]×[targetHeight] 로 늘려 그린다.
  static void paint(
    Canvas canvas,
    ui.Image bubble,
    int targetWidth,
    int targetHeight,
    double pixelRatio,
  ) {
    final xs = _slices(stretchX, width, targetWidth, pixelRatio);
    final ys = _slices(stretchY, height, targetHeight, pixelRatio);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final (sy0, sy1, dy0, dy1) in ys) {
      for (final (sx0, sx1, dx0, dx1) in xs) {
        if (dx1 <= dx0 || dy1 <= dy0) continue;
        canvas.drawImageRect(
          bubble,
          Rect.fromLTRB(sx0 * scale, sy0 * scale, sx1 * scale, sy1 * scale),
          Rect.fromLTRB(dx0, dy0, dx1, dy1),
          paint,
        );
      }
    }
  }

  /// 한 축을 고정·늘림 조각으로 나눠 (원본 시작, 원본 끝, 대상 시작, 대상 끝)을 돌려준다.
  /// 원본은 논리 픽셀, 대상은 정수 물리 픽셀이다. 늘어난 길이는 늘림 구간 길이에 비례해
  /// 나눈다.
  static List<(double, double, double, double)> _slices(
    List<(double, double)> stretches,
    double sourceLength,
    int targetLength,
    double pixelRatio,
  ) {
    final stretchTotal = stretches.fold(0.0, (sum, s) => sum + s.$2 - s.$1);
    final fixedTotal = sourceLength - stretchTotal;
    final extra = targetLength - fixedTotal * pixelRatio;

    final slices = <(double, double, double, double)>[];
    var source = 0.0;
    var target = 0.0;
    void add(double sourceEnd, double length) {
      final targetEnd = (target + length).roundToDouble();
      slices.add((source, sourceEnd, target, targetEnd));
      source = sourceEnd;
      target = targetEnd;
    }

    for (final (start, end) in stretches) {
      add(start, (start - source) * pixelRatio);
      add(end, extra * (end - start) / stretchTotal);
    }
    // 마지막 조각은 끝까지 채워 반올림 오차를 없앤다.
    add(sourceLength, targetLength - target);
    return slices;
  }
}
