import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/services/usage_meter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('서버 x-usage 헤더의 호출 수에 서비스별 값을 곱해 토큰을 센다', () {
    final meter = UsageMeter.instance..reset();
    meter.addHeader('{"jev":3,"kakao":8}');
    meter.addHeader('{"claude_haiku":1}');
    meter.add('mapbox_map');
    meter.addHeader('not json');

    UsageService of(String key) =>
        usageServices.firstWhere((service) => service.key == key);
    expect(meter.countOf(of('jev')), 3);
    expect(meter.tokensOf(of('kakao')), 8);
    expect(meter.totalTokens, 3 * 1 + 8 * 1 + 1 * 6 + 1 * 10);

    meter.reset();
    expect(meter.totalTokens, 0);
  });

  test('Jev 1회가 가장 싸다', () {
    final jev = usageServices.firstWhere((service) => service.key == 'jev');
    expect(jev.weight, 1);
    for (final service in usageServices) {
      expect(
        service.weight,
        greaterThanOrEqualTo(jev.weight),
        reason: service.key,
      );
    }
  });
}
