import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/models/saved_link.dart';
import 'package:townloader/services/links_store.dart';
import 'package:townloader/state/links_controller.dart';

void main() {
  const a = SavedPlace(name: 'A', lat: 1, lng: 1, source: PlaceSource.tag);
  const b = SavedPlace(name: 'B', lat: 2, lng: 2, source: PlaceSource.caption);

  late MemoryLinksStore store;
  late LinksController links;

  setUp(() async {
    store = MemoryLinksStore(
      LinksData(
        categories: const ['여행'],
        links: [
          SavedLink(
            code: 'X',
            url: 'https://www.instagram.com/p/X/',
            category: '여행',
            savedAt: DateTime(2026, 10, 1),
            status: LinkStatus.ready,
            places: const [a, b],
          ),
        ],
      ),
    );
    links = LinksController(
      store: store,
      resolve: (_) => throw UnimplementedError(),
      analyze: (post, {required isKo}) async => const [],
    );
    await links.load(isKo: true);
  });

  test('장소 하나를 지우고 저장하며, 지운 자리를 돌려준다', () async {
    final revision = links.revision;

    final at = await links.removePlace('X', b);

    expect(at, 1);
    expect(links.allLinks.single.places.map((p) => p.name), ['A']);
    expect(store.data!.links.single.places.map((p) => p.name), ['A']);
    expect(links.revision, greaterThan(revision));
  });

  test('되돌리면 같은 자리에 다시 넣는다', () async {
    final at = await links.removePlace('X', a);
    await links.insertPlace('X', a, at);

    expect(links.allLinks.single.places.map((p) => p.name), ['A', 'B']);
  });

  test('없는 장소는 지우지 않는다', () async {
    const other = SavedPlace(
      name: 'C',
      lat: 9,
      lng: 9,
      source: PlaceSource.tag,
    );
    expect(await links.removePlace('X', other), -1);
    expect(await links.removePlace('Nope', a), -1);
    expect(links.allLinks.single.places, hasLength(2));
  });

  group('대표 제목', () {
    LinksController titled(
      MemoryLinksStore store,
      Future<String?> Function(SavedLink link, {required bool isKo}) title,
    ) => LinksController(
      store: store,
      resolve: (_) => throw UnimplementedError(),
      analyze: (post, {required isKo}) async => const [],
      title: title,
    );

    test('제목이 없는 글에 제목을 지어 저장한다', () async {
      final asked = <String>[];
      final controller = titled(store, (link, {required isKo}) async {
        asked.add(link.code);
        expect(isKo, isTrue);
        expect(link.places.map((p) => p.name), ['A', 'B']);
        return '도쿄 라멘 투어 2곳';
      });
      await controller.load(isKo: true);

      await controller.fillTitles();

      expect(asked, ['X']);
      expect(controller.allLinks.single.title, '도쿄 라멘 투어 2곳');
      expect(store.data!.links.single.title, '도쿄 라멘 투어 2곳');
    });

    test('못 지은 글은 다시 묻지 않고, 이미 제목이 있으면 건너뛴다', () async {
      var calls = 0;
      final controller = titled(store, (link, {required isKo}) async {
        calls++;
        return null;
      });
      await controller.load(isKo: true);

      await controller.fillTitles();
      await controller.fillTitles();

      expect(calls, 1);
      expect(controller.allLinks.single.title, isNull);
    });
  });
}
