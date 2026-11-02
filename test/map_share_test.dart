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

  test('공유 글은 제목, 장소, 링크 순서이고 많으면 줄인다', () {
    expect(
      shareMessage(
        title: '단풍 명소',
        places: ['가', '나', '다', '라', '마', '바', '사', '가'],
        url: 'https://maps.test/m/a',
        isKo: true,
      ),
      '단풍 명소\n📍 가, 나, 다, 라, 마 외 2곳\nhttps://maps.test/m/a',
    );
    expect(
      shareMessage(
        title: 'Cafes',
        places: const [],
        url: 'https://maps.test/m/a',
        isKo: false,
      ),
      'Cafes\nhttps://maps.test/m/a',
    );
  });
}
