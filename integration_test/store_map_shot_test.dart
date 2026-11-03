import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:townloader/models/saved_link.dart';
import 'package:townloader/services/links_store.dart';
import 'package:townloader/state/links_controller.dart';
import 'package:townloader/ui/places_map_screen.dart';
import 'package:townloader/ui/theme.dart';

/// App Store 스크린샷에 넣을 실제 지도 화면을 시뮬레이터에 띄운다.
/// Mapbox 는 위젯 테스트에 그려지지 않아 따로 찍는다. 절차는
/// `store/app_store/capture_map.sh` 가 맡는다. 글은 지어낸 예시다.
const _locale = String.fromEnvironment('STORE_LOCALE', defaultValue: 'ko');
const _images = 'http://localhost:8765';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('지도 화면을 띄워 둔다', (tester) async {
    final isKo = _locale == 'ko';
    final category = isKo ? '제주 여행' : 'Jeju trip';
    SavedPlace place(String ko, String en, double lat, double lng, String image) =>
        SavedPlace(
          name: isKo ? ko : en,
          lat: lat,
          lng: lng,
          source: PlaceSource.tag,
          photoUrl: '$_images/$image.jpg',
        );
    SavedLink link(String code, String ko, String en, String cover, List<SavedPlace> places) =>
        SavedLink(
          code: code,
          url: 'https://example.com/$code',
          category: category,
          savedAt: DateTime(2026, 10, 1),
          status: LinkStatus.ready,
          title: isKo ? ko : en,
          coverUrl: '$_images/$cover.jpg',
          imageUrls: ['$_images/$cover.jpg'],
          places: places,
        );
    final links = [
      link('Jeju1', '제주 동쪽 하루 코스', 'A day in east Jeju', 'p1018', [
        place('성산일출봉', 'Seongsan Ilchulbong', 33.4580, 126.9425, 'p1018'),
        place('우도', 'Udo Island', 33.5060, 126.9530, 'p1044'),
      ]),
      link('Jeju2', '제주 서쪽 바다 산책', 'West coast walks', 'p1043', [
        place('협재해수욕장', 'Hyeopjae Beach', 33.3940, 126.2396, 'p1043'),
      ]),
      link('Jeju3', '한라산과 폭포', 'Hallasan and waterfalls', 'p1039', [
        place('한라산', 'Hallasan', 33.3617, 126.5292, 'p1039'),
        place('천지연폭포', 'Cheonjiyeon Falls', 33.2450, 126.5540, 'p1039'),
      ]),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LinksController(
          store: MemoryLinksStore(
            LinksData(categories: [category], links: links),
          ),
          resolve: (_) => throw UnimplementedError(),
          analyze: (post, {required isKo}) async => const [],
        )..load(isKo: isKo),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: Locale(_locale),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ko'), Locale('en')],
          home: PlacesMapScreen(links: links, category: category),
        ),
      ),
    );
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('STORE_MAP_READY');
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
