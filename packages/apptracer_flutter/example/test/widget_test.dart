import 'package:apptracer_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the example page', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Пример apptracer_flutter'), findsOneWidget);
    expect(find.text('Бросить синхронно'), findsOneWidget);
  });
}
