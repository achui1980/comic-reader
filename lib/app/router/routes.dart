/// Route path constants and helper methods.
class AppRoutes {
  static const home = '/';
  static const discovery = '/discovery';
  static const search = '/search';
  static const detail = '/detail/:sourceId/:mangaId';
  static const reader = '/reader/:sourceId/:mangaId/:chapterId';
  static const settings = '/settings';
  static const webview = '/webview/:sourceId';

  /// Build detail path with parameters.
  ///
  /// Each parameter is percent-encoded with [Uri.encodeComponent] so that ids
  /// containing slashes (e.g. `manhwa/secret-class`) survive as a single
  /// go_router path segment. go_router decodes the value back automatically
  /// when reading `state.pathParameters`, so encoding here is idempotent for
  /// slug-only ids and safe to re-apply on round trips.
  static String detailPath(String sourceId, String mangaId) =>
      '/detail/${Uri.encodeComponent(sourceId)}/${Uri.encodeComponent(mangaId)}';

  /// Build reader path with parameters. See [detailPath] for encoding notes.
  static String readerPath(String sourceId, String mangaId, String chapterId) =>
      '/reader/${Uri.encodeComponent(sourceId)}/${Uri.encodeComponent(mangaId)}'
      '/${Uri.encodeComponent(chapterId)}';

  /// Build webview path with parameters.
  static String webviewPath(String sourceId) =>
      '/webview/${Uri.encodeComponent(sourceId)}';
}
