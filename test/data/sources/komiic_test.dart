import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/komiic.dart';

void main() {
  late Komiic source;

  setUp(() {
    source = Komiic();
  });

  group('Komiic.parseDiscovery description', () {
    test('parses description field when present', () {
      final response = {
        'data': {
          'comics': [
            {
              'id': 'abc123',
              'title': 'Test Komiic Manga',
              'status': 'ongoing',
              'imageUrl': 'https://example.com/cover.jpg',
              'authors': [
                {'id': '1', 'name': 'Some Author'}
              ],
              'description': 'A komiic description',
            },
          ],
        },
      };

      final result = source.parseDiscovery(response);

      expect(result.length, 1);
      expect(result[0].id, 'abc123');
      expect(result[0].description, 'A komiic description');
    });

    test('description is null when field is missing', () {
      final response = {
        'data': {
          'comics': [
            {
              'id': 'abc123',
              'title': 'Test Komiic Manga',
              'imageUrl': 'https://example.com/cover.jpg',
            },
          ],
        },
      };

      final result = source.parseDiscovery(response);

      expect(result[0].description, isNull);
    });
  });
}
