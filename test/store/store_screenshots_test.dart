import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:townloader/models/saved_link.dart';
import 'package:townloader/services/links_store.dart';
import 'package:townloader/state/links_controller.dart';
import 'package:townloader/data/hiker_client.dart';
import 'package:townloader/data/maps_client.dart';
import 'package:townloader/data/ig_repository.dart';
import 'package:townloader/data/ig_url.dart';
import 'package:townloader/l10n/strings.dart';
import 'package:townloader/models/ig_asset.dart';
import 'package:townloader/models/ig_post.dart';
import 'package:townloader/models/ig_user.dart';
import 'package:townloader/models/media_source.dart';
import 'package:townloader/models/threads_thread.dart';
import 'package:townloader/services/download_service.dart';
import 'package:townloader/services/image_disk_cache.dart';
import 'package:townloader/services/social_sign_in.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/account_controller.dart';
import 'package:townloader/state/profile_controller.dart';
import 'package:townloader/state/resolve_controller.dart';
import 'package:townloader/state/settings_controller.dart';
import 'package:townloader/ui/profile_screen.dart';
import 'package:townloader/ui/root_shell.dart';
import 'package:townloader/ui/theme.dart';

/// App Store 업로드용 스크린샷(6.9" iPhone, 1320×2868)을 만든다.
///
/// 실제 앱 화면을 폰 목업에 넣고 위에 문구를 얹는다. 평소 테스트에서는 건너뛴다.
///
///     STORE_SHOTS=1 flutter test test/store/store_screenshots_test.dart
///
/// 결과는 `store/app_store/screenshots/<언어>/` 에 떨어진다. 사진은 picsum.photos(Unsplash 라이선스)에서
/// 받은 것이고, 계정·게시물은 모두 지어낸 예시다.
void main() {
  final enabled = Platform.environment['STORE_SHOTS'] == '1';

  setUpAll(() async {
    if (!enabled) return;
    await _loadFonts();
    await _primeDiskCache();
  });

  for (final copy in _copies) {
    testWidgets('${copy.locale} 01 글 속 장소 찾기', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      await env.pump(
        _StoreFrame(
          title: copy.places.title,
          subtitle: copy.places.subtitle,
          titleSize: copy.titleSize,
          screen: const RootShell(),
        ),
        locale: copy.appLocale,
      );
      await _settle(tester);

      await _capture(tester, copy.locale, '01_places.png');
    }, skip: !enabled);

    testWidgets('${copy.locale} 02 지도', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      await env.pump(
        _StoreFrame(
          title: copy.map.title,
          subtitle: copy.map.subtitle,
          titleSize: copy.titleSize,
          simulatorShot: true,
          // capture_map.sh 로 시뮬레이터에서 찍은 실제 지도 화면.
          screen: Image.network(_img('map_${copy.locale}'), fit: BoxFit.cover),
        ),
        locale: copy.appLocale,
      );
      await _settle(tester);

      await _capture(tester, copy.locale, '02_map.png');
    }, skip: !enabled);

    testWidgets('${copy.locale} 03 스레드를 한 화면에', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      await env.pump(
        _StoreFrame(
          title: copy.thread.title,
          subtitle: copy.thread.subtitle,
          titleSize: copy.titleSize,
          screen: const RootShell(),
        ),
        locale: copy.appLocale,
      );

      await tester.tap(find.text(copy.strings.navDownload));
      await tester.pump();
      final field = find.descendant(
        of: find.byType(RootShell),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        field.first,
        'threads.com/@${_threadsAuthor.username}/post/DdTrek0001',
      );
      await tester.tap(find.byTooltip(copy.strings.fetch));
      await _settle(tester);

      await _capture(tester, copy.locale, '03_thread.png');
    }, skip: !enabled);

    testWidgets('${copy.locale} 04 링크 하나로 저장', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      await env.pump(
        _StoreFrame(
          title: copy.link.title,
          subtitle: copy.link.subtitle,
          titleSize: copy.titleSize,
          screen: const RootShell(),
        ),
        locale: copy.appLocale,
      );

      await tester.tap(find.text(copy.strings.navDownload));
      await tester.pump();
      final field = find.descendant(
        of: find.byType(RootShell),
        matching: find.byType(TextField),
      );
      await tester.enterText(field.first, 'instagram.com/p/DchLnq8E21N');
      await tester.tap(find.byTooltip(copy.strings.fetch));
      await _settle(tester);

      await _capture(tester, copy.locale, '04_link.png');
    }, skip: !enabled);

    testWidgets('${copy.locale} 05 프로필 통째로 둘러보기', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      await env.pump(
        _StoreFrame(
          title: copy.profile.title,
          subtitle: copy.profile.subtitle,
          titleSize: copy.titleSize,
          screen: const RootShell(),
        ),
        locale: copy.appLocale,
      );

      await tester.tap(find.text(copy.strings.navProfile));
      await tester.pump();
      final field = find.descendant(
        of: find.byType(ProfileScreen),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, _user.username);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(tester);

      await _capture(tester, copy.locale, '05_profile.png');
    }, skip: !enabled);

    testWidgets('${copy.locale} 제품 페이지 헤더', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      tester.view.physicalSize = _headerCanvas * _headerPixelRatio;
      tester.view.devicePixelRatio = _headerPixelRatio;
      await env.pump(_HeaderFrame(copy: copy.header), locale: copy.appLocale);
      await _settle(tester);

      await _capture(
        tester,
        copy.locale,
        'header.png',
        pixelRatio: _headerPixelRatio,
        folder: 'store/app_store/header',
      );
    }, skip: !enabled);

    testWidgets('${copy.locale} 검색 결과 이미지', (tester) async {
      final env = await _Env.create(tester, copy.appLocale);
      tester.view.physicalSize = _searchCanvas * _headerPixelRatio;
      tester.view.devicePixelRatio = _headerPixelRatio;
      await env.pump(
        _HeaderFrame(
          copy: copy.header,
          textWidth: 900,
          gap: 60,
          cardWidth: 760,
          titleSize: 108,
        ),
        locale: copy.appLocale,
      );
      await _settle(tester);

      await _capture(
        tester,
        copy.locale,
        'search_results.png',
        pixelRatio: _headerPixelRatio,
        folder: 'store/app_store/header',
      );
    }, skip: !enabled);
  }
}

// ── 문구 ────────────────────────────────────────────────────────────────────

/// 언어마다 앱 화면도 그 언어로 띄우고, 위에 얹는 문구도 바꾼다.
class _Copy {
  const _Copy({
    required this.locale,
    required this.titleSize,
    required this.places,
    required this.map,
    required this.thread,
    required this.link,
    required this.profile,
    required this.header,
  });

  /// App Store Connect(fastlane) 의 언어 폴더 이름.
  final String locale;

  /// 앱 화면을 이 언어로 띄운다.
  Locale get appLocale => Locale(locale.split('-').first);
  S get strings => S(appLocale.languageCode != 'en');
  final double titleSize;
  final ({String title, String subtitle}) places;
  final ({String title, String subtitle}) map;
  final ({String title, String subtitle}) thread;
  final ({String title, String subtitle}) link;
  final ({String title, String subtitle}) profile;
  final ({String title, String subtitle}) header;
}

const _copies = [
  _Copy(
    locale: 'ko',
    titleSize: 38,
    places: (title: '링크를 붙여넣으면\n장소를 찾아 줘요', subtitle: '캡션과 사진 속 글자까지 읽어 모아요'),
    map: (title: '저장한 장소를\n지도 한 장에', subtitle: '카테고리별로 보고, 링크로 공유해요'),
    thread: (title: '나뉜 스레드도\n한 화면에서 끝까지', subtitle: '이어지는 글과 댓글을 순서대로 모아 읽어요'),
    link: (title: '원본 화질로\n원하는 것만 보관', subtitle: '사진과 영상을 크게 보고, 원하는 것만 보관해요'),
    profile: (
      title: '계정을 통째로 보고\n원하는 것만 골라서',
      subtitle: '게시물·릴스·스토리를 한눈에 둘러봐요',
    ),
    header: (title: '글 속 장소를\n지도에 모아요', subtitle: '긴 글 읽기부터 사진·영상 보관까지 한 앱에서'),
  ),
  _Copy(
    locale: 'en-US',
    titleSize: 34,
    places: (
      title: 'Paste a link.\nGet the places.',
      subtitle: 'Reads captions and the text in photos',
    ),
    map: (
      title: 'All your spots.\nOne map.',
      subtitle: 'View by category and share with a link',
    ),
    thread: (
      title: 'Whole threads.\nOne screen.',
      subtitle: 'Read multi-part posts in order, with replies',
    ),
    link: (
      title: 'Original quality.\nKeep what you want.',
      subtitle: 'View photos and videos, keep only what you want',
    ),
    profile: (
      title: 'Browse an account.\nKeep what you like.',
      subtitle: 'See posts, reels and stories at a glance',
    ),
    header: (
      title: 'Save a post.\nMap its places.',
      subtitle: 'Read long threads. Keep photos and videos.',
    ),
  ),
];

/// 링크 탭에 미리 저장해 둔 예시 글. 글 내용은 지어낸 것이다.
LinksData _savedLinks(Locale locale) {
  final isKo = locale.languageCode == 'ko';
  final category = isKo ? '제주 여행' : 'Jeju trip';
  SavedPlace place(String ko, String en, double lat, double lng) => SavedPlace(
    name: isKo ? ko : en,
    lat: lat,
    lng: lng,
    source: PlaceSource.tag,
  );
  SavedLink link(
    String code,
    String ko,
    String en,
    String cover,
    List<SavedPlace> places,
  ) => SavedLink(
    code: code,
    url: 'https://www.instagram.com/p/$code/',
    category: category,
    savedAt: DateTime(2026, 10, 1),
    status: LinkStatus.ready,
    title: isKo ? ko : en,
    author: _user.username,
    coverUrl: _img(cover),
    imageUrls: [_img(cover)],
    places: places,
  );
  return LinksData(
    categories: [category, isKo ? '맛집' : 'Food'],
    links: [
      link('Jeju1', '제주 동쪽 하루 코스', 'A day in east Jeju', 'p1018', [
        place('성산일출봉', 'Seongsan Ilchulbong', 33.4580, 126.9425),
        place('우도', 'Udo Island', 33.5060, 126.9530),
      ]),
      link('Jeju2', '제주 서쪽 바다 산책', 'West coast walks', 'p1043', [
        place('협재해수욕장', 'Hyeopjae Beach', 33.3940, 126.2396),
      ]),
      link('Jeju3', '한라산과 폭포', 'Hallasan and waterfalls', 'p1039', [
        place('한라산', 'Hallasan', 33.3617, 126.5292),
        place('천지연폭포', 'Cheonjiyeon Falls', 33.2450, 126.5540),
      ]),
    ],
  );
}

// ── 캔버스 ────────────────────────────────────────────────────────────────────

/// App Store Connect 가 받는 6.9" 규격(1320×2868). 논리 크기 440×956 을 3배로 찍는다.
const _canvas = Size(440, 956);
const _pixelRatio = 3.0;

/// 목업 안 화면은 iPhone 16 Pro 논리 크기.
const _screen = Size(402, 874);

final _shotKey = GlobalKey();

const _korean = 'Pretendard';

class _Env {
  _Env._(this.tester, this.downloads, this.repository);

  final WidgetTester tester;
  final DownloadService downloads;
  final _StoreRepository repository;

  static Future<_Env> create(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = _canvas * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 데이터 계층 문구(S.current)는 기기 언어를 따르므로 함께 맞춘다.
    tester.platformDispatcher.localeTestValue = locale;
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    // 앞 테스트에서 불러오다 멈춘 사진이 캐시에 남으면 다음 장면에서도 끝나지 않는다.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await _primeImages(tester);
    // 위젯 테스트에는 딥링크 플러그인이 없다.
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    final store = _MemoryStore();
    return _Env._(
      tester,
      DownloadService(settings: store, httpClient: _HangingClient()),
      _StoreRepository(),
    );
  }

  Future<void> pump(Widget frame, {required Locale locale}) async {
    final settings = _StoreSettings(_MemoryStore());
    await settings.load();
    final links = LinksController(
      store: MemoryLinksStore(_savedLinks(locale)),
      resolve: repository.resolve,
      analyze: (post, {required isKo}) async => const [],
    );
    await links.load(isKo: locale.languageCode == 'ko');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider.value(value: downloads),
          ChangeNotifierProvider(create: (_) => ResolveController(repository)),
          ChangeNotifierProvider(create: (_) => ProfileController(repository)),
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
          theme: AppTheme.light(fontFallback: const [_korean]),
          locale: locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ko'), Locale('en')],
          // Material 이 없으면 프레임 문구에 디버그용 노란 밑줄이 그어진다.
          home: RepaintBoundary(
            key: _shotKey,
            child: Material(type: MaterialType.transparency, child: frame),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

/// 탭 잉크와 전환 애니메이션이 끝날 때까지 시간을 흘린다.
/// 진행 중 다운로드의 스피너 때문에 pumpAndSettle 은 끝나지 않아 직접 넘긴다.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    // 사진 파일을 읽고 디코딩하는 일은 실제 시간이 흘러야 끝난다.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  }
}

Future<void> _capture(
  WidgetTester tester,
  String locale,
  String name, {
  double pixelRatio = _pixelRatio,
  String folder = 'store/app_store/screenshots',
}) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_shotKey),
    );
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$folder/$locale/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

// ── 프레임 ────────────────────────────────────────────────────────────────────

class _StoreFrame extends StatelessWidget {
  const _StoreFrame({
    required this.title,
    required this.subtitle,
    required this.screen,
    this.titleSize = 38,
    this.simulatorShot = false,
  });

  final String title;
  final double titleSize;
  final String subtitle;
  final Widget screen;

  /// 시뮬레이터에서 찍은 화면이라 상태 표시줄이 이미 들어 있다.
  final bool simulatorShot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.white, Color(0xFFE9E9E9)],
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 76),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _korean,
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              height: 1.24,
              letterSpacing: -1,
              color: Palette.grey900,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: _korean,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.4,
              letterSpacing: -0.2,
              color: Palette.grey600,
            ),
          ),
          const SizedBox(height: 36),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: FittedBox(
                    child: _PhoneMockup(
                      screen: screen,
                      showStatusBar: !simulatorShot,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup({required this.screen, this.showStatusBar = true});

  final Widget screen;
  final bool showStatusBar;

  static const _bezel = 13.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).copyWith(
      size: _screen,
      padding: const EdgeInsets.only(top: 62, bottom: 34),
      viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
      viewInsets: EdgeInsets.zero,
      textScaler: TextScaler.noScaling,
    );

    return Container(
      width: _screen.width + _bezel * 2,
      height: _screen.height + _bezel * 2,
      padding: const EdgeInsets.all(_bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(68),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(55),
        child: SizedBox.fromSize(
          size: _screen,
          child: Stack(
            children: [
              Positioned.fill(child: MediaQuery(data: media, child: screen)),
              if (showStatusBar)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 54,
                  child: _StatusBar(),
                ),
              Positioned(
                top: 11,
                left: (_screen.width - 124) / 2,
                child: Container(
                  width: 124,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(40, 18, 30, 0),
      child: Row(
        children: [
          Text(
            '9:41',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Palette.grey900,
            ),
          ),
          Spacer(),
          Icon(Icons.signal_cellular_alt, size: 18, color: Palette.grey900),
          SizedBox(width: 5),
          Icon(Icons.wifi, size: 18, color: Palette.grey900),
          SizedBox(width: 5),
          Icon(Icons.battery_full, size: 20, color: Palette.grey900),
        ],
      ),
    );
  }
}

// ── 이미지·폰트 ───────────────────────────────────────────────────────────────

const _imageDir = 'test/store/images';

/// 가짜 URL. 테스트의 HTTP 는 막혀 있으므로 이미지 캐시에 미리 넣어 둔다.
String _img(String name) => 'https://img.townloader.test/$name';

Future<void> _primeImages(WidgetTester tester) async {
  final files = <String, String>{
    for (final entity in Directory(_imageDir).listSync())
      if (entity is File && entity.path.endsWith('.jpg'))
        entity.uri.pathSegments.last.replaceAll('.jpg', ''): entity.path,
    for (final locale in ['ko', 'en-US'])
      if (File('store/app_store/screenshots/raw/map_$locale.png').existsSync())
        'map_$locale': 'store/app_store/screenshots/raw/map_$locale.png',
    'icon':
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
  };

  await tester.runAsync(() async {
    for (final MapEntry(key: name, value: path) in files.entries) {
      final codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final info = ImageInfo(image: frame.image);
      PaintingBinding.instance.imageCache.putIfAbsent(
        NetworkImage(_img(name)),
        () => OneFrameImageStreamCompleter(SynchronousFuture(info)),
      );
    }
  });
}

/// 앱의 사진은 [DiskCachedImage] 로 그려지므로, 받아 둔 파일이 있는 것처럼 캐시 폴더를 채운다.
Future<void> _primeDiskCache() async {
  final base = await Directory.systemTemp.createTemp('store_shots');
  PathProviderPlatform.instance = _TempPathProvider(base.path);
  final dir = await Directory('${base.path}/images').create();
  for (final entity in Directory(_imageDir).listSync()) {
    if (entity is! File || !entity.path.endsWith('.jpg')) continue;
    final name = entity.uri.pathSegments.last.replaceAll('.jpg', '');
    await entity.copy('${dir.path}/${_diskCacheName(_img(name))}');
  }
  // 캐시 폴더 열기를 실제 시간에서 끝내 둔다. 테스트의 가짜 시간 안에서 시작했다가
  // 끝나지 못하면 뒤 장면의 사진까지 전부 멈춘다.
  await ImageDiskCache.instance.fileFor(_img('avatar'));
}

/// `ImageDiskCache._hash` 와 같은 FNV-1a 이름.
String _diskCacheName(String url) {
  var hash = 0xcbf29ce484222325;
  for (final unit in url.codeUnits) {
    hash = ((hash ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return '${hash.toRadixString(16)}_${url.length}';
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationCachePath() async => path;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load(AppTheme.fontFamily, [
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fonts/Urbanist-$weight.ttf',
  ]);
  await load(_korean, [
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      'test/store/fonts/Pretendard-$weight.otf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await load('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

// ── 가짜 의존성 ───────────────────────────────────────────────────────────────

/// 응답을 끝내 돌려주지 않아 다운로드가 '진행 중' 에 머문다.
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

class _StoreRepository extends IgRepository {
  _StoreRepository() : super(HikerClient(readApiKey: () => 'store'));

  @override
  Future<ResolveResult> resolve(IgLink link) async {
    if (link.type == IgLinkType.threadsPost) {
      final thread = _thread;
      return ResolveResult(
        title:
            '@${_threadsAuthor.username} · Threads · ${S.current.threadLabel}',
        posts: thread.mainPosts,
        user: _threadsAuthor,
        thread: thread,
      );
    }
    return _instagramResult;
  }

  ResolveResult get _instagramResult => ResolveResult(
    title:
        '@${_user.username} · ${_carousel.kind.localizedLabel(S.current.isKo)}',
    posts: [_carousel],
    user: _user,
  );

  @override
  Future<IgUser> fetchUser(String username) async => _user;

  @override
  Future<MediaPage> fetchUserMedias(String userId, {String? cursor}) async =>
      MediaPage(posts: _gridPosts);

  @override
  Future<MediaPage> fetchUserClips(String userId, {String? cursor}) async =>
      MediaPage(
        posts: _gridPosts.where((post) => post.kind == PostKind.reel).toList(),
      );

  @override
  Future<List<IgPost>> fetchUserStories(String username) async => const [];
}

/// 테스트는 키를 심지 않고 돌기 때문에, 키가 있는 빌드처럼 보이게 한다.
class _StoreSettings extends SettingsController {
  _StoreSettings(super.store);

  @override
  String? get apiKey => 'store';
}

class _MemoryStore extends SettingsStore {
  @override
  Future<String?> readLanguage() async => null;

  @override
  Future<bool> readDarkTheme() async => false;

  @override
  Future<bool> writeDarkTheme(bool value) async => true;

  @override
  Future<String?> readSummaryVotes() async => null;

  @override
  Future<bool> writeSummaryVotes(String value) async => true;

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

// ── 예시 데이터 (모두 지어낸 계정) ────────────────────────────────────────────

final _user = IgUser(
  pk: '4821001',
  username: 'marks.photo',
  fullName: "Mark's Photo",
  profilePicUrl: _img('avatar'),
  isVerified: true,
  mediaCount: 1284,
  followerCount: 482000,
  followingCount: 312,
  biography: '매일 한 장, 세상의 풍경',
);

IgItem _photo(String name) => IgItem(
  id: name,
  kind: AssetKind.photo,
  thumbnailUrl: _img(name),
  variants: [
    IgAsset(kind: AssetKind.photo, url: _img(name), width: 1080, height: 1350),
  ],
);

IgItem _video(String name, double seconds) => IgItem(
  id: name,
  kind: AssetKind.video,
  thumbnailUrl: _img(name),
  durationSeconds: seconds,
  variants: [
    IgAsset(
      kind: AssetKind.video,
      url: 'https://video.townloader.test/$name.mp4',
      width: 1080,
      height: 1920,
      bandwidth: 2100000,
      durationSeconds: seconds,
    ),
  ],
);

IgPost get _carousel => IgPost(
  pk: '3973939000000000001',
  code: 'DchLnq8E21N',
  kind: PostKind.carousel,
  user: _user,
  caption:
      S.current.isKo
          ? '돌로미티 트레킹 3일차. 구름이 걷히는 순간을 다섯 장에 담았어요.'
          : 'Day 3 in the Dolomites. Five frames of the clouds breaking.',
  takenAt: DateTime(2026, 9, 14),
  likeCount: 48200,
  commentCount: 612,
  items: [
    _photo('p1018'),
    _photo('p1036'),
    _photo('p1043'),
    _photo('p1044'),
    _photo('p1039'),
  ],
);

final _gridPosts = <IgPost>[
  for (final (index, name)
      in [
        'p1015', 'p1040', 'p1069', 'p1074', 'p1084', 'p110', //
        'p1062', 'p1057', 'p1050', 'p1047', 'p1039', 'p1080',
      ].indexed)
    IgPost(
      pk: '39750000000000000$index',
      code: 'DcGrid$index',
      kind: index % 3 == 1 ? PostKind.reel : PostKind.photo,
      user: _user,
      takenAt: DateTime(2026, 9, 20 - index),
      items: [index % 3 == 1 ? _video(name, 24.0 + index) : _photo(name)],
    ),
];

// Threads 스레드 예시. 작성자가 여섯 편으로 나눠 쓴 여행 기록과 댓글.

final _threadsAuthor = IgUser(
  pk: '6100231',
  username: 'marks.photo',
  fullName: "Mark's Photo",
  profilePicUrl: _img('avatar'),
  isVerified: true,
);

final _threadsReplier = IgUser(
  pk: '6100877',
  username: 'kim.films',
  fullName: 'Kim Films',
  profilePicUrl: _img('avatar2'),
);

IgPost _threadPost(
  int index,
  IgUser user,
  String caption, {
  List<IgItem> items = const [],
}) => IgPost(
  pk: '39800000000000000$index',
  code: 'DdTrek000$index',
  source: MediaSource.threads,
  kind:
      items.length > 1
          ? PostKind.carousel
          : items.any((item) => item.kind == AssetKind.video)
          ? PostKind.video
          : PostKind.photo,
  user: user,
  caption: caption,
  takenAt: DateTime(2026, 9, 21),
  items: items,
);

ThreadsThread get _thread {
  final ko = S.current.isKo;
  final author = [
    (
      ko
          ? '돌로미티 3일 트레킹 정리 (1/6)\n준비물부터 코스, 숙소까지 순서대로 적어 볼게요.'
          : 'My 3-day Dolomites trek, all in one thread (1/6)\nGear, route and huts, in order.',
      [_photo('p1018'), _photo('p1036')],
    ),
    (
      ko
          ? '(2/6) 첫날은 세체다. 케이블카로 올라가 능선을 따라 걸으면 2시간이면 충분해요.'
          : '(2/6) Day one: Seceda. Take the cable car up and follow the ridge, about two hours.',
      [_photo('p1043')],
    ),
    (
      ko
          ? '(3/6) 산장은 두 달 전에 예약했어요. 7월 주말은 거의 다 찹니다.'
          : '(3/6) I booked the huts two months ahead. July weekends fill up fast.',
      <IgItem>[],
    ),
    (
      ko
          ? '(4/6) 둘째 날 아침, 구름이 걷히는 순간.'
          : '(4/6) Day two, the moment the clouds broke.',
      [_video('p1044', 18)],
    ),
    (
      ko
          ? '(5/6) 트레치메 한 바퀴. 바람이 세니 얇은 패딩은 꼭 챙기세요.'
          : '(5/6) The Tre Cime loop. It gets windy, so bring a light down jacket.',
      [_photo('p1039'), _photo('p1015')],
    ),
    (
      ko
          ? '(6/6) 다음엔 가을에 다시 오고 싶어요. 궁금한 건 댓글로!'
          : '(6/6) I want to come back in autumn. Ask me anything below!',
      <IgItem>[],
    ),
  ];
  final replies = [
    ko
        ? '정리 감사해요! 산장 예약은 어디서 하셨어요?'
        : 'Thanks for this! Where did you book the huts?',
    ko ? '4번 사진 너무 좋네요. 몇 시쯤이었나요?' : 'Love the shot in 4. What time was that?',
  ];

  return ThreadsThread(
    nodes: [
      for (final (index, (caption, items)) in author.indexed)
        ThreadNode(
          post: _threadPost(index, _threadsAuthor, caption, items: items),
          role: index == 0 ? ThreadRole.root : ThreadRole.continuation,
          depth: 0,
        ),
      for (final (index, caption) in replies.indexed)
        ThreadNode(
          post: _threadPost(10 + index, _threadsReplier, caption),
          role: ThreadRole.reply,
          depth: 1,
        ),
    ],
  );
}

// ── 제품 페이지 헤더 ──────────────────────────────────────────────────────────

/// App Store 제품 페이지 맨 위 헤더(5244×2950). 논리 크기 2622×1475 를 2배로 찍는다.
///
/// Apple 가이드상 다른 플랫폼의 이름·로고·화면은 넣을 수 없어서, 앱 화면 대신
/// 지도를 단순화한 카드만 그린다. 기기마다 위아래가 잘리므로 내용은 가운데에 모은다.
const _headerCanvas = Size(2622, 1475);

/// 검색 결과 이미지(3840×2560). 작게 보이므로 글자를 키운다.
const _searchCanvas = Size(1920, 1280);
const _headerPixelRatio = 2.0;

class _HeaderFrame extends StatelessWidget {
  const _HeaderFrame({
    required this.copy,
    this.textWidth = 1060,
    this.gap = 120,
    this.cardWidth = 820,
    this.titleSize = 96,
  });

  final ({String title, String subtitle}) copy;
  final double textWidth;
  final double gap;
  final double cardWidth;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.white, Color(0xFFE6E6E6)],
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: textWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: Image.network(
                          _img('icon'),
                          width: 160,
                          height: 160,
                        ),
                      ),
                      const SizedBox(width: 36),
                      const Text(
                        'Townloader',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 72,
                          fontWeight: FontWeight.w700,
                          color: Palette.grey900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 64),
                  Text(
                    copy.title,
                    style: TextStyle(
                      fontFamily: _korean,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      height: 1.22,
                      letterSpacing: -2.5,
                      color: Palette.grey900,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    copy.subtitle,
                    style: const TextStyle(
                      fontFamily: _korean,
                      fontSize: 42,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                      color: Palette.grey600,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: cardWidth,
              child: const FittedBox(child: _HeaderMapCard()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 지도를 닮은 카드. 실제 지도·글자 대신 도형과 회색 막대만 그려 특정 서비스로 읽히지 않게 한다.
class _HeaderMapCard extends StatelessWidget {
  const _HeaderMapCard();

  static const _size = Size(820, 960);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size.width,
      height: _size.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Palette.white,
        borderRadius: BorderRadius.circular(48),
        // 테스트 렌더러는 그림자를 흐리게 그리지 못해 테두리로 띄운다.
        border: Border.all(color: Palette.grey300, width: 2),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
          const _MapPin(left: 96, top: 150, photo: 'p1018', size: 150),
          const _MapPin(left: 520, top: 90, photo: 'p1043', size: 130),
          const _MapPin(left: 400, top: 320, photo: 'p1039', size: 170),
          const _MapPin(left: 610, top: 400, photo: 'p1044', size: 120),
          Positioned(left: 28, right: 28, bottom: 28, child: _postRow()),
        ],
      ),
    );
  }

  static Widget _postRow() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Palette.white,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: Palette.grey200, width: 2),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            _img('p1039'),
            width: 128,
            height: 128,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(320, 28, Palette.grey800),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Icon(Icons.place, size: 40, color: _pinColor),
                  const SizedBox(width: 10),
                  _bar(210, 22, Palette.grey300),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static Widget _bar(double width, double height, Color color) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

/// 앱 아이콘 그라데이션에서 가져온 핀 색.
const _pinColor = Color(0xFFD9486F);

/// 사진을 담은 말풍선 핀. 꼬리 끝이 그 장소다.
class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.left,
    required this.top,
    required this.photo,
    required this.size,
  });

  final double left;
  final double top;
  final String photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tail = size * 0.2;
    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: size,
        height: size + tail,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _PinTailPainter(tail: tail)),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: size,
                height: size,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: _pinColor,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.network(_img(photo), fit: BoxFit.cover),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  const _PinTailPainter({required this.tail});

  final double tail;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final path =
        Path()
          ..moveTo(x - tail * 0.8, size.height - tail * 1.4)
          ..lineTo(x + tail * 0.8, size.height - tail * 1.4)
          ..lineTo(x, size.height)
          ..close();
    canvas.drawPath(path, Paint()..color = _pinColor);
  }

  @override
  bool shouldRepaint(_PinTailPainter old) => old.tail != tail;
}

/// 물, 공원, 길만 있는 가상의 지도.
class _MapPainter extends CustomPainter {
  const _MapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF3F2EE),
    );

    final water =
        Path()
          ..moveTo(size.width, 500)
          ..cubicTo(690, 560, 660, 700, 540, 760)
          ..cubicTo(440, 810, 380, 900, 360, size.height)
          ..lineTo(size.width, size.height)
          ..close();
    canvas.drawPath(water, Paint()..color = const Color(0xFFD6E6F2));

    final park = RRect.fromRectAndRadius(
      const Rect.fromLTWH(60, 500, 270, 190),
      const Radius.circular(40),
    );
    canvas.drawRRect(park, Paint()..color = const Color(0xFFDDEBD6));

    final road =
        Paint()
          ..color = Palette.white
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    void line(double width, List<Offset> points) {
      road.strokeWidth = width;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, road);
    }

    line(26, const [Offset(-20, 420), Offset(360, 470), Offset(860, 300)]);
    line(26, const [Offset(350, -20), Offset(360, 470), Offset(250, 1000)]);
    line(14, const [Offset(-20, 120), Offset(360, 90), Offset(860, 150)]);
    line(14, const [Offset(600, -20), Offset(640, 370), Offset(560, 600)]);
    line(14, const [Offset(-20, 730), Offset(310, 760)]);
    line(14, const [Offset(180, 90), Offset(170, 440)]);
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => false;
}
