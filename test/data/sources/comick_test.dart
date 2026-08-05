import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/comick.dart';

void main() {
  late ComicKSource source;

  setUp(() {
    source = ComicKSource();
  });

  group('ComicKSource.parseDiscovery description', () {
    test('parses description field when present', () {
      final input = [
        {
          'hid': 'abc123',
          'title': 'Test Manga',
          'last_chapter': 12,
          'rating': 4.5,
          'follow_count': 100,
          'desc': 'A test description',
        },
      ];

      final result = source.parseDiscovery(input);

      expect(result.length, 1);
      expect(result[0].id, 'abc123');
      expect(result[0].description, 'A test description');
    });

    test('description is null when field is missing', () {
      final input = [
        {
          'hid': 'abc123',
          'title': 'Test Manga',
        },
      ];

      final result = source.parseDiscovery(input);

      expect(result[0].description, isNull);
    });
  });
}
