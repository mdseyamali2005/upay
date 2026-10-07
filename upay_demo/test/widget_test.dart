import 'package:flutter_test/flutter_test.dart';
import 'package:upay_demo/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const UpayApp());
    expect(find.byType(UpayApp), findsOneWidget);
  });
}
