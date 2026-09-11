import 'package:comic_reader/data/sources/pica_comic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MangaSource exposes default login/session hooks', () {
    final source = PicaComic();

    // Defaults declared on the abstract base class.
    expect(source.needsSessionRefresh, isFalse);
    expect(
      () => source.buildRefreshRequest(),
      throwsA(isA<UnimplementedError>()),
    );
    // parseRefresh defaults to delegating to parseSignIn; with a response
    // that has no 'token' field, parseSignIn returns null.
    expect(source.parseRefresh(<String, dynamic>{}), isNull);
  });

  test('supportsAutoLogin/autoLoginEmail/autoLoginPassword/loginDescription default to null/false', () {
    // A source that does not override these (e.g. a hypothetical bare
    // MangaSource subclass) would see these defaults. PicaComic overrides
    // some of them via requiresLogin, but does NOT override
    // supportsAutoLogin/autoLoginEmail/autoLoginPassword/loginDescription,
    // so we can assert the base-class defaults through it.
    final source = PicaComic();
    expect(source.supportsAutoLogin, isFalse);
    expect(source.autoLoginEmail, isNull);
    expect(source.autoLoginPassword, isNull);
    expect(source.loginDescription, isNull);
  });
}
