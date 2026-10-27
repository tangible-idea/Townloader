import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../services/settings_store.dart';

/// 설정 화면과 나머지 앱이 공유하는 상태.
///
/// API 키는 [HikerClient] 가 매 호출마다 동기적으로 읽어간다.
class SettingsController extends ChangeNotifier {
  SettingsController(this._store);

  final SettingsStore _store;

  QualityPreference _quality = QualityPreference.best;
  bool _saveToGallery = true;
  bool _personalUseAck = false;
  bool _aiSummaryConsent = false;
  bool _isLoaded = false;
  SettingsBackend _backend = SettingsBackend.keychain;

  /// 실제로 API 호출에 쓸 키. 빌드에 심어 둔 키만 쓰며, 사용자가 바꿀 수 없다.
  /// 예전 버전에서 키체인에 저장해 둔 사용자 키가 있어도 무시한다.
  String? get apiKey =>
      AppConfig.hasBundledHikerKey ? AppConfig.hikerApiKey : null;

  QualityPreference get quality => _quality;
  bool get saveToGallery => _saveToGallery;

  /// 개인 보관 안내에 동의했는지. 동의 전에는 저장할 때마다 안내를 띄운다.
  bool get personalUseAcknowledged => _personalUseAck;

  /// 스레드 요약을 위해 글을 AI 서비스로 보내는 데 동의했는지.
  bool get aiSummaryConsented => _aiSummaryConsent;

  /// 저장소에서 값을 읽어오기 전에는 "키 없음" 화면을 띄우지 않기 위한 플래그.
  bool get isLoaded => _isLoaded;

  /// 인스타그램을 조회할 수 있는지. 프록시가 있으면 키는 프록시가 들고 있다.
  bool get hasApiKey => AppConfig.hasProxy || (apiKey?.isNotEmpty ?? false);

  /// 설정값이 실제로 어디에 저장되는지. 설정 화면이 그대로 표시한다.
  SettingsBackend get backend => _backend;

  Future<void> load() async {
    _backend = await _store.backend;
    _quality = await _store.readQuality();
    _saveToGallery = await _store.readSaveToGallery();
    _personalUseAck = await _store.readPersonalUseAck();
    _aiSummaryConsent = await _store.readAiSummaryConsent();
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setQuality(QualityPreference value) async {
    if (_quality == value) return;
    _quality = value;
    notifyListeners();
    await _store.writeQuality(value);
  }

  Future<void> setSaveToGallery(bool value) async {
    if (_saveToGallery == value) return;
    _saveToGallery = value;
    notifyListeners();
    await _store.writeSaveToGallery(value);
  }

  Future<void> acknowledgePersonalUse() async {
    if (_personalUseAck) return;
    _personalUseAck = true;
    notifyListeners();
    await _store.writePersonalUseAck();
  }

  Future<void> consentToAiSummary() async {
    if (_aiSummaryConsent) return;
    _aiSummaryConsent = true;
    notifyListeners();
    await _store.writeAiSummaryConsent();
  }
}
