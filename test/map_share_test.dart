import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/data/maps_client.dart';

void main() {
  test('브라우저 주소는 앱 링크에 걸리지 않는 /w/ 경로다', () {
    const share = MapShare(
      id: 'abc123',
      category: 'Travel',
      url: 'https://maps.test/m/abc123',
    );
    expect(share.url, 'https://maps.test/m/abc123');
    expect(share.browserUrl, 'https://maps.test/w/abc123');
  });
}
