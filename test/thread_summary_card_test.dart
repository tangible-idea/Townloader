import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:townloader/data/summary_client.dart';
import 'package:townloader/models/ig_post.dart';
import 'package:townloader/models/ig_user.dart';
import 'package:townloader/models/media_source.dart';
import 'package:townloader/models/threads_thread.dart';
import 'package:townloader/services/settings_store.dart';
import 'package:townloader/state/settings_controller.dart';
import 'package:townloader/ui/widgets/thread_summary_card.dart';

class _ConsentStore extends SettingsStore {
  _ConsentStore({this.consent = false});

  bool consent;

  @override
  Future<SettingsBackend> get backend async => SettingsBackend.keychain;

  @override
  Future<QualityPreference> readQuality() async => QualityPreference.best;

  @override
  Future<bool> readSaveToGallery() async => true;

  @override
  Future<bool> readPersonalUseAck() async => true;

  @override
  Future<bool> readAiSummaryConsent() async => consent;

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
  Future<bool> writeAiSummaryConsent() async {
    consent = true;
    return true;
  }
}

IgPost _post(String code, String user, String text) => IgPost(
  pk: code,
  code: code,
  source: MediaSource.threads,
  kind: PostKind.photo,
  user: IgUser(pk: user, username: user),
  caption: text,
  items: const [],
);

final _thread = ThreadsThread(
  nodes: [
    ThreadNode(
      post: _post('Root1', 'author', '(1/2) first'),
      role: ThreadRole.root,
      depth: 0,
    ),
    ThreadNode(
      post: _post('Cont2', 'author', '(2/2) second'),
      role: ThreadRole.continuation,
      depth: 0,
    ),
    ThreadNode(
      post: _post('Reply3', 'friend', 'nice'),
      role: ThreadRole.reply,
      depth: 1,
    ),
  ],
);

void main() {
  late List<Map<String, dynamic>> requests;

  late List<Map<String, dynamic>> votes;

  SummaryClient client({int status = 200, int voteStatus = 200}) => SummaryClient(
    baseUrl: 'https://proxy.test',
    appToken: 'token',
    httpClient: MockClient((request) async {
      expect(request.headers['x-app-token'], 'token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.toString() == 'https://proxy.test/summary-feedback') {
        votes.add(body);
        return http.Response('{}', voteStatus);
      }
      expect(request.url.toString(), 'https://proxy.test/summarize');
      requests.add(body);
      if (status != 200) return http.Response('{}', status);
      return http.Response(
        jsonEncode({
          'summary': '첫 줄\n둘째 줄\n셋째\n넷째\n다섯째\n여섯째',
          'comments': ['공감이 많다', '질문이 있다'],
          'provider': 'poe',
          'model': 'bot',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  Future<SettingsController> pump(
    WidgetTester tester, {
    required bool consent,
    int status = 200,
    int voteStatus = 200,
  }) async {
    final settings = SettingsController(_ConsentStore(consent: consent));
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ThreadSummaryCard(
                thread: _thread,
                client: client(status: status, voteStatus: voteStatus),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  setUp(() {
    requests = [];
    votes = [];
  });

  testWidgets('동의 전에는 아무것도 보내지 않고, 동의하면 요약을 불러온다', (tester) async {
    final settings = await pump(tester, consent: false);
    expect(requests, isEmpty);

    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(find.text('Agree and summarize'));
    await tester.pumpAndSettle();
    expect(settings.aiSummaryConsented, isTrue);
    expect(find.text('첫 줄'), findsOneWidget);

    final sent = requests.single;
    expect(sent['id'], 'threads-Root1');
    expect(sent['kind'], 'digest');
    expect(sent.containsKey('provider'), isFalse);
    expect(sent['posts'], [
      {'author': 'author', 'text': '(1/2) first', 'byAuthor': true},
      {'author': 'author', 'text': '(2/2) second', 'byAuthor': true},
      {'author': 'friend', 'text': 'nice', 'byAuthor': false},
    ]);
  });

  testWidgets('본문 요약은 5줄까지, 그 아래 댓글 요점을 블릿으로 보인다', (tester) async {
    await pump(tester, consent: true);
    expect(find.text('다섯째'), findsOneWidget);
    expect(find.text('여섯째'), findsNothing);
    expect(find.text('Reply summary'), findsOneWidget);
    expect(find.text('공감이 많다'), findsOneWidget);
    expect(find.text('질문이 있다'), findsOneWidget);
    // 어느 모델인지 보여 주지 않고, 고를 수도 없다.
    expect(find.text('Poe'), findsNothing);
    expect(find.text('Claude'), findsNothing);
  });

  testWidgets('평가는 받은 공급자로 보내고, 바꾸면 덮어쓰고, 다시 누르면 취소한다', (tester) async {
    final settings = await pump(tester, consent: true);
    const key = 'poe:threads-Root1';

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);
    expect(settings.summaryVote(key)?.vote, SummaryVote.up);
    expect(votes.single['provider'], 'poe');
    expect(votes.single['model'], 'bot');
    expect(votes.single['vote'], 'up');
    expect(votes.single['voteId'], matches(RegExp(r'^[a-f0-9]{32}$')));

    await tester.tap(find.byIcon(Icons.thumb_down_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.thumb_down), findsOneWidget);
    expect(find.byIcon(Icons.thumb_up), findsNothing);
    expect(votes[1]['vote'], 'down');
    expect(votes[1]['voteId'], votes[0]['voteId']);

    await tester.tap(find.byIcon(Icons.thumb_down));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.thumb_down), findsNothing);
    expect(votes[2]['vote'], 'none');
    expect(votes[2]['voteId'], votes[0]['voteId']);
    expect(settings.summaryVote(key), isNull);
  });

  testWidgets('평가를 보내지 못하면 표시를 되돌린다', (tester) async {
    final settings = await pump(tester, consent: true, voteStatus: 500);

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.thumb_up), findsNothing);
    expect(settings.summaryVote('poe:threads-Root1'), isNull);
  });

  testWidgets('하루 제한에 걸리면 다시 시도 버튼 없이 안내한다', (tester) async {
    await pump(tester, consent: true, status: 429);
    expect(find.textContaining('limit'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
