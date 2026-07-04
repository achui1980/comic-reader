import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/manga.dart';
import 'package:comic_reader/domain/entities/chapter.dart';
import 'package:comic_reader/domain/entities/plugin_info.dart';

/// 咚漫漫画 (dongmanmanhua.cn) — LINE Webtoon 中国版。
///
/// 图片为明文 data-url，无加密、无 scramble、无二次请求。
/// mangaId 存 titleNo；chapterId 存 episode_no。
/// 详情/章节列表用 list 页；章节图片用 viewer 页。
/// list/viewer URL 中的 GENRE/slug 段只是装饰，可用任意占位。
class Dongmanmanhua extends MangaSource {
  static const String sourceId = 'dongmanmanhua';
  static const String _baseUrl = 'https://www.dongmanmanhua.cn';

  // 桌面 Chrome UA（部分企业代理会拦截移动 UA）
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  @override
  String get id => sourceId;

  @override
  String get name => '咚漫漫画';

  @override
  String get shortName => '咚漫';

  @override
  String? get description => 'LINE Webtoon 中国版 · 官方在线漫画';

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

  // --- Discovery ---

  /// 分类筛选（发现页）。
  /// genre 页 (/genre) 一次性渲染全部分类区块，每个区块由
  /// <h2 data-genre-seo="CODE">中文名</h2> + 紧随的 <ul class="card_lst"> 组成。
  /// 选中某分类时只解析对应区块。'' 表示首页推荐（全部）。
  @override
  List<FilterOption> get discoveryFilters => const [
        FilterOption(
          name: 'genre',
          label: '分类',
          defaultValue: '',
          choices: [
            FilterChoice(label: '推荐', value: ''),
            FilterChoice(label: '恋爱', value: 'LOVE'),
            FilterChoice(label: '少年', value: 'BOY'),
            FilterChoice(label: '古风', value: 'ANCIENTCHINESE'),
            FilterChoice(label: '奇幻', value: 'FANTASY'),
            FilterChoice(label: '搞笑', value: 'COMEDY'),
            FilterChoice(label: '校园', value: 'CAMPUS'),
            FilterChoice(label: '都市', value: 'METROPOLIS'),
            FilterChoice(label: '治愈', value: 'HEALING'),
            FilterChoice(label: '悬疑', value: 'SUSPENSE'),
            FilterChoice(label: '励志', value: 'INSPIRATIONAL'),
            FilterChoice(label: '影视化', value: 'FILMADAPTATION'),
            FilterChoice(label: '完结', value: 'TERMINATION'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final genre = filters['genre'] ?? '';
    _pendingGenre = genre;
    if (genre.isNotEmpty) {
      // 分类页一次性含该分类全部作品，无服务端分页。
      // page > 1 请求空 URL 由框架据空结果停止翻页（避免重复）。
      _pendingDiscoveryPage = page;
      return FetchConfig(
        url: '$_baseUrl/genre',
        headers: defaultHeaders,
      );
    }
    // 首页推荐列表（无分页；page > 1 返回空）
    _pendingDiscoveryPage = page;
    return FetchConfig(
      url: _baseUrl,
      headers: defaultHeaders,
    );
  }

  /// 记录最近一次发现请求选中的分类 code，供 parseDiscovery 使用
  /// （框架的 parseDiscovery 不接收 filters，源为单例故用实例字段传递）。
  String _pendingGenre = '';

  /// 记录最近一次发现请求的页码。genre/首页均无真分页，
  /// page > 1 时 parseDiscovery 返回空，框架据此停止继续翻页。
  int _pendingDiscoveryPage = 1;

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    // 无服务端分页：仅第 1 页返回结果，其余返回空以停止翻页并避免重复。
    if (_pendingDiscoveryPage > 1) return const [];
    final html = response as String;
    final document = html_parser.parse(html);
    final genre = _pendingGenre;
    if (genre.isNotEmpty) {
      return _parseGenreSection(document, genre);
    }
    return _parseTitleCards(document);
  }

  /// 从 genre 页解析指定分类区块的作品卡片。
  /// 每个分类为 <h2 data-genre-seo="CODE"> 后紧跟 <ul class="card_lst">。
  /// 提取该 h2 之后、下一个 h2[data-genre-seo] 之前的所有 li[data-title-no]。
  List<MangaSummary> _parseGenreSection(dynamic document, String genre) {
    final headers = document.querySelectorAll('h2[data-genre-seo]');
    dynamic target;
    for (final h in headers) {
      if ((h.attributes['data-genre-seo'] ?? '').toUpperCase() ==
          genre.toUpperCase()) {
        target = h;
        break;
      }
    }
    if (target == null) {
      // 未命中区块：回退解析整页（至少不空）
      return _parseTitleCards(document);
    }

    // 收集 target 之后、下一个 genre h2 之前的兄弟节点中的卡片。
    final results = <MangaSummary>[];
    final seen = <String>{};
    var node = target.nextElementSibling;
    while (node != null) {
      final isNextGenreHeader = node.localName == 'h2' &&
          node.attributes.containsKey('data-genre-seo');
      if (isNextGenreHeader) break;

      final cards = node.querySelectorAll('li[data-title-no]');
      for (final li in cards) {
        final titleNo = li.attributes['data-title-no'] ?? '';
        if (titleNo.isEmpty || seen.contains(titleNo)) continue;

        final titleEl = li.querySelector('.subj') ?? li.querySelector('p.subj');
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        seen.add(titleNo);

        final imgEl = li.querySelector('img');
        final coverUrl =
            imgEl?.attributes['src'] ?? imgEl?.attributes['data-url'] ?? '';

        final authorEl =
            li.querySelector('.author') ?? li.querySelector('p.author');
        final author = authorEl?.text.trim() ?? '';

        results.add(MangaSummary(
          id: titleNo,
          sourceId: sourceId,
          title: title,
          coverUrl: coverUrl,
          author: author,
          headers: defaultHeaders,
        ));
      }
      node = node.nextElementSibling;
    }
    return results;
  }

  /// 解析含 title_no 的推荐/首页卡片。
  /// 卡片形如 <a href=".../list?title_no={N}"> 内含 img + p.subj + p.author。
  List<MangaSummary> _parseTitleCards(dynamic document) {
    final cards = document.querySelectorAll('a[href*="title_no="]');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final card in cards) {
      final href = card.attributes['href'] ?? '';
      final match = RegExp(r'title_no=(\d+)').firstMatch(href);
      if (match == null) continue;

      final titleNo = match.group(1)!;
      if (seen.contains(titleNo)) continue;

      final titleEl = card.querySelector('.subj') ??
          card.querySelector('p.subj') ??
          card.querySelector('.title');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      seen.add(titleNo);

      final imgEl = card.querySelector('img');
      final coverUrl =
          imgEl?.attributes['src'] ?? imgEl?.attributes['data-url'] ?? '';

      final authorEl = card.querySelector('.author') ??
          card.querySelector('p.author');
      final author = authorEl?.text.trim() ?? '';

      results.add(MangaSummary(
        id: titleNo,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
        headers: defaultHeaders,
      ));
    }

    return results;
  }

  // --- Search ---

  @override
  FetchConfig prepareSearchFetch(
      String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: '$_baseUrl/search',
      queryParameters: {'keyword': keyword},
      headers: defaultHeaders,
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    final html = response as String;
    final document = html_parser.parse(html);

    // 搜索结果卡片: ul.card_lst > li[data-title-no]
    final items = document.querySelectorAll('ul.card_lst li[data-title-no]');
    final results = <MangaSummary>[];
    final seen = <String>{};

    for (final li in items) {
      final titleNo = li.attributes['data-title-no'] ?? '';
      if (titleNo.isEmpty || seen.contains(titleNo)) continue;

      final titleEl = li.querySelector('.subj') ?? li.querySelector('p.subj');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;

      seen.add(titleNo);

      final imgEl = li.querySelector('img');
      final coverUrl =
          imgEl?.attributes['src'] ?? imgEl?.attributes['data-url'] ?? '';

      final authorEl =
          li.querySelector('.author') ?? li.querySelector('p.author');
      final author = authorEl?.text.trim() ?? '';

      results.add(MangaSummary(
        id: titleNo,
        sourceId: sourceId,
        title: title,
        coverUrl: coverUrl,
        author: author,
        headers: defaultHeaders,
      ));
    }

    // 若 ul.card_lst 结构未命中，回退到通用 title_no 卡片解析
    if (results.isEmpty) {
      return _parseTitleCards(document);
    }
    return results;
  }

  // --- Manga Info ---

  /// 缓存 titleNo -> '{GENRE}/{slug}' 规范路径。
  /// 因为详情/章节列表页会 301 到规范路径并丢弃 page 参数，分页必须直接请求规范路径。
  /// 源为单例，parseMangaInfo/parseChapterList 解析到 canonical 后写入此缓存，
  /// prepareChapterListFetch 读取以构建正确的分页 URL。
  final Map<String, String> _pathCache = {};

  /// mangaId 可能编码为 '{titleNo}::{GENRE}/{slug}'（用于分页保留真实路径）。
  /// 返回 titleNo。
  String _titleNoOf(String mangaId) {
    final i = mangaId.indexOf('::');
    return i >= 0 ? mangaId.substring(0, i) : mangaId;
  }

  /// 返回编码在 mangaId 中的 '{GENRE}/{slug}' 路径，其次查缓存，未知则 null。
  String? _pathOf(String mangaId) {
    final i = mangaId.indexOf('::');
    if (i >= 0) return mangaId.substring(i + 2);
    return _pathCache[mangaId];
  }

  /// 构建 list 页 URL。已知真实 genre/slug 时用规范路径（分页时 page 参数才不会被 301 丢弃）；
  /// 否则用 /comic/{titleNo}/list（服务器 301 重定向到规范路径，仅第 1 页可靠）。
  String _listUrl(String mangaId) {
    final path = _pathOf(mangaId);
    if (path != null && path.isNotEmpty) {
      return '$_baseUrl/$path/list';
    }
    return '$_baseUrl/comic/${_titleNoOf(mangaId)}/list';
  }

  /// 从页面 <link rel="canonical"> 提取 '{GENRE}/{slug}'，失败返回 null。
  String? _canonicalPath(dynamic document) {
    final el = document.querySelector('link[rel="canonical"]');
    final href = el?.attributes['href'] ?? '';
    final m = RegExp(r'dongmanmanhua\.cn/([A-Za-z_]+/[^/?]+)/list')
        .firstMatch(href);
    return m?.group(1);
  }

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    final titleNo = _titleNoOf(mangaId);
    return FetchConfig(
      url: _listUrl(mangaId),
      queryParameters: {'title_no': titleNo},
      headers: defaultHeaders,
    );
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final html = response as String;
    final document = html_parser.parse(html);

    final titleNo = _titleNoOf(mangaId);
    // 提取规范 genre/slug，缓存并编码进 id 以便章节列表分页保留真实路径
    final canonical = _canonicalPath(document);
    if (canonical != null) {
      _pathCache[titleNo] = canonical;
    }
    final encodedId =
        canonical != null ? '$titleNo::$canonical' : titleNo;

    // 标题
    String title = document.querySelector('div.detail_header h1.subj')?.text
            .trim() ??
        document.querySelector('h1.subj')?.text.trim() ??
        '';
    if (title.isEmpty) {
      // 回退到 <title> 的 '_' 前段
      final pageTitle = document.querySelector('title')?.text ?? '';
      title = pageTitle.split('_').first.trim();
    }

    // 封面
    final coverEl = document.querySelector('div.detail_header span.thmb img') ??
        document.querySelector('div.detail_header img');
    final coverUrl = coverEl?.attributes['src'] ??
        coverEl?.attributes['data-url'] ??
        '';

    // 分类/tags: h2.genre 文本空格分隔
    final genreEl = document.querySelector('div.detail_header h2.genre') ??
        document.querySelector('h2.genre');
    final tags = <String>[];
    if (genreEl != null) {
      for (final t in genreEl.text.trim().split(RegExp(r'\s+'))) {
        if (t.isNotEmpty) tags.add(t);
      }
    }

    // 作者: span.author 自身文本（去除内嵌 <a>'作家信息'）
    String author = '';
    final authorEl = document.querySelector('div.detail_header span.author') ??
        document.querySelector('span.author');
    if (authorEl != null) {
      author = authorEl.text.trim();
      for (final a in authorEl.querySelectorAll('a')) {
        author = author.replaceAll(a.text.trim(), '');
      }
      author = author.trim();
    }

    // 简介
    final description =
        document.querySelector('p.summary')?.text.trim();

    // 状态: 页面无中文字，读 data-sc-event-parameter 中 serial_status
    MangaStatus status = MangaStatus.unknown;
    final statusMatch =
        RegExp(r'serial_status:(\w+)').firstMatch(html);
    if (statusMatch != null) {
      final s = statusMatch.group(1)!.toUpperCase();
      if (s.contains('COMPLET') || s.contains('END') || s.contains('FINISH')) {
        status = MangaStatus.completed;
      } else if (s.contains('SERIES') || s.contains('SERIAL')) {
        status = MangaStatus.ongoing;
      }
    }

    // 章节列表由 getChapterList 分页拉取（详情页只内嵌首页 10 话，会导致
    // detail_cubit 认为无更多章节）。故这里返回空 chapters，强制走分页路径。
    return MangaDetail(
      id: encodedId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      chapters: const [],
      headers: defaultHeaders,
    );
  }

  // --- Chapter List ---

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    return FetchConfig(
      url: _listUrl(mangaId),
      queryParameters: {
        'title_no': _titleNoOf(mangaId),
        'page': page.toString(),
      },
      headers: defaultHeaders,
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final html = response as String;
    final document = html_parser.parse(html);

    // 缓存规范 genre/slug 路径（供后续分页请求构建正确 URL）
    final canonical = _canonicalPath(document);
    if (canonical != null) {
      _pathCache[_titleNoOf(mangaId)] = canonical;
    }

    final chapters = _parseChapterItems(document, mangaId);

    // 分页: div.paginate 内 a[href*='page='] 最大 page 号
    int maxPage = 1;
    int currentPage = 1;
    final paginate = document.querySelector('div.paginate');
    if (paginate != null) {
      // 当前页为 <span class='on'>N</span>
      final onEl = paginate.querySelector('.on') ??
          paginate.querySelector('span.on');
      final curVal = int.tryParse(onEl?.text.trim() ?? '');
      if (curVal != null) currentPage = curVal;

      for (final a in paginate.querySelectorAll('a[href*="page="]')) {
        final m = RegExp(r'page=(\d+)').firstMatch(a.attributes['href'] ?? '');
        if (m != null) {
          final p = int.tryParse(m.group(1)!) ?? 1;
          if (p > maxPage) maxPage = p;
        }
      }
    }
    if (currentPage > maxPage) maxPage = currentPage;

    final canLoadMore = chapters.isNotEmpty && currentPage < maxPage;

    return ChapterListResult(
      chapters: chapters,
      canLoadMore: canLoadMore,
      nextPage: canLoadMore ? currentPage + 1 : null,
    );
  }

  /// 解析章节列表: ul#_listUl > li[data-episode-no]
  List<ChapterItem> _parseChapterItems(dynamic document, String mangaId) {
    final items = document.querySelectorAll('ul#_listUl li[data-episode-no]');
    final chapters = <ChapterItem>[];
    final seen = <String>{};

    for (final li in items) {
      var episodeNo = li.attributes['data-episode-no'] ?? '';
      if (episodeNo.isEmpty) {
        // 从内部 a[href] 提 episode_no
        final a = li.querySelector('a[href*="episode_no="]');
        final m = RegExp(r'episode_no=(\d+)')
            .firstMatch(a?.attributes['href'] ?? '');
        episodeNo = m?.group(1) ?? '';
      }
      if (episodeNo.isEmpty || seen.contains(episodeNo)) continue;
      seen.add(episodeNo);

      final subjEl = li.querySelector('span.subj span') ??
          li.querySelector('.subj span') ??
          li.querySelector('.subj');
      final chapterTitle =
          subjEl?.text.trim() ?? '第 $episodeNo 话';

      chapters.add(ChapterItem(
        id: episodeNo,
        mangaId: mangaId,
        title: chapterTitle.isEmpty ? '第 $episodeNo 话' : chapterTitle,
      ));
    }

    return chapters;
  }

  // --- Chapter Content ---

  @override
  FetchConfig prepareChapterFetch(String mangaId, String chapterId, int page,
      {dynamic extra}) {
    final titleNo = _titleNoOf(mangaId);
    return FetchConfig(
      url: '$_baseUrl/comic/$titleNo/ep/viewer',
      queryParameters: {
        'title_no': titleNo,
        'episode_no': chapterId,
      },
      headers: defaultHeaders,
    );
  }

  @override
  ChapterResult parseChapter(
      dynamic response, String mangaId, String chapterId, int page) {
    final html = response as String;
    final document = html_parser.parse(html);

    // 章节标题从 <title> '... - {episode_no} | {漫画名}'
    String title = '第 $chapterId 话';
    final pageTitle = document.querySelector('title')?.text ?? '';
    if (pageTitle.contains(' - ')) {
      final part = pageTitle.split(' - ').first.trim();
      if (part.isNotEmpty) title = part;
    }

    // 图片在 #_imageList img._images 的 data-url
    final imgElements =
        document.querySelectorAll('#_imageList img._images');
    final images = <ChapterImage>[];

    for (final img in imgElements) {
      final url = img.attributes['data-url'] ?? img.attributes['src'];
      if (url == null || url.isEmpty) continue;
      if (url.contains('bg_transparency')) continue; // 跳过占位图
      images.add(ChapterImage(url: url, headers: defaultHeaders));
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: title,
        images: images,
        headers: defaultHeaders,
      ),
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    final titleNo = _titleNoOf(mangaId);
    return '$_baseUrl/comic/$titleNo/ep/viewer?title_no=$titleNo&episode_no=$chapterId';
  }
}
