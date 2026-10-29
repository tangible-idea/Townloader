import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:townloader/data/maps_client.dart';
import 'package:townloader/services/links_store.dart';
import 'package:townloader/services/social_sign_in.dart';
import 'package:townloader/state/account_controller.dart';
import 'package:townloader/state/links_controller.dart';
import 'package:townloader/data/hiker_client.dart';
import 'package:townloader/data/ig_repository.dart';
import 'package:townloader/models/ig_asset.dart';
import 'package:townloader/models/ig_post.dart';
import 'package:townloader/models/ig_user.dart';
import 'package:townloader/services/download_service.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/profile_controller.dart';
import 'package:townloader/state/resolve_controller.dart';
import 'package:townloader/state/settings_controller.dart';
import 'package:townloader/ui/root_shell.dart';
import 'package:townloader/ui/settings_screen.dart';
import 'package:townloader/ui/theme.dart';
import 'package:townloader/ui/widgets/post_card.dart';

/// 실제 위젯을 PNG 로 렌더링해 `test/goldens/` 에 남긴다.
///
/// 화면 기록 권한 없이도 UI 를 눈으로 확인하기 위한 용도다.
/// 실행: `flutter test test/screenshot_test.dart --update-goldens`
void main() {
  setUpAll(() async {
    // 기본 테스트 폰트는 한글이 네모로 나오므로 시스템 폰트를 직접 올린다.
    await _loadFamily(_fontFamily, _fontPaths);
    // 앱 서체(Urbanist)도 올려 실제 기기처럼 영문은 Urbanist, 한글은 폴백으로 그린다.
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      await _loadFamily(AppTheme.fontFamily, [
        'assets/fonts/Urbanist-$weight.ttf',
      ]);
    }

    // 아이콘도 폰트라서 따로 올리지 않으면 전부 빈 네모로 그려진다.
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        '/Users/markchoi/Documents/flutter';
    await _loadFamily('MaterialIcons', [
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  testWidgets('홈 화면', (tester) async {
    await _setSurface(tester, const Size(1100, 760));
    await tester.pumpWidget(_app(const RootShell()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/01_home.png'),
    );
  });

  testWidgets('설정 화면', (tester) async {
    await _setSurface(tester, const Size(1100, 900));
    await tester.pumpWidget(_app(const SettingsScreen()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/02_settings.png'),
    );
  });

  testWidgets('릴스 결과 카드', (tester) async {
    await _setSurface(tester, const Size(720, 900));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PostCard(post: _reel),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/03_reel_card.png'),
    );
  });

  testWidgets('캐러셀 결과 카드', (tester) async {
    await _setSurface(tester, const Size(720, 760));
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PostCard(post: _carousel),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/04_carousel_card.png'),
    );
  });

  testWidgets('다크 모드 홈', (tester) async {
    await _setSurface(tester, const Size(1100, 760));
    await tester.pumpWidget(_app(const RootShell(), dark: true));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/05_home_dark.png'),
    );
  });
}

const _fontFamily = 'ScreenshotFont';
const _fontPaths = [
  '/System/Library/Fonts/Supplemental/AppleGothic.ttf',
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
];

/// 주어진 파일들을 하나의 폰트 패밀리로 등록한다. 없는 경로는 건너뛴다.
Future<void> _loadFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var added = 0;
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      added++;
    }
  }
  if (added > 0) await loader.load();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  // 데이터 계층 문구(S.current)도 한국어로 나오도록 기기 언어를 맞춘다.
  tester.platformDispatcher.localeTestValue = const Locale('ko');
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 앱과 같은 provider 구성으로 감싸되, 테스트에서 플러그인을 타지 않도록
/// 설정 저장소만 메모리 구현으로 바꾼다.
Widget _app(Widget child, {bool dark = false}) {
  final store = _MemoryStore();
  final settings = SettingsController(store)..load();
  final repository = IgRepository(HikerClient(readApiKey: () => 'demo-key'));
  // 테스트 환경은 글리프 단위 시스템 폴백이 없어 한글 폰트를 폴백으로 직접 건다.
  final base = dark
      ? AppTheme.dark(fontFallback: [_fontFamily])
      : AppTheme.light(fontFallback: [_fontFamily]);
  final links = LinksController(
    store: MemoryLinksStore(),
    resolve: repository.resolve,
    analyze: (post, {required isKo}) async => const [],
  )..load(isKo: true);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: DownloadService(settings: store)),
      ChangeNotifierProvider.value(value: ResolveController(repository)),
      ChangeNotifierProvider.value(value: ProfileController(repository)),
      ChangeNotifierProvider.value(value: links),
      ChangeNotifierProvider.value(
        value: AccountController(
          client: MapsClient(),
          links: links,
          readSession: () async => null,
          writeSession: (_) async => true,
        ),
      ),
      Provider.value(value: SocialSignIn()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

/// 키체인·파일 접근 없이 동작하는 설정 저장소.
class _MemoryStore extends SettingsStore {
  final _values = <String, String>{};

  @override
  Future<SettingsBackend> get backend async => SettingsBackend.keychain;

  @override
  Future<String?> readApiKey() async => _values['key'] ?? 'demo-access-key';

  @override
  Future<bool> writeApiKey(String? value) async {
    _values['key'] = value ?? '';
    return true;
  }

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

// ── 화면에 채워 넣을 예시 데이터 ──────────────────────────────────────────────

const _nasa = IgUser(
  pk: '528817151',
  username: 'nasa',
  fullName: 'NASA',
  isVerified: true,
  mediaCount: 4900,
  followerCount: 104434488,
);

final _reel = IgPost(
  pk: '3970959123456789012',
  code: 'DcMXl1IPNtB',
  kind: PostKind.reel,
  user: _nasa,
  caption:
      '아르테미스 II 발사 준비가 마무리 단계에 들어섰습니다. '
      '50년 만에 다시 달로 향하는 유인 비행입니다.',
  takenAt: DateTime(2026, 8, 20),
  likeCount: 1204000,
  commentCount: 8420,
  playCount: 3400000,
  items: [
    IgItem(
      id: '1',
      kind: AssetKind.video,
      durationSeconds: 50.4,
      variants: const [
        IgAsset(
          kind: AssetKind.video,
          url: 'https://cdn.example/1080.mp4',
          width: 1080,
          height: 1920,
          bandwidth: 2100000,
          durationSeconds: 50.4,
        ),
        IgAsset(
          kind: AssetKind.video,
          url: 'https://cdn.example/720.mp4',
          width: 720,
          height: 1280,
          bandwidth: 931127,
          durationSeconds: 50.4,
        ),
      ],
    ),
  ],
);

final _carousel = IgPost(
  pk: '3973939000000000000',
  code: 'DchLnq8E21N',
  kind: PostKind.carousel,
  user: _nasa,
  caption: '허블이 담은 이번 주의 우주. 다섯 장을 넘겨 보세요.',
  takenAt: DateTime(2026, 8, 28),
  likeCount: 892000,
  commentCount: 3140,
  items: [
    for (var i = 1; i <= 5; i++)
      IgItem(
        id: '$i',
        kind: i == 3 ? AssetKind.video : AssetKind.photo,
        variants: [
          IgAsset(
            kind: i == 3 ? AssetKind.video : AssetKind.photo,
            url: 'https://cdn.example/$i.jpg',
            width: 1440,
            height: 1440,
          ),
        ],
      ),
  ],
);
