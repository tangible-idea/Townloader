import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/settings_controller.dart';
import 'package:townloader/ui/widgets/personal_use_notice.dart';

/// 동의 여부만 메모리에 들고 있는 저장소.
class _AckStore extends SettingsStore {
  bool ack = false;
  int writes = 0;

  @override
  Future<SettingsBackend> get backend async => SettingsBackend.keychain;

  @override
  Future<QualityPreference> readQuality() async => QualityPreference.best;

  @override
  Future<bool> readSaveToGallery() async => true;

  @override
  Future<bool> readPersonalUseAck() async => ack;

  @override
  Future<bool> readAiSummaryConsent() async => false;

  @override
  Future<bool> writePersonalUseAck() async {
    ack = true;
    writes++;
    return true;
  }
}

void main() {
  late _AckStore store;
  late SettingsController settings;
  final results = <bool>[];

  Future<void> pumpButton(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () async =>
                          results.add(await confirmPersonalUse(context)),
                  child: const Text('save'),
                ),
          ),
        ),
      ),
    );
  }

  setUp(() async {
    store = _AckStore();
    settings = SettingsController(store);
    await settings.load();
    results.clear();
  });

  testWidgets('처음 저장하면 안내를 띄우고, 동의하면 기억해서 다시 묻지 않는다', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(store.writes, 1);
    expect(settings.personalUseAcknowledged, isTrue);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, [true, true]);
  });

  testWidgets('취소하면 저장하지 않고 다음에 다시 묻는다', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(store.writes, 0);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
