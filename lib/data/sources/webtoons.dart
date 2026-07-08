import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';

/// Webtoons (www.webtoons.com/zh-hant) — LINE Webtoon 繁體中文站。
///
/// 与咚漫漫画 (dongmanmanhua) 同一套模板，复用其架构：
/// - _pathCache 缓存 titleNo -> '{genre-slug}/{title-slug}' 规范路径。
/// - mangaId 编码为 '{titleNo}::{path}' 以在分页/viewer 保留真实路径。
/// - 章节列表强制走分页接口（详情页只内嵌部分章节）。
///
/// 与 dongmanmanhua 的关键差异：
/// - 详情/章节列表页的通用占位路径 301 会丢弃 page 参数（同 dongmanmanhua 坑）。
/// - viewer 的通用占位路径返回 500（dongmanmanhua 可用），故 viewer 必须用
///   规范路径。正常导航流程（详情页先加载章节列表）保证 _pathCache 已填充。
/// - 图片 CDN 需 Referer 头，否则 403。
class WebtoonsSource extends MangaSource {
  static const String sourceId = 'webtoons';
  static const String _baseUrl = 'https://www.webtoons.com/zh-hant';

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => 'Webtoons';

  @override
  String get shortName => 'Webtoons';

  @override
  String? get description => 'webtoons.com (繁體中文)';

  @override
  double get score => 4.5;

  @override
  String? get href => _baseUrl;

  @override
  bool get isAdult => false;

  @override
  bool get needsProxy => false;

  @override
  bool get needsCloudflare => false;

  @override
  String? get userAgent => _userAgent;

  @override
  Map<String, String>? get defaultHeaders => {
        'User-Agent': _userAgent,
        'Referer': '$_baseUrl/',
      };
}
