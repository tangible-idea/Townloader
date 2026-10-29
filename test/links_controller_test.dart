import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:townloader/data/hiker_client.dart';
import 'package:townloader/data/ig_repository.dart';
import 'package:townloader/data/ig_url.dart';
import 'package:townloader/data/maps_client.dart';
import 'package:townloader/data/media_parser.dart';
import 'package:townloader/data/places_client.dart';
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

  test('카카오맵에서 장소의 대표 사진·업종·별점·전화번호·리뷰를 찾아 채우고 우선 표시한다', () async {
    final client = PlacesClient(
      httpClient: MockClient((request) async {
        if (request.url.host == 'place-api.map.kakao.com') {
          final panel = jsonEncode({
            'ai_mate': {
              'summary': {'title': '도심 속 고즈넉한 산책 명소'},
              'bottom_sheet': {'summary': '돌담길과 야간 개장이 아름다운 궁궐입니다.'},
              'blog_summaries': [
                {
                  'title': '분위기',
                  'keywords': ['고즈넉한', '산책하기좋은'],
                },
              ],
            },
            'open_hours': {
              'headline': {
                'display_text': '영업 중',
                'display_text_info': '21:00에 영업 종료',
              },
              'week_from_today': {
                'week_periods': [
                  {
                    'days': [
                      {
                        'day_of_the_week_desc': '목(10/29)',
                        'on_days': {'start_end_time_desc': '09:00 ~ 21:00'},
                      },
                    ],
                  },
                ],
              },
            },
            'menu': {
              'menus': {
                'items': [
                  {'name': '일반권 (개인)', 'price': 1000, 'desc': '만25세~만64세'},
                ],
              },
            },
            'kakaomap_review': {
              'strength_description': [
                {'id': 9, 'name': '뷰'},
              ],
              'score_set': {
                'strength_counts': [
                  {'id': 9, 'count': 360},
                ],
              },
              'reviews': [
                {
                  'star_rating': 5,
                  'contents': '아이들과 방문하기 좋습니다.',
                  'registered_at': '2025-11-25 14:23:27',
                  'meta': {
                    'owner': {'nickname': 'sung hyun'},
                  },
                },
              ],
            },
            'blog_review': {
              'reviews': [
                {
                  'title': '덕수궁 단풍 절정시기 돌담길 포토존',
                  'contents': '서울 도심에서 가장 운치 있는 산책길',
                  'author': 'Save Memory',
                  'registered_at': '2026-10-25 02:46:00',
                  'origin_url': 'https://blog.naver.com/test/1',
                },
              ],
            },
          });
          return http.Response.bytes(
            utf8.encode(panel),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(request.url.host, 'search.map.kakao.com');
        final payload = jsonEncode({
          'place': [
            {
              'confirmid': '10305191',
              'name': '덕수궁',
              'last_cate_name': '고궁,궁',
              'address': '서울 중구 정동 5-1',
              'new_address': '서울 중구 세종대로 99',
              'tel': '02-771-9951',
              'rating_average': 4.8,
              'reviewCount': 1515,
              'img':
                  'http://t1.kakaocdn.net/local/booking/review/78A2D8980B9049FB9992B12C05E64FF7',
            },
          ],
        });
        return http.Response.bytes(
          utf8.encode('/**/j($payload);'),
          200,
          headers: {'content-type': 'application/javascript; charset=utf-8'},
        );
      }),
    );

    final enriched = await client.enrichPlace(_place);
    expect(enriched.category, '고궁,궁');
    expect(enriched.phone, '02-771-9951');
    expect(enriched.rating, 4.8);
    expect(enriched.reviewCount, 1515);
    expect(enriched.summary, '도심 속 고즈넉한 산책 명소');
    expect(enriched.placeUrl, 'https://place.map.kakao.com/10305191');
    expect(
      enriched.photoUrl,
      'https://img1.kakaocdn.net/cthumb/local/R400x0/?fname=https%3A%2F%2Ft1.kakaocdn.net%2Flocal%2Fbooking%2Freview%2F78A2D8980B9049FB9992B12C05E64FF7',
    );

    final detail = await client.fetchPlaceDetail(enriched);
    expect(detail?.aiTitle, '도심 속 고즈넉한 산책 명소');
    expect(detail?.aiSummary, '돌담길과 야간 개장이 아름다운 궁궐입니다.');
    expect(detail?.aiKeywords, ['고즈넉한', '산책하기좋은']);
    expect(detail?.openStatus, '영업 중 · 21:00에 영업 종료');
    expect(detail?.menus.single.name, '일반권 (개인)');
    expect(detail?.menus.single.price, 1000);
    expect(detail?.strengths.single.name, '뷰');
    expect(detail?.strengths.single.count, 360);
    expect(detail?.visitorReviews.single.contents, '아이들과 방문하기 좋습니다.');
    expect(detail?.blogReviews.single.title, '덕수궁 단풍 절정시기 돌담길 포토존');

    final link = SavedLink(
      code: 'DdK3PpFmpRJ',
      url: 'https://www.instagram.com/p/DdK3PpFmpRJ/',
      category: '여행',
      savedAt: DateTime(2026),
      imageUrls: const ['https://cdn/0.jpg', 'https://cdn/1.jpg'],
      places: [enriched],
    );
    expect(link.photoFor(enriched), enriched.photoUrl);

    final roundTrip = SavedPlace.fromJson(enriched.toJson());
    expect(roundTrip.category, '고궁,궁');
    expect(roundTrip.photoUrl, enriched.photoUrl);
    expect(roundTrip.rating, 4.8);
    expect(roundTrip.reviewCount, 1515);
    expect(roundTrip.summary, '도심 속 고즈넉한 산책 명소');
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
