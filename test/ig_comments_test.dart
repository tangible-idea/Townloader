import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:townloader/data/hiker_client.dart';
import 'package:townloader/data/ig_repository.dart';
import 'package:townloader/data/ig_url.dart';
import 'package:townloader/data/media_parser.dart';
import 'package:townloader/models/threads_thread.dart';

/// `/v2/media/comments` 응답을 줄인 예시. 실제 응답과 같은 자리에 같은 이름으로 둔다.
Map<String, dynamic> _comments({bool hasMore = true}) => {
  'response': {
    'comment_count': 120,
    'has_more_comments': hasMore,
    'comments': [
      {
        'pk': '1801',
        'text': 'Amazing shot!',
        'created_at_utc': 1787780000,
        'user': {'pk': 11, 'username': 'kim.films', 'is_verified': false},
        'preview_child_comments': [
          {
            'pk': '1802',
            'text': 'Thank you!',
            'created_at_utc': 1787780100,
            'user': {'pk': 22, 'username': 'marks.photo', 'is_verified': true},
          },
        ],
      },
      // 글 없는 댓글(스티커 등)은 빠진다.
      {
        'pk': '1803',
        'text': '',
        'user': {'pk': 33, 'username': 'sticker.only'},
      },
      {
        'pk': '1804',
        'text': 'Where is this?',
        'created_at_utc': 1787780200,
        'user': {'pk': 44, 'username': 'traveler'},
      },
    ],
  },
  'next_page_id': 'abc',
};

Map<String, dynamic> get _media => {
  'pk': '3972507450993765709',
  'id': '3972507450993765709_22',
  'code': 'DchLnq8E21N',
  'taken_at': 1787779818,
  'media_type': 1,
  'caption_text': 'Day 3 in the Dolomites.',
  'user': {'pk': 22, 'username': 'marks.photo'},
  'image_versions': [
    {'url': 'https://cdn.test/a.jpg', 'width': 1080, 'height': 1350},
  ],
  'thumbnail_url': 'https://cdn.test/a.jpg',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('댓글과 대댓글을 순서대로, 대댓글은 한 단계 더 들여서 만든다', () {
    final parsed = MediaParser.parseComments(_comments());

    expect(parsed.hasMore, isTrue);
    expect(
      [
        for (final n in parsed.nodes)
          (n.post.authorName, n.post.caption, n.depth),
      ],
      [
        ('kim.films', 'Amazing shot!', 1),
        ('marks.photo', 'Thank you!', 2),
        ('traveler', 'Where is this?', 1),
      ],
    );
    expect(parsed.nodes.every((n) => n.role == ThreadRole.reply), isTrue);
  });

  test('인스타 게시물을 열면 댓글까지 스레드 트리로 묶는다', () async {
    final paths = <String>[];
    final repository = IgRepository(
      HikerClient(
        readApiKey: () => 'key',
        proxyUrl: '',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/v2/media/comments') {
            expect(request.url.queryParameters['id'], '3972507450993765709');
            return http.Response(jsonEncode(_comments(hasMore: false)), 200);
          }
          return http.Response(jsonEncode(_media), 200);
        }),
      ),
    );

    final result = await repository.resolve(
      IgUrlParser.parse('https://www.instagram.com/p/DchLnq8E21N/'),
    );

    expect(paths, ['/v1/media/by/code', '/v2/media/comments']);
    final thread = result.thread!;
    expect(thread.root.code, 'DchLnq8E21N');
    expect(thread.replyCount, 3);
    expect(thread.hasMoreReplies, isFalse);
    expect(result.posts.single.code, 'DchLnq8E21N');
  });

  test('댓글을 못 가져와도 게시물은 그대로 연다', () async {
    final repository = IgRepository(
      HikerClient(
        readApiKey: () => 'key',
        proxyUrl: '',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v2/media/comments') {
            return http.Response(jsonEncode({'detail': 'nope'}), 500);
          }
          return http.Response(jsonEncode(_media), 200);
        }),
      ),
    );

    final result = await repository.resolve(
      IgUrlParser.parse('https://www.instagram.com/p/DchLnq8E21N/'),
    );

    expect(result.thread, isNull);
    expect(result.posts.single.code, 'DchLnq8E21N');
  });
}
