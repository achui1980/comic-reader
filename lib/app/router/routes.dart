/// Route path constants and helper methods.
class AppRoutes {
  static const home = '/';
  static const discovery = '/discovery';
  static const search = '/search';
  static const detail = '/detail/:sourceId/:mangaId';
  static const reader = '/reader/:sourceId/:mangaId/:chapterId';
  static const settings = '/settings';

  /// Build detail path with parameters
  static String detailPath(String sourceId, String mangaId) =>
      '/detail/$sourceId/$mangaId';

  /// Build reader path with parameters
  static String readerPath(String sourceId, String mangaId, String chapterId) =>
      '/reader/$sourceId/$mangaId/$chapterId';
}
