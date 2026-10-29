import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/services/text_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('townloader/ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('기기가 읽은 줄을 위에서 아래 순서로, 빈 줄은 빼고 돌려준다', () async {
    Object? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call.arguments;
      return [
        {'text': '덕수궁 | 서울 중구 정동', 'top': 0.47, 'height': 0.021},
        {'text': '  ', 'top': 0.2, 'height': 0.01},
        {'text': '서울 가을 산책 명소', 'top': 0.08, 'height': 0.034},
      ];
    });

    final lines = await const TextRecognizer().recognize(
      Uint8List.fromList([1, 2, 3]),
    );

    expect(sent, [1, 2, 3]);
    expect(lines.map((l) => l.text), ['서울 가을 산책 명소', '덕수궁 | 서울 중구 정동']);
    expect(lines.last.toJson(), {
      'text': '덕수궁 | 서울 중구 정동',
      'top': 0.47,
      'height': 0.021,
    });
  });

  test('읽지 못하면(모델을 받는 중 등) 빈 목록이다', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ocr_failed');
    });
    expect(await const TextRecognizer().recognize(Uint8List(0)), isEmpty);
  });
}
