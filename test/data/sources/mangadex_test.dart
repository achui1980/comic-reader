import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/mangadex.dart';

void main() {
  late MangaDexSource source;

  setUp(() {
    source = MangaDexSource();
  });

  group('MangaDexSource.parseDiscovery description', () {
    test('parses description field when present', () {
      final input = {
        'data': [
          {
            'id': 'abc-123',
            'attributes': {
              'title': {'en': 'Test Manga'},
              'altTitles': [],
              'description': {'en': 'A test description'},
              'availableTranslatedLanguages': ['en'],
            },
            'relationships': [],
          },
        ],
      };

      final result = source.parseDiscovery(input);

      expect(result.length, 1);
      expect(result[0].id, 'abc-123');
      expect(result[0].description, 'A test description');
    });

    test('description is null when field is missing', () {
      final input = {
        'data': [
          {
            'id': 'abc-123',
            'attributes': {
              'title': {'en': 'Test Manga'},
              'altTitles': [],
              'availableTranslatedLanguages': ['en'],
            },
            'relationships': [],
          },
        ],
      };

      final result = source.parseDiscovery(input);

      expect(result[0].description, isNull);
    });
  });
}
