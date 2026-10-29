import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:townloader/data/maps_client.dart';
import 'package:townloader/models/saved_link.dart';
import 'package:townloader/services/links_store.dart';
import 'package:townloader/state/account_controller.dart';
import 'package:townloader/state/links_controller.dart';

/// 지도 Worker 를 흉내 낸다. 받은 요청을 남기고, 동기화한 데이터와 공유를 들고 있다.
class _FakeWorker {
  final requests = <http.Request>[];
  Map<String, dynamic>? data;
  final shares = <String, String>{};
  bool expired = false;

  MapsClient client() => MapsClient(
    baseUrl: 'https://maps.test',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (expired && request.url.path != '/api/session') {
        return http.Response('{"error":"unauthorized"}', 401);
      }
      final path = request.url.path;
      switch ((request.method, path)) {
        case ('POST', '/api/session'):
          return _json({
            'token': 'session-1',
            'user': {'email': 'me@example.com'},
          });
        case ('GET', '/api/data'):
          return _json({'data': data, 'updatedAt': 0});
        case ('PUT', '/api/data'):
          data = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({'ok': true});
        case ('GET', '/api/shares'):
          return _json({
            'shares': [
              for (final entry in shares.entries)
                {
                  'id': entry.value,
                  'category': entry.key,
                  'url': 'https://maps.test/m/${entry.value}',
                },
            ],
          });
        case ('POST', '/api/shares'):
          final category = (jsonDecode(request.body) as Map)['category'];
          final id = shares.putIfAbsent(category as String, () => 'Share1');
          return _json({
            'id': id,
            'category': category,
            'url': 'https://maps.test/m/$id',
          });
        case ('DELETE', _) when path.startsWith('/api/shares/'):
          shares.removeWhere((_, id) => path.endsWith(id));
          return _json({'ok': true});
        case ('DELETE', '/api/session' || '/api/account'):
          return _json({'ok': true});
      }
      return http.Response('{"error":"not_found"}', 404);
    }),
  );

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

SavedLink _link(String code, String category, {List<SavedPlace>? places}) =>
    SavedLink(
      code: code,
      url: 'https://www.instagram.com/p/$code/',
      category: category,
      savedAt: DateTime(2026, 10, 1),
      status: LinkStatus.ready,
      places: places ?? const [],
    );

void main() {
  late _FakeWorker worker;
  late MemoryLinksStore store;
  late LinksController links;
  String? savedSession;

  AccountController account() => AccountController(
    client: worker.client(),
    links: links,
    readSession: () async => savedSession,
    writeSession: (value) async {
      savedSession = value;
      return true;
    },
    uploadDelay: Duration.zero,
  );

  setUp(() async {
    worker = _FakeWorker();
    savedSession = null;
    store = MemoryLinksStore(
      LinksData(categories: const ['여행'], links: [_link('Local1', '여행')]),
    );
    links = LinksController(
      store: store,
      resolve: (_) => throw UnimplementedError(),
      analyze: (post, {required isKo}) async => const [],
    );
    await links.load(isKo: true);
  });

  test('로그인하면 서버 링크를 합치고, 합친 결과를 다시 올린다', () async {
    worker.data = {
      'categories': ['여행', '맛집'],
      'links': [_link('Remote1', '맛집').toJson()],
    };
    final controller = account();

    await controller.signIn('google', () async => 'google-id-token');

    expect(controller.session?.email, 'me@example.com');
    expect(jsonDecode(savedSession!)['token'], 'session-1');
    final signIn = worker.requests.first;
    expect(jsonDecode(signIn.body), {
      'provider': 'google',
      'idToken': 'google-id-token',
    });

    expect(links.categories, ['여행', '맛집']);
    expect(
      links.allLinks.map((l) => l.code),
      containsAll(['Local1', 'Remote1']),
    );
    final uploaded = worker.data!['links'] as List;
    expect(uploaded.map((l) => l['code']), containsAll(['Local1', 'Remote1']));
    expect(
      worker.requests
          .where((r) => r.method == 'PUT')
          .single
          .headers['authorization'],
      'Bearer session-1',
    );
  });

  test('취소하면 아무것도 보내지 않는다', () async {
    final controller = account();
    await controller.signIn('apple', () async => null);
    expect(controller.isSignedIn, isFalse);
    expect(worker.requests, isEmpty);
  });

  test('로그인한 뒤 링크가 바뀌면 서버에 올린다', () async {
    final controller = account();
    await controller.signIn('google', () async => 'token');
    await links.addCategory('카페');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(worker.data!['categories'], contains('카페'));
  });

  test('공유하면 최신 링크를 먼저 올리고 public 링크를 받는다', () async {
    final controller = account();
    await controller.signIn('google', () async => 'token');
    await links.addCategory('카페');

    final share = await controller.share('카페');

    expect(share.url, 'https://maps.test/m/Share1');
    expect(controller.shareOf('카페')?.id, 'Share1');
    expect(worker.data!['categories'], contains('카페'));
    final putIndex = worker.requests.lastIndexWhere((r) => r.method == 'PUT');
    final shareIndex = worker.requests.indexWhere(
      (r) => r.method == 'POST' && r.url.path == '/api/shares',
    );
    expect(putIndex, lessThan(shareIndex));

    await controller.unshare('카페');
    expect(controller.shareOf('카페'), isNull);
    expect(worker.shares, isEmpty);
  });

  test('세션이 만료되면 로그아웃 상태로 돌아간다', () async {
    savedSession = jsonEncode({'token': 'old', 'provider': 'google'});
    worker.expired = true;
    final controller = account();

    await controller.load();

    expect(controller.isSignedIn, isFalse);
    expect(savedSession, isNull);
    expect(controller.error, isNotNull);
  });

  test('계정을 삭제해도 기기의 링크는 남는다', () async {
    final controller = account();
    await controller.signIn('google', () async => 'token');

    await controller.deleteAccount();

    expect(controller.isSignedIn, isFalse);
    expect(savedSession, isNull);
    expect(worker.requests.last.url.path, '/api/account');
    expect(links.allLinks.map((l) => l.code), ['Local1']);
  });

  group('LinksController.mergeFrom', () {
    test('같은 글이면 분석이 끝난 쪽을 남긴다', () async {
      store = MemoryLinksStore(
        LinksData(
          categories: const ['여행'],
          links: [
            _link('A', '여행').copyWith(status: LinkStatus.failed),
            _link('B', '여행', places: const []),
          ],
        ),
      );
      links = LinksController(
        store: store,
        resolve: (_) => throw UnimplementedError(),
        analyze: (post, {required isKo}) async => const [],
      );
      await links.load(isKo: true);
      const place = SavedPlace(
        name: '이치란',
        lat: 35.69,
        lng: 139.7,
        source: PlaceSource.tag,
      );

      await links.mergeFrom(
        LinksData(
          categories: const ['여행'],
          links: [
            _link('A', '여행', places: const [place]),
            _link(
              'B',
              '여행',
              places: const [place],
            ).copyWith(status: LinkStatus.failed),
          ],
        ),
      );

      final byCode = {for (final l in links.allLinks) l.code: l};
      expect(byCode['A']!.places.single.name, '이치란');
      expect(byCode['B']!.places, isEmpty);
    });
  });

  group('MapsClient', () {
    test('공유 링크에서 지도 ID 를 꺼낸다', () {
      final client = MapsClient(baseUrl: 'https://maps.test');
      expect(
        client.shareIdOf(Uri.parse('https://maps.test/m/CMBKdcZxe7')),
        'CMBKdcZxe7',
      );
      expect(
        client.shareIdOf(Uri.parse('https://other.test/m/CMBKdcZxe7')),
        isNull,
      );
      expect(client.shareIdOf(Uri.parse('https://maps.test/api/data')), isNull);
    });

    test('공개 지도의 글 제목·사진을 살리고, 장소에 사진 순번을 붙인다', () {
      final map = PublicMap.fromJson({
        'category': '보은',
        'posts': [
          {
            'url': 'https://www.instagram.com/p/X/',
            'title': '예쁜 보은 카페 모음.ZIP',
            'author': 'cafe',
            'caption': '분위기 최고',
            'coverUrl': 'https://a.cdninstagram.com/0.jpg',
            'imageUrls': [
              'https://a.cdninstagram.com/0.jpg',
              'https://a.cdninstagram.com/1.jpg',
            ],
          },
          {'url': 'https://www.instagram.com/p/Y/', 'imageUrls': []},
        ],
        'places': [
          {
            'name': '카페 소소',
            'lat': 1,
            'lng': 2,
            'url': 'https://www.instagram.com/p/X/',
            'photo': 'https://a.cdninstagram.com/1.jpg',
            'post': 0,
          },
        ],
      });
      expect(map.links, hasLength(2));
      final first = map.links.first;
      expect(first.title, '예쁜 보은 카페 모음.ZIP');
      expect(first.caption, '분위기 최고');
      expect(first.places.single.imageIndex, 1);
      expect(
        first.photoFor(first.places.single),
        'https://a.cdninstagram.com/1.jpg',
      );
      expect(map.links.last.places, isEmpty);
    });

    test('공개 지도는 글마다 장소를 묶는다', () {
      final map = PublicMap.fromJson({
        'category': '도쿄',
        'places': [
          {
            'name': 'A',
            'lat': 1,
            'lng': 2,
            'url': 'https://www.instagram.com/p/X/',
            'author': 'foodie',
          },
          {
            'name': 'B',
            'lat': 3,
            'lng': 4,
            'url': 'https://www.instagram.com/p/X/',
            'author': 'foodie',
          },
          {
            'name': 'C',
            'lat': 5,
            'lng': 6,
            'url': 'https://www.instagram.com/p/Y/',
            'approximate': true,
          },
        ],
      });
      expect(map.category, '도쿄');
      expect(map.links, hasLength(2));
      expect(map.links.first.places.map((p) => p.name), ['A', 'B']);
      expect(map.links.first.author, 'foodie');
      expect(map.links.last.places.single.approximate, isTrue);
    });
  });
}
