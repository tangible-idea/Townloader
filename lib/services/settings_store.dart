import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 다운로드할 화질 선택 기준.
enum QualityPreference {
  /// 가장 높은 해상도(용량이 가장 큼).
  best,

  /// 가장 낮은 해상도(빠른 확인용).
  smallest,
}

extension QualityPreferenceLabel on QualityPreference {
  String get label => switch (this) {
    QualityPreference.best => '최고 화질',
    QualityPreference.smallest => '가장 작은 용량',
  };
}

/// 설정값이 실제로 어디에 저장되는지.
enum SettingsBackend {
  /// OS 키체인. iOS·안드로이드와 서명된 macOS 빌드에서 쓰인다.
  keychain,

  /// 앱 샌드박스 컨테이너 안의 파일.
  ///
  /// 서명 인증서 없이 만든 macOS 빌드에서는 키체인 접근이 막히므로 이쪽으로
  /// 물러선다. 컨테이너는 다른 앱이 읽을 수 없지만 키체인만큼 보호되지는 않는다.
  containerFile,
}

/// 앱 설정을 저장한다.
///
/// API 키는 자격 증명이라 우선 키체인에 넣고, 키체인을 쓸 수 없는 환경에서만
/// 앱 컨테이너 파일로 물러선다. 어느 쪽을 쓰는지는 [backend] 로 알 수 있으며
/// 설정 화면이 이를 사용자에게 그대로 알려 준다.
class SettingsStore {
  SettingsStore({FlutterSecureStorage? storage})
    : _secure =
          storage ??
          const FlutterSecureStorage(
            // v11 부터 안드로이드는 기본값이 AES-GCM + RSA-OAEP 라 별도 설정이 필요 없다.
            aOptions: AndroidOptions(),
            // 잠금 해제 후에만 읽히게 해서 백그라운드 접근을 막는다.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _secure;

  static const _keyApiKey = 'hiker_api_key';
  static const _keyQuality = 'quality_preference';
  static const _keySaveToGallery = 'save_to_gallery';
  static const _keyPersonalUseAck = 'personal_use_ack';
  static const _keyAiSummaryConsent = 'ai_summary_consent';
  static const _keyAccountSession = 'account_session';
  static const _keyLanguage = 'app_language';

  /// 키체인이 정말 동작하는지 한 번만 확인하고 결과를 재사용한다.
  static const _canary = '__townloader_probe';

  Future<SettingsBackend>? _backendProbe;
  Map<String, String>? _fileCache;

  Future<SettingsBackend> get backend => _backendProbe ??= _detectBackend();

  /// 쓰기와 읽기가 모두 성공해야 키체인을 쓸 수 있다고 본다.
  /// macOS 는 엔타이틀먼트가 없으면 예외 대신 조용히 null 을 돌려주기도 한다.
  Future<SettingsBackend> _detectBackend() async {
    try {
      await _secure.write(key: _canary, value: '1');
      final echoed = await _secure.read(key: _canary);
      await _secure.delete(key: _canary);
      if (echoed == '1') return SettingsBackend.keychain;
    } catch (_) {
      // 키체인 접근 자체가 막힌 경우로, 아래 파일 백엔드를 쓴다.
    }
    return SettingsBackend.containerFile;
  }

  Future<String?> readApiKey() => _read(_keyApiKey);

  /// 저장에 성공했으면 true.
  Future<bool> writeApiKey(String? value) =>
      _write(_keyApiKey, (value ?? '').trim());

  Future<QualityPreference> readQuality() async {
    final raw = await _read(_keyQuality);
    return QualityPreference.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => QualityPreference.best,
    );
  }

  Future<bool> writeQuality(QualityPreference value) =>
      _write(_keyQuality, value.name);

  /// 모바일에서 받은 파일을 사진 앱에도 넣을지 여부. 기본값은 켜짐.
  Future<bool> readSaveToGallery() async =>
      (await _read(_keySaveToGallery)) != 'false';

  Future<bool> writeSaveToGallery(bool value) =>
      _write(_keySaveToGallery, value.toString());

  /// 처음 저장할 때 띄우는 개인 보관 안내에 동의했는지.
  Future<bool> readPersonalUseAck() async =>
      (await _read(_keyPersonalUseAck)) == 'true';

  Future<bool> writePersonalUseAck() => _write(_keyPersonalUseAck, 'true');

  /// 글과 댓글을 AI 요약 서비스로 보내는 데 동의했는지.
  Future<bool> readAiSummaryConsent() async =>
      (await _read(_keyAiSummaryConsent)) == 'true';

  Future<bool> writeAiSummaryConsent() =>
      _write(_keyAiSummaryConsent, 'true');

  /// 지도 동기화 계정의 세션(JSON). 로그아웃하면 지운다.
  Future<String?> readAccountSession() => _read(_keyAccountSession);

  Future<bool> writeAccountSession(String? value) =>
      _write(_keyAccountSession, value ?? '');

  /// 앱 표시 언어 코드('ko', 'en'). 기기 설정을 따르면 null.
  Future<String?> readLanguage() async {
    final raw = await _read(_keyLanguage);
    return (raw == 'ko' || raw == 'en') ? raw : null;
  }

  Future<bool> writeLanguage(String? code) =>
      _write(_keyLanguage, code ?? '');

  Future<String?> _read(String key) async {
    if (await backend == SettingsBackend.keychain) {
      try {
        final value = await _secure.read(key: key);
        return (value == null || value.isEmpty) ? null : value;
      } catch (_) {
        return null;
      }
    }

    final map = await _readFile();
    final value = map[key];
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<bool> _write(String key, String value) async {
    if (await backend == SettingsBackend.keychain) {
      try {
        if (value.isEmpty) {
          await _secure.delete(key: key);
        } else {
          await _secure.write(key: key, value: value);
        }
        return true;
      } catch (_) {
        return false;
      }
    }

    try {
      final map = await _readFile();
      if (value.isEmpty) {
        map.remove(key);
      } else {
        map[key] = value;
      }
      await (await _settingsFile()).writeAsString(jsonEncode(map), flush: true);
      _fileCache = map;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, String>> _readFile() async {
    final cached = _fileCache;
    if (cached != null) return cached;

    var map = <String, String>{};
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          map = {
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value.toString(),
          };
        }
      }
    } catch (_) {
      // 파일이 깨졌으면 빈 설정으로 시작한다.
    }
    _fileCache = map;
    return map;
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    // 컨테이너에는 이 폴더가 아직 없을 수 있다.
    await dir.create(recursive: true);
    return File('${dir.path}/settings.json');
  }
}
