import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:townloader/data/hiker_client.dart';
import 'package:townloader/data/ig_repository.dart';
import 'package:townloader/data/ig_url.dart';
import 'package:townloader/data/maps_client.dart';
import 'package:townloader/data/media_parser.dart';
import 'package:townloader/models/ig_asset.dart';
import 'package:townloader/models/ig_post.dart';
import 'package:townloader/models/ig_user.dart';
import 'package:townloader/models/saved_link.dart';
import 'package:townloader/services/download_service.dart';
import 'package:townloader/services/links_store.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/account_controller.dart';
import 'package:townloader/state/links_controller.dart';
import 'package:townloader/ui/links_screen.dart';
import 'package:townloader/ui/places_map_screen.dart';

IgPost _post(String code) => IgPost(
  pk: 'pk-$code',
  code: code,
  kind: PostKind.carousel,
  user: const IgUser(pk: 'u', username: 'eateat.mag'),
  caption: '가을 산책 명소',
  items: [
    for (var i = 0; i < 2; i++)
      IgItem(
        id: '$code-$i',
        kind: AssetKind.photo,
        thumbnailUrl: 'https://cdn/$code/$i.jpg',
        variants: [
          IgAsset(
            kind: AssetKind.photo,
            url: 'https://cdn/$code/$i.jpg',
            width: 1080,
            height: 1350,
          ),
        ],
      ),
  ],
);

const _place = SavedPlace(
  name: '덕수궁',
  lat: 37.5656,
  lng: 126.9749,
  source: PlaceSource.image,
  address: '서울 중구 정동',
  imageIndex: 1,
);

void main() {
  late MemoryLinksStore store;
  late List<String> resolved;
  late Set<String> failing;

  LinksController controller() => LinksController(
    store: store,
    resolve: (IgLink link) async {
      resolved.add(link.code!);
      if (failing.contains(link.code)) {
        throw HikerException('게시물을 찾을 수 없습니다.');
      }
      return ResolveResult(title: '', posts: [_post(link.code!)]);
    },
    analyze: (post, {required isKo}) async => [_place],
  );

  setUp(() {
    store = MemoryLinksStore();
    resolved = [];
    failing = {};
  });

  test('붙여넣은 글에서 게시물·릴스 링크만 뽑아 지금 카테고리에 저장하고 장소를 찾는다', () async {
    final links = controller();
    await links.load(isKo: true);
    expect(links.categories, ['여행', '맛집']);

    final result = await links.addFromText('''
가을 명소 모음
https://www.instagram.com/p/DdK3PpFmpRJ/?img_index=3&srtk=abc
https://www.instagram.com/reel/DP02RkeE3Yj/  https://www.instagram.com/p/DdK3PpFmpRJ/
https://www.instagram.com/seoul__guide/
''', isKo: true);

    expect(result, (added: 2, duplicates: 1, unsupported: 1));
    await pumpEventQueue();

    expect(resolved, ['DdK3PpFmpRJ', 'DP02RkeE3Yj']);
    final saved = links.links;
    // 나중에 붙여넣은 글이 위로 온다.
    expect(saved.map((l) => l.code), ['DP02RkeE3Yj', 'DdK3PpFmpRJ']);
    expect(saved.every((l) => l.status == LinkStatus.ready), isTrue);
    expect(saved.first.category, '여행');
    expect(saved.first.author, 'eateat.mag');
    // 장소가 적힌 사진(1번)을 장소 사진으로 쓴다.
    expect(
      saved.first.photoFor(saved.first.places.single),
      'https://cdn/DP02RkeE3Yj/1.jpg',
    );

    // 기기에 저장되어 다시 켜도 그대로다.
    final reopened = controller();
    await reopened.load(isKo: true);
    expect(reopened.links.map((l) => l.code), ['DP02RkeE3Yj', 'DdK3PpFmpRJ']);
    expect(reopened.links.first.places.single.name, '덕수궁');
  });

  test('불러오지 못한 글은 실패로 두고, 다시 찾기로 재시도한다', () async {
    failing = {'DdK3PpFmpRJ'};
    final links = controller();
    await links.load(isKo: true);
    await links.addFromText('instagram.com/p/DdK3PpFmpRJ/', isKo: true);
    await pumpEventQueue();

    final link = links.links.single;
    expect(link.status, LinkStatus.failed);
    expect(link.error, '게시물을 찾을 수 없습니다.');

    failing = {};
    await links.retry(link);
    await pumpEventQueue();
    expect(links.links.single.status, LinkStatus.ready);
    expect(links.links.single.places, isNotEmpty);
  });

  test('카테고리를 만들면 그 카테고리로 저장되고, 글을 다른 카테고리로 옮길 수 있다', () async {
    final links = controller();
    await links.load(isKo: true);
    await links.addCategory('  제주 여행 ');
    expect(links.selectedCategory, '제주 여행');

    await links.addFromText(
      'https://www.instagram.com/p/DQ9OPFqCar4/',
      isKo: true,
    );
    await pumpEventQueue();
    expect(links.countIn('제주 여행'), 1);

    await links.moveTo(links.links.single, '맛집');
    expect(links.countIn('제주 여행'), 0);
    links.selectCategory('맛집');
    expect(links.links.single.code, 'DQ9OPFqCar4');

    await links.remove(links.links.single);
    expect(links.allLinks, isEmpty);
  });

  test('위치 태그는 이름과 좌표가 다 있을 때만 읽는다', () {
    final tagged = MediaParser.parsePost({
      'pk': '1',
      'code': 'DQ9OPFqCar4',
      'media_type': 1,
      'image_versions2': {
        'candidates': [
          {'url': 'https://cdn/a.jpg', 'width': 1080, 'height': 1350},
        ],
      },
      'location': {
        'name': '용산공원',
        'lat': 37.521433,
        'lng': 126.989062,
        'address': '용산구 서빙고로 221',
      },
    })!;
    expect(tagged.location?.name, '용산공원');
    expect(tagged.location?.lat, 37.521433);
    expect(tagged.location?.address, '용산구 서빙고로 221');

    final nameOnly = MediaParser.parsePost({
      'pk': '2',
      'media_type': 1,
      'image_versions2': {
        'candidates': [
          {'url': 'https://cdn/a.jpg', 'width': 1080, 'height': 1350},
        ],
      },
      'location': {'name': '어딘가'},
    })!;
    expect(nameOnly.location, isNull);
  });

  testWidgets('분석이 끝난 링크 카드를 누르면 해당 글의 지도로 이동한다', (tester) async {
    final links = controller();
    await links.load(isKo: true);
    await links.addFromText(
      'https://www.instagram.com/p/DdK3PpFmpRJ/',
      isKo: true,
    );
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: links),
          ChangeNotifierProvider(
            create: (_) => DownloadService(settings: _FakeSettingsStore()),
          ),
          ChangeNotifierProvider(
            create: (_) => AccountController(
              client: MapsClient(),
              links: links,
              readSession: () async => null,
              writeSession: (_) async => true,
            ),
          ),
        ],
        child: const MaterialApp(home: LinksScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('@eateat.mag'));
    await tester.pumpAndSettle();

    final mapScreen = tester.widget<PlacesMapScreen>(
      find.byType(PlacesMapScreen),
    );
    expect(mapScreen.initialLink?.code, 'DdK3PpFmpRJ');
  });
}

class _FakeSettingsStore extends SettingsStore {
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
