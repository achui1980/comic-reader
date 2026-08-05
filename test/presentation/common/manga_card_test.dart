import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/presentation/common/manga_card.dart';

void main() {
  const baseManga = MangaSummary(
    id: '1',
    sourceId: 'test',
    title: 'Test Manga',
    coverUrl: 'https://example.com/cover.jpg',
    author: 'Test Author',
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('MangaListItem', () {
    testWidgets('renders title and author', (tester) async {
      await tester.pumpWidget(wrap(const MangaListItem(manga: baseManga)));
      expect(find.text('Test Manga'), findsOneWidget);
      expect(find.text('Test Author'), findsOneWidget);
    });

    testWidgets('does not render a description when null', (tester) async {
      await tester.pumpWidget(wrap(const MangaListItem(manga: baseManga)));
      expect(find.text('A description'), findsNothing);
    });

    testWidgets('renders description text when present', (tester) async {
      const manga = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        description: 'A description',
      );
      await tester.pumpWidget(wrap(const MangaListItem(manga: manga)));
      expect(find.text('A description'), findsOneWidget);
    });

    testWidgets('renders no chips when chapterCount/popularityText/updateTime are all missing',
        (tester) async {
      await tester.pumpWidget(wrap(const MangaListItem(manga: baseManga)));
      // NOTE: deviates from the plan's literal `expect(find.byType(Container),
      // findsNothing)` — MangaCoverImage's own CachedNetworkImage placeholder
      // (lib/presentation/common/manga_cover_image.dart:269) always renders a
      // Container while the (fake, unresolved) network image is loading, so
      // that assertion fails even with zero chips rendered. Checking the
      // chip Wrap's children directly tests "no chips" without coupling to
      // MangaCoverImage's unrelated internals.
      final chipWrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(chipWrap.children, isEmpty);
    });

    testWidgets('renders a chapterCount chip when present', (tester) async {
      const manga = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        chapterCount: 42,
      );
      await tester.pumpWidget(wrap(const MangaListItem(manga: manga)));
      expect(find.text('42章'), findsOneWidget);
    });
  });

  group('MangaGridCard', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(wrap(const MangaGridCard(manga: baseManga)));
      expect(find.text('Test Manga'), findsOneWidget);
    });

    testWidgets('renders chapterCount + popularityText as meta text', (tester) async {
      const manga = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        chapterCount: 10,
        popularityText: '100 views',
      );
      await tester.pumpWidget(wrap(const MangaGridCard(manga: manga)));
      expect(find.text('10章 · 100 views'), findsOneWidget);
    });
  });
}
