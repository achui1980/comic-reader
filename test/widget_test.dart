import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:comic_reader/app/app.dart';
import 'package:comic_reader/app/di/injection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // ComicReaderApp resolves SettingsStore / LocalStorage / SourceRegistry /
    // FavoritesStore from GetIt during build, so DI must be wired up first.
    await GetIt.instance.reset();
    configureDependencies();
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('App builds and mounts a MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const ComicReaderApp());
    // A single pump is enough to build the router shell; we intentionally do
    // NOT pumpAndSettle() because async data loads would hang the fake async.
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
