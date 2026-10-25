import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/config/app_config.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/settings_controller.dart';

class _Store extends SettingsStore {
  _Store(this._key);
  final String? _key;

  @override
  Future<SettingsBackend> get backend async => SettingsBackend.keychain;
  @override
  Future<String?> readApiKey() async => _key;
  @override
  Future<bool> writeApiKey(String? value) async => true;
  @override
  Future<QualityPreference> readQuality() async => QualityPreference.best;
  @override
  Future<bool> writeQuality(QualityPreference value) async => true;
  @override
  Future<bool> readSaveToGallery() async => true;
  @override
  Future<bool> writeSaveToGallery(bool value) async => true;

  @override
  Future<bool> readPersonalUseAck() async => true;

  @override
  Future<bool> writePersonalUseAck() async => true;

  @override
  Future<bool> readAiSummaryConsent() async => false;

  @override
  Future<bool> writeAiSummaryConsent() async => true;
}

void main() {
  test('사용자가 예전에 저장한 키가 있어도 심어 둔 키만 쓴다', () async {
    final controller = SettingsController(_Store('user-key'));
    await controller.load();

    // 심어 둔 키가 있고 없고에 따라 기대값이 갈린다. 두 빌드 모두에서 돌아야 한다.
    if (AppConfig.hasBundledHikerKey) {
      expect(controller.apiKey, AppConfig.hikerApiKey);
      expect(controller.hasApiKey, isTrue);
    } else {
      expect(controller.apiKey, isNull);
      expect(controller.hasApiKey, isFalse);
    }
  });
}
