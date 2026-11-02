import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/summary_client.dart';
import '../l10n/strings.dart';
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

  /// 요약 평가. 값은 '[SummaryVote.name]:평가 ID'. 들어온 순서를 지킨다.
  Map<String, String> _summaryVotes = {};
  String? _languageCode;
  bool _darkTheme = false;
  bool _isLoaded = false;
  SettingsBackend _backend = SettingsBackend.keychain;

  /// 실제로 API 호출에 쓸 키. 빌드에 심어 둔 키만 쓰며, 사용자가 바꿀 수 없다.
  /// 예전 버전에서 키체인에 저장해 둔 사용자 키가 있어도 무시한다.
  String? get apiKey =>
      AppConfig.hasBundledHikerKey ? AppConfig.hikerApiKey : null;

  QualityPreference get quality => _quality;
  bool get saveToGallery => _saveToGallery;

  /// 사용자가 직접 고른 언어 코드('ko' 또는 'en'). 기기 설정을 따르면 null.
  String? get languageCode => _languageCode;
  Locale? get locale => _languageCode == null ? null : Locale(_languageCode!);

  /// 어두운 테마를 쓸지. 기기 설정이나 시간과 상관없이 사용자가 고른 대로 둔다.
  bool get darkTheme => _darkTheme;
  ThemeMode get themeMode => _darkTheme ? ThemeMode.dark : ThemeMode.light;

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
    _summaryVotes = _decodeVotes(await _store.readSummaryVotes());
    _languageCode = await _store.readLanguage();
    _darkTheme = await _store.readDarkTheme();
    S.overrideLanguageCode = _languageCode;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setLanguage(String? code) async {
    final normalized = (code == 'ko' || code == 'en') ? code : null;
    if (_languageCode == normalized) return;
    _languageCode = normalized;
    S.overrideLanguageCode = normalized;
    notifyListeners();
    await _store.writeLanguage(normalized);
  }

  Future<void> setDarkTheme(bool value) async {
    if (_darkTheme == value) return;
    _darkTheme = value;
    notifyListeners();
    await _store.writeDarkTheme(value);
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

  /// 키체인에 넣는 값이라 오래된 평가부터 지워 크기를 묶어 둔다.
  static const _maxSummaryVotes = 300;

  static Map<String, String> _decodeVotes(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value.toString(),
        };
      }
    } on FormatException {
      // 깨진 값이면 빈 상태로 시작한다.
    }
    return {};
  }

  ({SummaryVote vote, String voteId})? summaryVote(String key) {
    final parts = _summaryVotes[key]?.split(':');
    if (parts == null || parts.length != 2) return null;
    final vote = SummaryVote.values.asNameMap()[parts[0]];
    return vote == null ? null : (vote: vote, voteId: parts[1]);
  }

  /// [vote] 가 null 이면 평가를 지운다.
  Future<void> setSummaryVote(
    String key, {
    required SummaryVote? vote,
    required String voteId,
  }) async {
    _summaryVotes.remove(key);
    if (vote != null) _summaryVotes[key] = '${vote.name}:$voteId';
    while (_summaryVotes.length > _maxSummaryVotes) {
      _summaryVotes.remove(_summaryVotes.keys.first);
    }
    notifyListeners();
    await _store.writeSummaryVotes(jsonEncode(_summaryVotes));
  }
}
