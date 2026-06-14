import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader/app/app.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ComicReaderApp());

    expect(find.text('Home'), findsOneWidget);
  });
}
