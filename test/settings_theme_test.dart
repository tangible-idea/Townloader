import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/settings_controller.dart';

class _ThemeStore extends SettingsStore {
  _ThemeStore();

  bool dark = false;

  @override
  Future<SettingsBackend> get backend async => SettingsBackend.keychain;

  @override
  Future<QualityPreference> readQuality() async => QualityPreference.best;

  @override
  Future<bool> readSaveToGallery() async => true;

  @override
  Future<bool> readPersonalUseAck() async => true;

  @override
  Future<bool> readAiSummaryConsent() async => false;

  @override
  Future<String?> readSummaryVotes() async => null;

  @override
  Future<String?> readLanguage() async => null;

  @override
  Future<bool> readDarkTheme() async => dark;

  @override
  Future<bool> writeDarkTheme(bool value) async {
    dark = value;
    return true;
  }
}

void main() {
  test('기본은 밝은 테마로 고정되고 기기 설정을 따르지 않는다', () async {
    final settings = SettingsController(_ThemeStore());
    await settings.load();
    expect(settings.themeMode, ThemeMode.light);
  });

  test('고른 테마를 저장하고 다음 실행에도 유지한다', () async {
    final store = _ThemeStore();
    final settings = SettingsController(store);
    await settings.load();

    await settings.setDarkTheme(true);
    expect(settings.themeMode, ThemeMode.dark);
    expect(store.dark, isTrue);

    final reopened = SettingsController(store);
    await reopened.load();
    expect(reopened.themeMode, ThemeMode.dark);
  });
}
