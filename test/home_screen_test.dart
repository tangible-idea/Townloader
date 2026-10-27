import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:townloader/data/hiker_client.dart';
import 'package:townloader/data/ig_repository.dart';
import 'package:townloader/data/threads_client.dart';
import 'package:townloader/services/download_service.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/resolve_controller.dart';
import 'package:townloader/state/settings_controller.dart';
import 'package:townloader/ui/home_screen.dart';

class _NoKeyStore extends SettingsStore {
  @override
  Future<SettingsBackend> get backend async => SettingsBackend.keychain;

  @override
  Future<String?> readApiKey() async => null;

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

class _KeyedStore extends _NoKeyStore {
  @override
  Future<String?> readApiKey() async => 'test-key';
}

void main() {
  testWidgets('API 키가 없어도 Threads 게시물을 정상적으로 가져와 화면에 표시한다', (tester) async {
    final store = _NoKeyStore();
    final settings = SettingsController(store);
    await settings.load();

    final threadsHttpClient = MockClient((request) async {
      return http.Response('''
        <div class="OuterContainer">
          <a class="HeaderLink"><span>testuser</span></a>
          <div class="SoloMediaContainer">
            <img src="https://cdn.example/photo.jpg" width="1080" height="1080">
          </div>
        </div>
      ''', 200);
    });

    // 데이터 계층 제목(S.current)은 기기 언어를 따르므로 앱 언어와 맞춘다.
    tester.platformDispatcher.localeTestValue = const Locale('ko');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    final hikerClient = HikerClient(readApiKey: () => settings.apiKey);
    final threadsClient = ThreadsClient(httpClient: threadsHttpClient);
    final repository = IgRepository(hikerClient, threadsClient: threadsClient);
    final resolveController = ResolveController(repository);
    final downloadService = DownloadService(settings: store);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: downloadService),
          ChangeNotifierProvider.value(value: resolveController),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(
            onOpenProfile: (_) {},
            onOpenDownloads: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 초기 상태에서 링크 붙여넣기 안내가 표시된다.
    expect(find.text('링크를 입력하세요'), findsOneWidget);

    // Threads 주소를 입력하고 가져오기를 누른다.
    await tester.enterText(
      find.byType(TextField),
      'https://www.threads.com/@testuser/post/C1234567890',
    );
    await tester.tap(find.byTooltip('가져오기'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Threads 게시물 결과가 화면에 나타난다.
    expect(find.text('@testuser · Threads · 사진'), findsOneWidget);
  });

  testWidgets('심어 둔 키가 없는 빌드에서 인스타그램 링크를 조회하면 이유를 안내한다', (tester) async {
    final store = _NoKeyStore();
    final settings = SettingsController(store);
    await settings.load();

    final hikerClient = HikerClient(readApiKey: () => settings.apiKey);
    final repository = IgRepository(hikerClient);
    final resolveController = ResolveController(repository);
    final downloadService = DownloadService(settings: store);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: downloadService),
          ChangeNotifierProvider.value(value: resolveController),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(
            onOpenProfile: (_) {},
            onOpenDownloads: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 인스타그램 주소 입력 후 가져오기
    await tester.enterText(
      find.byType(TextField),
      'https://www.instagram.com/reel/C1234567890/',
    );
    await tester.tap(find.byTooltip('가져오기'));
    await tester.pump();
    await tester.pumpAndSettle();

    // 키는 사용자가 바꿀 수 없으므로 설정으로 보내지 않고 이유만 알린다.
    expect(find.text('가져오지 못했습니다'), findsOneWidget);
    expect(find.textContaining('인스타그램 조회용 키가 들어 있지 않습니다'), findsOneWidget);
    expect(find.text('설정 열기'), findsNothing);
  });

  testWidgets('전체 받기를 누르면 키보드를 내리고 다운로드 목록 탭으로 넘어간다', (tester) async {
    final store = _KeyedStore();
    final settings = SettingsController(store);
    await settings.load();

    // 스토리 두 건을 돌려주면 결과가 여러 개라 '전체 받기' 버튼이 나타난다.
    final hikerHttpClient = MockClient((request) async {
      expect(request.url.path, '/v1/user/stories/by/username');
      return http.Response(
        '[{"pk":"111","media_type":1,"product_type":"story",'
        '"user":{"pk":"222","username":"nasa"},'
        '"thumbnail_url":"https://cdn.example/s1.jpg"},'
        '{"pk":"333","media_type":1,"product_type":"story",'
        '"user":{"pk":"222","username":"nasa"},'
        '"thumbnail_url":"https://cdn.example/s2.jpg"}]',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    // 테스트는 키를 심지 않고 돌므로 클라이언트에 키를 직접 준다.
    final hikerClient = HikerClient(
      readApiKey: () => 'test-key',
      httpClient: hikerHttpClient,
    );
    final repository = IgRepository(hikerClient);
    final resolveController = ResolveController(repository);
    final downloadService = DownloadService(settings: store);

    var downloadsOpened = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: downloadService),
          ChangeNotifierProvider.value(value: resolveController),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: const [Locale('ko'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(
            onOpenProfile: (_) {},
            onOpenDownloads: () => downloadsOpened++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://www.instagram.com/stories/nasa/',
    );
    await tester.tap(find.byTooltip('가져오기'));
    await tester.pumpAndSettle();

    expect(find.text('전체 받기'), findsOneWidget);

    // 결과가 뜬 뒤 다시 입력창을 만져 키보드가 올라온 상태를 만든다.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue, reason: '탭 후 입력창에 포커스가 있어야 한다');

    await tester.tap(find.text('전체 받기'));
    await tester.pumpAndSettle();

    expect(field.focusNode?.hasFocus, isFalse, reason: '키보드를 내려야 한다');
    expect(downloadsOpened, 1, reason: '목록 탭으로 한 번 넘어가야 한다');
    expect(downloadService.items, isNotEmpty);
  });

  testWidgets('영어 로케일에서는 미니멀한 영문 텍스트가 표시된다', (tester) async {
    final store = _KeyedStore();
    final settings = SettingsController(store);
    await settings.load();

    final repository = IgRepository(HikerClient(readApiKey: () => 'test'));
    final resolveController = ResolveController(repository);
    final downloadService = DownloadService(settings: store);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: downloadService),
          ChangeNotifierProvider.value(value: resolveController),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          home: HomeScreen(
            onOpenProfile: (_) {},
            onOpenDownloads: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Paste a link'), findsOneWidget);
    expect(find.text('Instagram & Threads'), findsOneWidget);
  });
}
