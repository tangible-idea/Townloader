import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:townloader/data/ig_url.dart';
import 'package:townloader/data/threads_client.dart';
import 'package:townloader/models/ig_post.dart';
import 'package:townloader/models/threads_thread.dart';
import 'package:townloader/ui/widgets/thread_tree.dart';

/// 실제 게시물 페이지와 같은 구조로 만든 예시. 본체(code 가 있는 객체)와
/// 스레드·댓글 정보(`<pk>_<작성자 id>` id 만 가진 객체)가 서로 다른 조각에 실린다.
String _page({bool moreReplies = true}) {
  Map<String, dynamic> post(
    String code,
    String user,
    String text, {
    String? photo,
    List<String> videos = const [],
  }) => {
    'pk': '9$code',
    'code': code,
    'media_type': videos.isNotEmpty ? 2 : (photo != null ? 1 : 19),
    'user': {'pk': '1$user', 'username': user},
    'caption': {'text': text},
    'taken_at': 1789772422,
    'image_versions2': {
      'candidates': [
        if (photo != null) ...[
          {'url': '$photo?small', 'width': '640', 'height': '360'},
          {'url': photo, 'width': '1600', 'height': '900'},
        ],
      ],
    },
    if (videos.isNotEmpty)
      'video_versions': [
        for (final url in videos) {'type': '101', 'url': url},
      ],
    'text_post_app_info': <String, dynamic>{},
  };

  Map<String, dynamic> edge(Map<String, dynamic> node) => {'node': node};

  final body = {
    'require': [
      {
        'result': {
          'data': {'media': post('DdRootPost1', 'author', '본문 글')},
        },
      },
    ],
  };
  final thread = {
    'require': [
      {
        'media': {
          'id': '9DdRootPost1_1author',
          'text_post_app_info': {
            'self_thread': {
              'posts': {
                'edges': [
                  edge(
                    post(
                      'SELF1',
                      'author',
                      '1/ 동영상',
                      videos: [
                        'https://cdn/self1-hd.mp4',
                        'https://cdn/self1-sd.mp4',
                      ],
                    ),
                  ),
                  edge(post('SELF2', 'author', '2/ 글만')),
                ],
                'page_info': {'has_next_page': false},
              },
            },
            'direct_replies': {
              'edges': [
                edge({
                  'posts': {
                    'edges': [
                      edge(
                        post(
                          'REPLY1',
                          'friend',
                          '댓글 사진',
                          photo: 'https://cdn/reply1.jpg',
                        ),
                      ),
                      edge(post('REPLY1A', 'author', '답글')),
                    ],
                  },
                }),
                edge({
                  'posts': {
                    'edges': [edge(post('REPLY2', 'other', '글만 단 댓글'))],
                  },
                }),
              ],
              'page_info': {'has_next_page': moreReplies},
            },
          },
        },
      },
    ],
  };

  return '''
    <html><body>
      <script type="application/json" data-sjs>${jsonEncode(body)}</script>
      <script type="application/json" data-sjs>{"unrelated":true}</script>
      <script type="application/json" data-sjs>${jsonEncode(thread)}</script>
    </body></html>
  ''';
}

void main() {
  group('ThreadsClient.parseThreadPage', () {
    test('본문 → 이어지는 글 → 댓글(답글은 한 단계 더 깊게) 순으로 트리를 만든다', () {
      final thread = ThreadsClient.parseThreadPage(
        _page(),
        code: 'DdRootPost1',
      )!;

      expect(
        [
          for (final node in thread.nodes)
            (node.post.code, node.role, node.depth),
        ],
        [
          ('DdRootPost1', ThreadRole.root, 0),
          ('SELF1', ThreadRole.continuation, 0),
          ('SELF2', ThreadRole.continuation, 0),
          ('REPLY1', ThreadRole.reply, 1),
          ('REPLY1A', ThreadRole.reply, 2),
          ('REPLY2', ThreadRole.reply, 1),
        ],
      );
      expect(thread.hasMoreReplies, isTrue);
    });

    test('본문 미디어는 링크한 글만, 전체는 이어지는 글·댓글 미디어까지 고른다', () {
      final thread = ThreadsClient.parseThreadPage(
        _page(),
        code: 'DdRootPost1',
      )!;

      // 링크한 글에는 미디어가 없다.
      expect(thread.mainPosts, isEmpty);
      expect(thread.allPosts.map((post) => post.code), ['SELF1', 'REPLY1']);
      expect(ThreadsThread.fileCount(thread.allPosts), 2);
    });

    test('동영상은 첫 후보(최고 화질), 사진은 가장 큰 후보를 받는다', () {
      final thread = ThreadsClient.parseThreadPage(
        _page(),
        code: 'DdRootPost1',
      )!;
      final self1 = thread.nodes[1].post.items.single;
      final reply1 = thread.nodes[3].post.items.single;

      expect(self1.best?.url, 'https://cdn/self1-hd.mp4');
      expect(self1.variants, hasLength(1));
      expect(reply1.best?.url, 'https://cdn/reply1.jpg');
    });

    test('게시물 JSON 이 없으면 null 을 돌려준다', () {
      expect(
        ThreadsClient.parseThreadPage('<html></html>', code: 'DdRootPost1'),
        isNull,
      );
    });

    test('스레드 정보 조각이 없으면 본문 하나만 담는다', () {
      final html = _page().split('{"unrelated":true}').first;
      final thread = ThreadsClient.parseThreadPage(html, code: 'DdRootPost1')!;

      expect(thread.isSinglePost, isTrue);
    });
  });

  test('fetchThread 는 embed 가 아닌 게시물 페이지를 탐색 요청 헤더로 받는다', () async {
    final client = ThreadsClient(
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://www.threads.com/@author/post/DdRootPost1',
        );
        expect(request.headers['sec-fetch-mode'], 'navigate');
        return http.Response.bytes(utf8.encode(_page()), 200);
      }),
    );

    final thread = await client.fetchThread(
      IgUrlParser.parse(
        'https://www.threads.com/@author/post/DdRootPost1?xmt=abc',
      ),
    );

    expect(thread?.nodes, hasLength(6));
    client.close();
  });

  testWidgets('작성자 스레드·댓글 구역과 두 가지 받기 버튼을 보여 주고 고른 범위를 넘긴다', (tester) async {
    final thread = ThreadsClient.parseThreadPage(_page(), code: 'DdRootPost1')!;
    List<IgPost>? picked;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ThreadTree(
              thread: thread,
              onDownload: (posts) => picked = posts,
            ),
          ),
        ),
      ),
    );

    expect(find.text('@author'), findsWidgets);
    expect(find.text('@friend'), findsOneWidget);
    expect(find.text('댓글은 앞부분만 불러옵니다.'), findsOneWidget);

    expect(find.text('작성자 스레드 3'), findsOneWidget);
    expect(find.text('댓글 3'), findsOneWidget);

    // 링크한 글에 미디어가 없으면 본문만 받기는 꺼져 있다.
    await tester.tap(find.text('본문만 (0)'));
    expect(picked, isNull);

    await tester.tap(find.text('전체 (2)'));
    expect(picked?.map((post) => post.code), ['SELF1', 'REPLY1']);
  });
}
