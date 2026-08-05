import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/domain/entities/entities.dart';

void main() {
  group('MangaSummary.description', () {
    test('defaults to null when not provided', () {
      const summary = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
      );
      expect(summary.description, isNull);
    });

    test('can be set via constructor', () {
      const summary = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
        description: 'A test description',
      );
      expect(summary.description, 'A test description');
    });

    test('copyWith updates description without affecting other fields', () {
      const original = MangaSummary(
        id: '1',
        sourceId: 'test',
        title: 'Test Manga',
        coverUrl: 'https://example.com/cover.jpg',
      );
      final updated = original.copyWith(description: 'New description');
      expect(updated.description, 'New description');
      expect(updated.id, original.id);
      expect(updated.title, original.title);
      expect(updated.coverUrl, original.coverUrl);
    });

    test('two summaries with different description are not equal', () {
      const a = MangaSummary(
        id: '1',
        sourceId: 's',
        title: 't',
        coverUrl: 'c',
        description: 'A',
      );
      const b = MangaSummary(
        id: '1',
        sourceId: 's',
        title: 't',
        coverUrl: 'c',
        description: 'B',
      );
      expect(a == b, isFalse);
    });
  });
}
