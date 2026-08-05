import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/pica_comic.dart';

void main() {
  late PicaComic source;

  setUp(() {
    source = PicaComic();
  });

  group('PicaComic.parseDiscovery description', () {
    test('parses description field when present', () {
      final response = {
        'comics': [
          {
            '_id': 'xyz789',
            'title': 'Test Pica Manga',
            'author': 'Some Author',
            'thumb': <String, dynamic>{},
            'finished': false,
            'epsCount': 20,
            'likesCount': 50,
            'description': 'A pica description',
          },
        ],
      };

      final result = source.parseDiscovery(response);

      expect(result.length, 1);
      expect(result[0].id, 'xyz789');
      expect(result[0].description, 'A pica description');
    });

    test('description is null when field is missing', () {
      final response = {
        'comics': [
          {
            '_id': 'xyz789',
            'title': 'Test Pica Manga',
            'thumb': <String, dynamic>{},
          },
        ],
      };

      final result = source.parseDiscovery(response);

      expect(result[0].description, isNull);
    });
  });
}
