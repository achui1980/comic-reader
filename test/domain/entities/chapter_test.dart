import 'package:comic_reader/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChapterImage carries hanabi scramble metadata', () {
    const image = ChapterImage(
      url: 'https://cdn.hanabimanga.top/fake.webp',
      scrambleType: ScrambleType.hanabi,
      hanabiTicket: 'ticket-b64',
      hanabiNonce: 'nonce-b64',
      hanabiCols: 4,
      hanabiRows: 4,
    );

    expect(image.scrambleType, ScrambleType.hanabi);
    expect(image.hanabiTicket, 'ticket-b64');
    expect(image.hanabiNonce, 'nonce-b64');
    expect(image.hanabiCols, 4);
    expect(image.hanabiRows, 4);
  });

  test('ScrambleType.hanabi is a distinct enum value', () {
    expect(ScrambleType.values, contains(ScrambleType.hanabi));
  });
}
