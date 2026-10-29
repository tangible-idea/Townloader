import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/models/ig_post.dart';
import 'package:townloader/models/ig_user.dart';
import 'package:townloader/ui/widgets/comment_overlay.dart';

IgPost _comment(int n) => IgPost(
  pk: 'c$n',
  kind: PostKind.photo,
  user: IgUser(pk: 'u$n', username: 'user$n'),
  caption: '댓글 $n',
  items: const [],
);

void main() {
  final comments = [for (var n = 1; n <= 5; n++) _comment(n)];
  const interval = Duration(seconds: 1);

  Future<void> pump(
    WidgetTester tester, {
    int? highlighted,
    List<IgPost>? list,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 400,
          child: CommentOverlay(
            comments: list ?? comments,
            highlighted: highlighted,
            interval: interval,
          ),
        ),
      ),
    ),
  );

  testWidgets('댓글을 하나씩 차례로 띄우고, 세 개까지만 쌓는다', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('댓글 1'), findsOneWidget);
    expect(find.textContaining('댓글 2'), findsNothing);

    await tester.pump(interval);
    await tester.pumpAndSettle();
    expect(find.textContaining('댓글 2'), findsOneWidget);

    await tester.pump(interval);
    await tester.pump(interval);
    await tester.pumpAndSettle();
    // 네 번째가 붙으면 첫 번째는 밀려 사라진다.
    expect(find.textContaining('댓글 4'), findsOneWidget);
    expect(find.textContaining('댓글 1'), findsNothing);
    expect(find.textContaining('댓글 2'), findsOneWidget);
  });

  testWidgets('읽는 중이면 그 댓글까지 보여 주고 강조하며, 저절로 넘어가지 않는다', (tester) async {
    await pump(tester, highlighted: 3);
    await tester.pumpAndSettle();
    expect(find.textContaining('댓글 4'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.pump(interval * 3);
    await tester.pumpAndSettle();
    expect(find.textContaining('댓글 4'), findsOneWidget);
    expect(find.textContaining('댓글 5'), findsNothing);

    // 읽기가 끝나면 강조가 풀리고 다시 차례로 넘어간다.
    await pump(tester);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsNothing);
    await tester.pump(interval);
    await tester.pumpAndSettle();
    expect(find.textContaining('댓글 5'), findsOneWidget);
  });

  testWidgets('댓글이 하나면 그대로 띄워 둔다', (tester) async {
    await pump(tester, list: [comments.first]);
    await tester.pump(interval * 5);
    await tester.pumpAndSettle();
    expect(find.textContaining('댓글 1'), findsOneWidget);
  });
}
