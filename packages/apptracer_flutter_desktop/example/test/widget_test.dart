import 'package:apptracer_desktop_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native crash requires confirmation', (tester) async {
    await tester.pumpWidget(const DesktopProbeApp());
    await tester.tap(find.text('Native crash…'));
    await tester.pumpAndSettle();
    expect(find.text('Terminate the example?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Terminate the example?'), findsNothing);
  });
}
