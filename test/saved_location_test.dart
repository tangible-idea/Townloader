import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/services/file_saver.dart';

void main() {
  group('SavedLocation.sharePath', () {
    test('디스크에 저장한 파일은 그 파일을 그대로 공유한다', () {
      const location = SavedLocation(description: 'x', filePath: '/a/b.jpg');
      expect(location.sharePath, '/a/b.jpg');
      expect(location.sharesCachedCopy, isFalse);
    });

    test('사진 앱에 넣은 경우에는 캐시에 남긴 사본을 공유한다', () {
      const location = SavedLocation(
        description: 'x',
        sharePath: '/tmp/townloader_share/b.jpg',
      );
      expect(location.filePath, isNull);
      expect(location.sharesCachedCopy, isTrue);
    });

    test('사본을 남기지 못했으면 공유할 파일이 없다', () {
      const location = SavedLocation(description: 'x');
      expect(location.sharePath, isNull);
      expect(location.sharesCachedCopy, isFalse);
    });
  });
}
