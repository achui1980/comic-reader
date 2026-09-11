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

  test('PicaComic overrides supportsAutoLogin/autoLoginEmail/autoLoginPassword with its built-in credentials', () {
    // PicaComic overrides these to preserve its pre-refactor behavior of
    // auto-logging in with built-in credentials. loginDescription is not
    // overridden, so it still falls back to the base-class default.
    final source = PicaComic();
    expect(source.supportsAutoLogin, isTrue);
    expect(source.autoLoginEmail, PicaComic.defaultEmail);
    expect(source.autoLoginPassword, PicaComic.defaultPassword);
    expect(source.loginDescription, isNull);
  });
}
