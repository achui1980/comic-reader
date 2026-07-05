import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// MangaDex 数据源。
///
/// 仅列出提供简体中文(zh)与繁体中文(zh-hk)翻译的漫画/章节。
///
/// 关键设计:
/// - MangaDex 主站 (api.mangadex.org / mangadex.org) 位于 Cloudflare 的
///   TLS/JA3 指纹校验之后,Dart/Dio 直连会返回 400/403。因此原生端启用
///   [usesWebViewFetch] + [cloudflareUrl],让请求从真实 WebKit 上下文
///   发出,复用浏览器 TLS 指纹。
/// - 图片走 *.mangadex.network CDN,通常可直连 200,保持在直连路径,
///   不经过 WebView-fetch / impersonate。
/// - `availableTranslatedLanguage[]` / `translatedLanguage[]` / `includes[]`
///   / `contentRating[]` 等数组参数必须以字面 `[]=` 形式写进 URL 字符串。
///   因为 dio 与 WebView 的 `_resolveUrl` 都会把 queryParameters 里的
///   List 序列化成 `[zh, zh-hk]` 这种错误形式,只有标量才安全。
class MangaDexSource extends MangaSource {
  static const String sourceId = 'mangadex';

  static const String _apiBase = 'https://api.mangadex.org';
  static const String _siteBase = 'https://mangadex.org';
  static const String _uploadsBase = 'https://uploads.mangadex.org';

  /// 中文语言过滤 —— 发现/搜索选「仅中文」时带上。
  static const String _langFilter =
      'availableTranslatedLanguage[]=zh&availableTranslatedLanguage[]=zh-hk';

  /// 内容分级 —— 默认排除 pornographic,可通过 filter 打开。
  static const String _contentRatingSafe =
      'contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica';
  static const String _contentRatingAll =
      'contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic';

  /// 只显示限制级(仅 pornographic)。
  static const String _contentRatingPornOnly = 'contentRating[]=pornographic';

  static const int _pageSize = 24;

  /// 记录每部漫画是否含中文翻译(zh / zh-hk)。
  ///
  /// prepareChapterListFetch / parseChapterList 拿不到过滤器,也不能依赖
  /// 「进入路径」的全局状态(收藏、历史、深链都会绕过 discovery)。
  /// 因此改用漫画自身的元数据 availableTranslatedLanguages 作为无时序依赖
  /// 的信号:parseMangaInfo 与 _parseMangaList 时按 mangaId 缓存。
  ///
  /// 规则:含中文的漫画 → 章节列表只保留中文章节(体验干净);
  /// 不含中文的漫画(如日文原版,用户主动选「全部语言」才会看到)
  /// → 章节列表显示全部语言,否则会空列表。
  final Map<String, bool> _mangaHasChinese = <String, bool>{};

  static bool _hasChinese(dynamic availableLangs) {
    if (availableLangs is! List) return false;
    return availableLangs.contains('zh') || availableLangs.contains('zh-hk');
  }

  @override
  String get id => sourceId;

  @override
  String get name => 'MangaDex';

  @override
  String get shortName => 'MDx';

  @override
  String? get description => '国际漫画平台,仅展示简体/繁体中文翻译';

  @override
  double get score => 5.0;

  @override
  String? get href => _siteBase;

  @override
  bool get needsProxy => true;

  // MangaDex 位于 Cloudflare TLS/JA3 校验之后 —— 原生端走 WebView-fetch。
  @override
  bool get usesWebViewFetch => true;

  @override
  String? get cloudflareUrl => _siteBase;

  @override
  Map<String, String>? get defaultHeaders => const {
    'Accept': 'application/json',
  };

  @override
  List<FilterOption> get discoveryFilters => const [
    FilterOption(
      name: 'order',
      label: '排序',
      defaultValue: 'followedCount',
      choices: [
        FilterChoice(label: '关注最多', value: 'followedCount'),
        FilterChoice(label: '最新更新', value: 'latestUploadedChapter'),
        FilterChoice(label: '评分最高', value: 'rating'),
        FilterChoice(label: '创建时间', value: 'createdAt'),
      ],
    ),
    FilterOption(
      name: 'language',
      label: '语言',
      defaultValue: 'zh',
      choices: [
        // zh: 仅简体/繁体中文;all: 不限翻译语言,含日英等所有语言。
        FilterChoice(label: '仅中文', value: 'zh'),
        FilterChoice(label: '全部语言', value: 'all'),
      ],
    ),
    FilterOption(
      name: 'rating',
      label: '内容分级',
      defaultValue: 'safe',
      choices: [
        // safe: safe+suggestive+erotica(不含 pornographic);all: 追加 pornographic;
        // porn: 只显示 pornographic。
        FilterChoice(label: '不含限制级', value: 'safe'),
        FilterChoice(label: '全部(含限制级)', value: 'all'),
        FilterChoice(label: '只显示限制级', value: 'porn'),
      ],
    ),
  ];

  // 搜索复用发现页的过滤项(排序对搜索无意义,只保留语言与内容分级)。
  @override
  List<FilterOption> get searchFilters => const [
    FilterOption(
      name: 'language',
      label: '语言',
      defaultValue: 'zh',
      choices: [
        FilterChoice(label: '仅中文', value: 'zh'),
        FilterChoice(label: '全部语言', value: 'all'),
      ],
    ),
    FilterOption(
      name: 'rating',
      label: '内容分级',
      defaultValue: 'safe',
      choices: [
        FilterChoice(label: '不含限制级', value: 'safe'),
        FilterChoice(label: '全部(含限制级)', value: 'all'),
        FilterChoice(label: '只显示限制级', value: 'porn'),
      ],
    ),
  ];

  /// 把 rating filter 值映射成 contentRating[] 参数串。
  static String _resolveContentRating(String? rating) {
    switch (rating) {
      case 'all':
        return _contentRatingAll;
      case 'porn':
        return _contentRatingPornOnly;
      default:
        return _contentRatingSafe;
    }
  }

  /// 把 language filter 值映射成 availableTranslatedLanguage[] 参数串;
  /// 全部语言时返回 null(不加语言限制)。
  static String? _resolveDiscoveryLangFilter(String? language) {
    return language == 'all' ? null : _langFilter;
  }

  // ---- Discovery ----

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final order = filters['order'] ?? 'followedCount';
    final offset = (page - 1) * _pageSize;

    final cr = _resolveContentRating(filters['rating']);
    final lang = _resolveDiscoveryLangFilter(filters['language']);
    final langClause = lang == null ? '' : '$lang&';
    final url =
        '$_apiBase/manga?$langClause$cr'
        '&includes[]=cover_art&includes[]=author&includes[]=artist'
        '&order[$order]=desc';

    return FetchConfig(
      url: url,
      headers: defaultHeaders,
      queryParameters: <String, dynamic>{
        'limit': '$_pageSize',
        'offset': '$offset',
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(dynamic response) {
    return _parseMangaList(response);
  }

  // ---- Search ----

  @override
  FetchConfig prepareSearchFetch(
    String keyword,
    int page,
    Map<String, String> filters,
  ) {
    final offset = (page - 1) * _pageSize;
    final cr = _resolveContentRating(filters['rating']);
    final lang = _resolveDiscoveryLangFilter(filters['language']);
    final langClause = lang == null ? '' : '$lang&';
    final url =
        '$_apiBase/manga?$langClause$cr'
        '&includes[]=cover_art&includes[]=author&includes[]=artist'
        '&order[relevance]=desc';

    return FetchConfig(
      url: url,
      headers: defaultHeaders,
      queryParameters: <String, dynamic>{
        'title': keyword,
        'limit': '$_pageSize',
        'offset': '$offset',
      },
    );
  }

  @override
  List<MangaSummary> parseSearch(dynamic response) {
    return _parseMangaList(response);
  }

  // ---- Manga Info ----

  @override
  FetchConfig prepareMangaInfoFetch(String mangaId) {
    final url =
        '$_apiBase/manga/$mangaId'
        '?includes[]=cover_art&includes[]=author&includes[]=artist';
    return FetchConfig(url: url, headers: defaultHeaders);
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final map = response as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>;
    final attrs = data['attributes'] as Map<String, dynamic>? ?? const {};
    final relationships =
        (data['relationships'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];

    final title = _pickTitle(attrs['title'], attrs['altTitles']);
    final coverUrl = _buildCoverUrl(mangaId, relationships);
    final author = _pickAuthor(relationships);
    final description = _pickDescription(attrs['description']);

    // 缓存该漫画是否含中文翻译,供 parseChapterList 决定是否过滤章节语言。
    // 从收藏/历史直接进详情(未经列表)时,这里是唯一的信息来源。
    _mangaHasChinese[mangaId] = _hasChinese(
      attrs['availableTranslatedLanguages'],
    );
    final tags = _pickTags(attrs['tags']);
    final status = _mapStatus(attrs['status'] as String?);

    return MangaDetail(
      id: mangaId,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      headers: defaultHeaders,
    );
  }

  // ---- Chapter List (feed) ----

  static const int _feedPageSize = 100;

  /// 章节 feed 的中文语言过滤 —— 含中文的漫画在服务端就按 zh/zh-hk 过滤。
  static const String _feedLangFilter =
      'translatedLanguage[]=zh&translatedLanguage[]=zh-hk';

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    final offset = (page - 1) * _feedPageSize;

    // 含中文的漫画:在 feed 请求就带 translatedLanguage[] 过滤,让 API 只返回
    // 中文章节。否则像《一拳超人》这类有 1000+ 章、几十种语言的漫画,中文章节
    // 会被 order[volume/chapter]=desc 排到很后面的分页,首页(甚至前几页)全是
    // 外语章节 —— 经 parseChapterList 语言过滤后为空,detail_cubit 会因「空页」
    // 误判没有更多而中断翻页,导致明明有中文章节却显示空列表。
    //
    // 不含中文的漫画(纯外语,用户主动选「全部语言」才会看到)不加此过滤,
    // 否则会得到空章节列表;由 parseChapterList 显示全部语言。
    // 缺省(未缓存,如深链直入未经 mangaInfo)按含中文处理,与 parseChapterList
    // 的默认保持一致。
    final chineseOnly = _mangaHasChinese[mangaId] ?? true;
    final langClause = chineseOnly ? '$_feedLangFilter&' : '';

    final url =
        '$_apiBase/manga/$mangaId/feed'
        '?$langClause$_contentRatingAll'
        '&includes[]=scanlation_group'
        // 注意:includeExternalUrl 语义反直觉 ——
        //   =1 表示「只返回外链章节」,=0 表示「只返回非外链章节」,
        //   不传(unset)才表示「不过滤,外链+非外链全部返回」。
        // 所以这里刻意不传该参数,拿到全部章节;
        // 外链章节在 parseChapterList 里标记 [外链] 并用 externalUrl 打开。
        '&order[volume]=desc&order[chapter]=desc';

    return FetchConfig(
      url: url,
      headers: defaultHeaders,
      queryParameters: <String, dynamic>{
        'limit': '$_feedPageSize',
        'offset': '$offset',
      },
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final map = response as Map<String, dynamic>;
    final total = (map['total'] as num?)?.toInt() ?? 0;
    final offset = (map['offset'] as num?)?.toInt() ?? 0;
    final limit = (map['limit'] as num?)?.toInt() ?? _feedPageSize;
    final data =
        (map['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final chapters = <ChapterItem>[];
    for (final item in data) {
      final chapterId = item['id'] as String?;
      if (chapterId == null) continue;
      final attrs = item['attributes'] as Map<String, dynamic>? ?? const {};

      // isUnavailable 表示章节当前不可读,跳过。
      if (attrs['isUnavailable'] == true) continue;

      // 语言过滤:含中文的漫画只保留简/繁中文章节(体验干净);
      // 不含中文的漫画(纯外语,用户主动选「全部语言」看到的)显示全部,
      // 否则会得到空章节列表。是否含中文来自漫画元数据缓存,
      // 缺省(未缓存)按含中文处理,避免误放行非中文章节。
      final chineseOnly = _mangaHasChinese[mangaId] ?? true;
      final chapterLang = attrs['translatedLanguage'] as String?;
      if (chineseOnly && chapterLang != 'zh' && chapterLang != 'zh-hk') {
        continue;
      }

      final relationships =
          (item['relationships'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];

      // externalUrl 非空表示章节托管在外部站点(汉化组自建站),
      // 无法通过 at-home 在 App 内看图,但仍保留并标记为 [外链],
      // 点击时用浏览器打开该外部页面。
      final externalUrl = attrs['externalUrl'] as String?;
      final isExternal = externalUrl != null && externalUrl.isNotEmpty;
      final baseTitle = _buildChapterTitle(attrs, relationships);
      final title = isExternal ? '[外链] $baseTitle' : baseTitle;
      final href = isExternal ? externalUrl : '$_siteBase/chapter/$chapterId';

      chapters.add(
        ChapterItem(
          id: chapterId,
          mangaId: mangaId,
          title: title,
          href: href,
        ),
      );
    }

    final canLoadMore = offset + limit < total;
    return ChapterListResult(
      chapters: chapters,
      canLoadMore: canLoadMore,
      nextPage: canLoadMore ? (offset ~/ limit) + 2 : null,
    );
  }

  // ---- Chapter Images (at-home server) ----

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) {
    final url = '$_apiBase/at-home/server/$chapterId';
    return FetchConfig(url: url, headers: defaultHeaders);
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final map = response as Map<String, dynamic>;
    final baseUrl = map['baseUrl'] as String?;
    final chapter = map['chapter'] as Map<String, dynamic>? ?? const {};
    final hash = chapter['hash'] as String?;
    // 使用 dataSaver 压缩图(/data-saver/ 路径, .jpg):
    // MangaDex@Home CDN 对压缩图的缓存命中率更高、更少 404,加载也更快。
    // 若 dataSaver 缺失则回退到全质量 data。
    final saverFiles =
        (chapter['dataSaver'] as List?)?.cast<String>() ?? const <String>[];
    final fullFiles =
        (chapter['data'] as List?)?.cast<String>() ?? const <String>[];
    final useSaver = saverFiles.isNotEmpty;
    final files = useSaver ? saverFiles : fullFiles;
    final pathSegment = useSaver ? 'data-saver' : 'data';

    // MangaDex@Home CDN(*.mangadex.network)要求带 Referer: https://mangadex.org/
    // 请求头,否则返回 404。官方阅读器由浏览器自动带上,我们需显式指定。
    // Web 端:ImageProxy.safeHeaders 会把 referer 转为 X-Proxy-Referer,
    // cors_proxy.js 再还原为真实 Referer 转发给 CDN;Native 端 header 直接透传。
    final imageHeaders = <String, String>{'Referer': '$_siteBase/'};

    final images = <ChapterImage>[];
    if (baseUrl != null && hash != null) {
      for (final file in files) {
        images.add(
          ChapterImage(
            url: '$baseUrl/$pathSegment/$hash/$file',
            headers: imageHeaders,
          ),
        );
      }
    }

    return ChapterResult(
      chapter: Chapter(
        id: chapterId,
        mangaId: mangaId,
        title: '',
        images: images,
      ),
    );
  }

  @override
  String? getChapterWebUrl(String mangaId, String chapterId) {
    return '$_siteBase/chapter/$chapterId';
  }

  // ---- Helpers ----

  List<MangaSummary> _parseMangaList(dynamic response) {
    final map = response as Map<String, dynamic>;
    final data =
        (map['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final result = <MangaSummary>[];
    for (final item in data) {
      final mangaId = item['id'] as String?;
      if (mangaId == null) continue;
      final attrs = item['attributes'] as Map<String, dynamic>? ?? const {};
      final relationships =
          (item['relationships'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];

      // 缓存该漫画是否含中文翻译,供 parseChapterList 决定是否过滤章节语言。
      _mangaHasChinese[mangaId] = _hasChinese(
        attrs['availableTranslatedLanguages'],
      );

      result.add(
        MangaSummary(
          id: mangaId,
          sourceId: sourceId,
          title: _pickTitle(attrs['title'], attrs['altTitles']),
          coverUrl: _buildCoverUrl(mangaId, relationships),
          author: _pickAuthor(relationships),
          latestChapter: attrs['lastChapter'] as String?,
          headers: defaultHeaders,
        ),
      );
    }
    return result;
  }

  /// 从 title 本地化 map(优先 en/zh)+ altTitles 里挑一个可读标题。
  String _pickTitle(dynamic title, dynamic altTitles) {
    final fromTitle = _pickLocalized(title);
    if (fromTitle != null && fromTitle.isNotEmpty) return fromTitle;

    if (altTitles is List) {
      for (final alt in altTitles) {
        final picked = _pickLocalized(alt);
        if (picked != null && picked.isNotEmpty) return picked;
      }
    }
    return '未知标题';
  }

  /// 从形如 {'en':'...', 'zh':'...', 'ja-ro':'...'} 的本地化 map 中取值。
  /// 优先中文,其次英文,最后取第一个。
  String? _pickLocalized(dynamic value) {
    if (value is! Map) return null;
    final map = value.cast<String, dynamic>();
    for (final key in const ['zh', 'zh-hk', 'en']) {
      final v = map[key];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final v in map.values) {
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  String _buildCoverUrl(String mangaId, List<Map<String, dynamic>> rels) {
    for (final rel in rels) {
      if (rel['type'] == 'cover_art') {
        final attrs = rel['attributes'] as Map<String, dynamic>?;
        final fileName = attrs?['fileName'] as String?;
        if (fileName != null && fileName.isNotEmpty) {
          return '$_uploadsBase/covers/$mangaId/$fileName.512.jpg';
        }
      }
    }
    return '';
  }

  String _pickAuthor(List<Map<String, dynamic>> rels) {
    for (final rel in rels) {
      if (rel['type'] == 'author') {
        final attrs = rel['attributes'] as Map<String, dynamic>?;
        final n = attrs?['name'] as String?;
        if (n != null && n.isNotEmpty) return n;
      }
    }
    for (final rel in rels) {
      if (rel['type'] == 'artist') {
        final attrs = rel['attributes'] as Map<String, dynamic>?;
        final n = attrs?['name'] as String?;
        if (n != null && n.isNotEmpty) return n;
      }
    }
    return '';
  }

  String? _pickDescription(dynamic description) {
    return _pickLocalized(description);
  }

  List<String> _pickTags(dynamic tags) {
    if (tags is! List) return const [];
    final result = <String>[];
    for (final tag in tags) {
      if (tag is Map) {
        final attrs = tag['attributes'] as Map<String, dynamic>?;
        final name = _pickLocalized(attrs?['name']);
        if (name != null && name.isNotEmpty) result.add(name);
      }
    }
    return result;
  }

  MangaStatus _mapStatus(String? status) {
    switch (status) {
      case 'ongoing':
        return MangaStatus.ongoing;
      case 'completed':
        return MangaStatus.completed;
      default:
        return MangaStatus.unknown;
    }
  }

  String _buildChapterTitle(
    Map<String, dynamic> attrs,
    List<Map<String, dynamic>> rels,
  ) {
    final buffer = StringBuffer();
    final volume = attrs['volume'] as String?;
    final chapter = attrs['chapter'] as String?;
    final title = attrs['title'] as String?;
    final lang = attrs['translatedLanguage'] as String?;

    if (volume != null && volume.isNotEmpty) {
      buffer.write('第$volume卷 ');
    }
    if (chapter != null && chapter.isNotEmpty) {
      buffer.write('第$chapter话');
    } else {
      buffer.write('单话');
    }
    if (title != null && title.isNotEmpty) {
      buffer.write(' $title');
    }

    // 语言标记:中文区分简/繁,其他语言标出语言码,便于多语言时区分。
    switch (lang) {
      case 'zh':
        buffer.write(' [简]');
        break;
      case 'zh-hk':
        buffer.write(' [繁]');
        break;
      case null:
        break;
      case '':
        break;
      default:
        buffer.write(' [${lang.toUpperCase()}]');
    }

    // 汉化组。
    for (final rel in rels) {
      if (rel['type'] == 'scanlation_group') {
        final n = (rel['attributes'] as Map<String, dynamic>?)?['name']
            as String?;
        if (n != null && n.isNotEmpty) {
          buffer.write(' - $n');
          break;
        }
      }
    }

    return buffer.toString().trim();
  }
}
