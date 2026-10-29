import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 사진에서 읽은 글자 한 줄. 위치와 크기는 사진 크기에 대한 비율(0~1)이다.
@immutable
class OcrLine {
  const OcrLine({required this.text, required this.top, required this.height});

  factory OcrLine.fromMap(Map<Object?, Object?> map) => OcrLine(
    text: (map['text'] as String? ?? '').trim(),
    top: (map['top'] as num? ?? 0).toDouble(),
    height: (map['height'] as num? ?? 0).toDouble(),
  );

  final String text;

  /// 줄 윗변의 위치. 0 이 사진 맨 위.
  final double top;

  /// 줄 높이. 글자 크기를 견줄 때 쓴다(제목은 본문보다 크다).
  final double height;

  /// 장소 찾기(`/places`) 요청에 그대로 싣는 형태.
  Map<String, Object> toJson() => {
    'text': text,
    'top': double.parse(top.toStringAsFixed(3)),
    'height': double.parse(height.toStringAsFixed(3)),
  };
}

/// 기기 안에서 사진의 글자를 읽는다. iOS 는 Apple Vision, Android 는 ML Kit(한국어).
///
/// 사진을 서버로 보내지 않고, 읽은 글자 줄만 장소 찾기에 쓴다.
class TextRecognizer {
  const TextRecognizer();

  static const _channel = MethodChannel('townloader/ocr');

  /// [image] (JPEG·PNG) 의 글자를 위에서 아래 순서로 돌려준다.
  /// 글자를 못 읽었거나 이 기기에서 쓸 수 없으면 빈 목록이다.
  Future<List<OcrLine>> recognize(Uint8List image) async {
    try {
      final lines = await _channel.invokeListMethod<Object?>(
        'recognize',
        image,
      );
      return [
          for (final line in lines ?? const [])
            if (line is Map) OcrLine.fromMap(line),
        ].where((line) => line.text.isNotEmpty).toList()
        ..sort((a, b) => a.top.compareTo(b.top));
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      // 데스크톱·테스트처럼 채널이 없는 곳.
      return const [];
    }
  }
}
