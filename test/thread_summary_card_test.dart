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

  SummaryClient client({int status = 200}) => SummaryClient(
    baseUrl: 'https://proxy.test',
    appToken: 'token',
    httpClient: MockClient((request) async {
      expect(request.url.toString(), 'https://proxy.test/summarize');
      expect(request.headers['x-app-token'], 'token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      if (status != 200) return http.Response('{}', status);
      return http.Response(
        jsonEncode({'summary': 'summary from ${body['provider']}'}),
        200,
      );
    }),
  );

  Future<SettingsController> pump(
    WidgetTester tester, {
    required bool consent,
    int status = 200,
  }) async {
    final settings = SettingsController(_ConsentStore(consent: consent));
    await settings.load();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: ThreadSummaryCard(
              thread: _thread,
              client: client(status: status),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  setUp(() => requests = []);

  testWidgets('동의 전에는 아무것도 보내지 않고, 동의하면 요약을 불러온다', (tester) async {
    final settings = await pump(tester, consent: false);
    expect(requests, isEmpty);

    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(settings.aiSummaryConsented, isTrue);
    expect(find.text('summary from claude'), findsOneWidget);

    final sent = requests.single;
    expect(sent['id'], 'threads-Root1');
    expect(sent['posts'], [
      {'author': 'author', 'text': '(1/2) first', 'byAuthor': true},
      {'author': 'author', 'text': '(2/2) second', 'byAuthor': true},
      {'author': 'friend', 'text': 'nice', 'byAuthor': false},
    ]);
  });

  testWidgets('동의했으면 바로 요약하고, 공급자를 바꾸면 그쪽으로 다시 부른다', (tester) async {
    await pump(tester, consent: true);
    expect(find.text('summary from claude'), findsOneWidget);

    await tester.tap(find.text('Poe'));
    await tester.pumpAndSettle();
    expect(find.text('summary from poe'), findsOneWidget);

    // 이미 받은 요약은 다시 부르지 않는다.
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    expect(find.text('summary from claude'), findsOneWidget);
    expect(requests.map((r) => r['provider']), ['claude', 'poe']);
  });

  testWidgets('하루 제한에 걸리면 다시 시도 버튼 없이 안내한다', (tester) async {
    await pump(tester, consent: true, status: 429);
    expect(find.textContaining('limit'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
