import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:townloader/ui/widgets/shimmer.dart';

void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('제한 시간이 지나면 대신할 위젯으로 바꾼다', (tester) async {
    await tester.pumpWidget(
      app(
        const ShimmerBox(
          timeout: Duration(seconds: 1),
          timedOut: Text('fallback'),
        ),
      ),
    );
    expect(find.text('fallback'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('장소 칩 뼈대는 두 줄로 좁은 화면에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(const PlaceChipsSkeleton()));
    await tester.pump();
    expect(find.byType(Row), findsNWidgets(2));
    expect(find.byType(ShimmerBox), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });
}
