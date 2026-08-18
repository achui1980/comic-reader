import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'models/page_translation.dart';

/// Persists [PageTranslation] results as one JSON file per page, mirroring
/// the on-disk layout of `ChapterCacheService`. Native-only: every method
/// is a no-op / returns null on web.
class TranslationCacheStore {
  TranslationCacheStore({Future<String> Function()? baseDirResolver})
      : _baseDirResolver = baseDirResolver ?? _defaultBaseDir;

  final Future<String> Function() _baseDirResolver;
  String? _basePath;

  static Future<String> _defaultBaseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> get _cachePath async {
    if (_basePath != null) return _basePath!;
    if (kIsWeb) {
      _basePath = '';
      return '';
    }
    final base = await _baseDirResolver();
    _basePath = '$base/translation_cache';
    return _basePath!;
  }

  String _safe(String id) => id.replaceAll(RegExp(r'[^\w\-.]'), '_');

  Future<String> _pagePath(
      String sourceId, String mangaId, String chapterId, int pageIndex) async {
    final base = await _cachePath;
    final dir =
        '$base/${_safe(sourceId)}/${_safe(mangaId)}/${_safe(chapterId)}';
    return '$dir/$pageIndex.json';
  }

  Future<PageTranslation?> get(
      String sourceId, String mangaId, String chapterId, int pageIndex) async {
    if (kIsWeb) return null;
    final path = await _pagePath(sourceId, mangaId, chapterId, pageIndex);
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return PageTranslation.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PageTranslation translation) async {
    if (kIsWeb) return;
    final path = await _pagePath(translation.sourceId, translation.mangaId,
        translation.chapterId, translation.pageIndex);
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(translation.toJson()));
  }

  Future<void> clearChapter(
      String sourceId, String mangaId, String chapterId) async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final dir = Directory(
        '$base/${_safe(sourceId)}/${_safe(mangaId)}/${_safe(chapterId)}');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 删除整个翻译缓存目录。Web 上是 no-op（本类在 web 全程 no-op）。
  Future<void> clearAll() async {
    if (kIsWeb) return;
    final base = await _cachePath;
    final dir = Directory(base);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
