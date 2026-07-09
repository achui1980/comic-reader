import 'dart:convert';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/sources/manga_source.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// ComicK 数据源。
///
/// ComicK (comick.dev) 是一个国际漫画追踪/聚合平台,收录漫画(Manga)、
/// 韩漫(Manhwa)与国漫(Manhua)。界面本身为英文,但可按原产国筛选出中文
/// 国漫,并支持成人内容分级过滤。
///
/// 关键设计:
/// - API 域名 `api.comick.dev`,图片 CDN `meo.comick.pictures`,主站
///   `comick.dev`。主站与 API 位于 Cloudflare 之后,Dart/Dio 直连会被
///   TLS/JA3 指纹校验拦截(返回 403),因此原生端启用 [usesWebViewFetch] +
///   [cloudflareUrl],让请求从真实 WebKit 上下文发出。
/// - **语言筛选用 `country` 而非翻译语言**:ComicK 的 `lang` 参数在 search
///   端点无效(lang=zh 与 lang=en 返回完全相同结果),但 `country` 参数有效
///   (cn=中国国漫、jp=日漫、kr=韩漫)。因此「语言」过滤器映射到 country:
///   cn=中文(国漫)、en(用 country=gb+us 近似英语原作)、其他、全部。
/// - **成人过滤用 `content_rating`**:四级 safe/suggestive/erotica/
///   pornographic,默认只显示 safe(用户要求「默认显示安全」)。可开启
///   suggestive、erotica、pornographic。数组参数以重复 `content_rating=`
///   形式(无 `[]`)字面写进 URL 字符串,因为 dio/WebView 的 `_resolveUrl`
///   会把 queryParameters 里的 List 序列化成错误形式,只有标量才安全。
/// - **图片托管性质**:ComicK 主要是「追踪器」,很多章节(尤其官方授权
///   licensed 与外链 external 章节)不托管图片(md_images 为空),仅提供元
///   数据 + 外部搜索链接。parseChapter 从 chapter.md_images 取图,为空时该
///   章节无图(属网站性质,非实现 bug)。
class ComicKSource extends MangaSource {
  static const String sourceId = 'comick';

  static const String _apiBase = 'https://api.comick.dev';
  static const String _siteBase = 'https://comick.dev';
  static const String _imageBase = 'https://meo.comick.pictures';

  // MangaDex 回退:ComicK 很多章节自身不托管图片(md_images 为空),但若该
  // 章节带有 `mdid`(MangaDex 章节 UUID),说明其内容源自 MangaDex,可通过
  // MangaDex 的 at-home 服务器接口取回真实图片(经 nextExtra +
  // parseChapterImagePage 的二次请求机制)。
  static const String _mdApiBase = 'https://api.mangadex.org';
  static const String _mdSiteBase = 'https://mangadex.org';

  static const int _pageSize = 30;

  @override
  String get id => sourceId;

  @override
  String get name => 'ComicK';

  @override
  String get shortName => 'CK';

  @override
  String? get description => '国际漫画追踪平台,可筛选中文国漫,默认隐藏成人内容';

  @override
  double get score => 4.5;

  @override
  String? get href => _siteBase;

  @override
  bool get needsProxy => true;

  // ComicK 主站/API 位于 Cloudflare TLS/JA3 校验之后 —— 原生端走 WebView-fetch。
  @override
  bool get usesWebViewFetch => true;

  @override
  String? get cloudflareUrl => _siteBase;

  // 图片 CDN(meo.comick.pictures)返回 access-control-allow-origin:* 且不需
  // Cloudflare 校验,可直连。Web 端走 CORS 代理 + CachedNetworkImage 时会因
  // 响应被当作 String 处理而报 EncodingError,故让图片用 HTML <img> 直连 CDN。
  @override
  bool get webDirectImage => true;

  @override
  Map<String, String>? get defaultHeaders => const {
    'Accept': 'application/json',
  };

  // ---- Filters ----

  // 排序:映射 ComicK 的 sort 参数。
  static const FilterOption _orderFilter = FilterOption(
    name: 'order',
    label: '排序',
    defaultValue: 'follow',
    choices: [
      FilterChoice(label: '关注最多', value: 'follow'),
      FilterChoice(label: '浏览最多', value: 'view'),
      FilterChoice(label: '最新更新', value: 'uploaded'),
      FilterChoice(label: '评分最高', value: 'rating'),
    ],
  );

  // 语言 —— 实际映射到 country(原产国),因为 ComicK 的 lang 参数在 search
  // 端点无效。cn=中文国漫;en=英语原作(近似,用 gb);jp=日漫;kr=韩漫;
  // all=不限。
  static const FilterOption _languageFilter = FilterOption(
    name: 'language',
    label: '语言/地区',
    defaultValue: 'all',
    choices: [
      FilterChoice(label: '全部', value: 'all'),
      FilterChoice(label: '中文(国漫)', value: 'cn'),
      FilterChoice(label: '英语', value: 'gb'),
      FilterChoice(label: '日漫', value: 'jp'),
      FilterChoice(label: '韩漫', value: 'kr'),
    ],
  );

  // 成人过滤 —— 映射到 content_rating。默认「安全」(仅 safe)。
  static const FilterOption _ratingFilter = FilterOption(
    name: 'rating',
    label: '成人过滤',
    defaultValue: 'safe',
    choices: [
      // safe: 仅 safe;
      // suggestive: safe + suggestive(轻度暗示);
      // all: safe + suggestive + erotica + pornographic(含全部成人);
      // porn: 仅 erotica + pornographic(只看成人)。
      FilterChoice(label: '安全', value: 'safe'),
      FilterChoice(label: '含轻度', value: 'suggestive'),
      FilterChoice(label: '全部(含成人)', value: 'all'),
      FilterChoice(label: '只看成人', value: 'porn'),
    ],
  );

  @override
  List<FilterOption> get discoveryFilters => const [
    _orderFilter,
    _languageFilter,
    _ratingFilter,
  ];

  // 搜索复用过滤项,但排序对关键词搜索无意义,去掉 order。
  @override
  List<FilterOption> get searchFilters => const [
    _languageFilter,
    _ratingFilter,
  ];

  /// 把 rating filter 值映射成 content_rating= 参数串(重复键,无 `[]`)。
  static String _resolveContentRating(String? rating) {
    switch (rating) {
      case 'suggestive':
        return 'content_rating=safe&content_rating=suggestive';
      case 'all':
        return 'content_rating=safe&content_rating=suggestive'
            '&content_rating=erotica&content_rating=pornographic';
      case 'porn':
        return 'content_rating=erotica&content_rating=pornographic';
      default:
        return 'content_rating=safe';
    }
  }

  /// 把 language filter 值映射成 country= 参数串;'all' 返回空(不限)。
  static String _resolveCountry(String? language) {
    if (language == null || language == 'all' || language.isEmpty) return '';
    return 'country=$language';
  }

  // ---- Discovery ----

  @override
  FetchConfig prepareDiscoveryFetch(int page, Map<String, String> filters) {
    final order = filters['order'] ?? 'follow';
    final cr = _resolveContentRating(filters['rating']);
    final country = _resolveCountry(filters['language']);
    final countryClause = country.isEmpty ? '' : '$country&';

    final url =
        '$_apiBase/v1.0/search?$countryClause$cr'
        '&sort=$order';

    return FetchConfig(
      url: url,
      headers: defaultHeaders,
      queryParameters: <String, dynamic>{
        'page': '$page',
        'limit': '$_pageSize',
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
    final cr = _resolveContentRating(filters['rating']);
    final country = _resolveCountry(filters['language']);
    final countryClause = country.isEmpty ? '' : '$country&';

    final url = '$_apiBase/v1.0/search?$countryClause$cr';

    return FetchConfig(
      url: url,
      headers: defaultHeaders,
      queryParameters: <String, dynamic>{
        'title': keyword,
        'page': '$page',
        'limit': '$_pageSize',
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
    // mangaId 用 slug 或 hid 均可;详情接口 /comic/{id}。
    final url = '$_apiBase/comic/$mangaId';
    return FetchConfig(url: url, headers: defaultHeaders);
  }

  @override
  MangaDetail parseMangaInfo(dynamic response, String mangaId) {
    final map = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final comic = map['comic'] as Map<String, dynamic>? ?? const {};

    final title = _pickComicTitle(comic);
    final coverUrl = _buildCoverFromComic(comic);
    final author = _pickAuthor(map['authors']);
    final description = comic['desc'] as String?;
    final tags = _pickGenres(comic['md_comic_md_genres']);
    final status = _mapStatus(comic['status']);
    final lastChapter = _stringify(comic['last_chapter']);

    // hid 是后续章节列表请求所需的稳定标识,优先用它作为 chapterList 的入参。
    final hid = comic['hid'] as String? ?? mangaId;

    return MangaDetail(
      id: hid,
      sourceId: sourceId,
      title: title,
      coverUrl: coverUrl,
      description: description,
      author: author,
      tags: tags,
      status: status,
      latestChapter: lastChapter,
      headers: defaultHeaders,
    );
  }

  // ---- Chapter List ----

  // ComicK 的 /chapters 接口接受任意大 limit 并一次性返回全部章节
  // (响应仅含 total/limit/chapters,无 page/offset 字段,无法逐页翻),
  // 因此一次拉全,不做分页。
  static const int _chapterPageSize = 100000;

  @override
  FetchConfig? prepareChapterListFetch(String mangaId, int page) {
    // mangaId 此时是 comic 的 hid(见 parseMangaInfo)。章节列表接口
    // /comic/{hid}/chapters。不传 lang 返回所有语言章节。
    final url = '$_apiBase/comic/$mangaId/chapters';
    return FetchConfig(
      url: url,
      headers: defaultHeaders,
      queryParameters: <String, dynamic>{
        'page': '1',
        'limit': '$_chapterPageSize',
      },
    );
  }

  @override
  ChapterListResult parseChapterList(dynamic response, String mangaId) {
    final map = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final data =
        (map['chapters'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    final chapters = <ChapterItem>[];
    for (final item in data) {
      final hid = item['hid'] as String?;
      if (hid == null) continue;

      final baseTitle = _buildChapterTitle(item);

      // external 非空表示章节托管在外部站点,App 内看不到图,标记 [外链]。
      final external = item['external'];
      final isExternal = external != null &&
          (external is String ? external.isNotEmpty : true);
      final title = isExternal ? '[外链] $baseTitle' : baseTitle;

      chapters.add(
        ChapterItem(
          id: hid,
          mangaId: mangaId,
          title: title,
        ),
      );
    }

    // 一次性拉全部章节,无需分页。
    return ChapterListResult(chapters: chapters);
  }

  // ---- Chapter Images ----

  @override
  FetchConfig prepareChapterFetch(
    String mangaId,
    String chapterId,
    int page, {
    dynamic extra,
  }) {
    // chapterId 是章节 hid。/chapter/{hid} 返回 {chapter:{md_images:[...]}}。
    final url = '$_apiBase/chapter/$chapterId';
    return FetchConfig(url: url, headers: defaultHeaders);
  }

  @override
  ChapterResult parseChapter(
    dynamic response,
    String mangaId,
    String chapterId,
    int page,
  ) {
    final map = response is String
        ? jsonDecode(response) as Map<String, dynamic>
        : response as Map<String, dynamic>;
    final chapter = map['chapter'] as Map<String, dynamic>? ?? const {};
    final mdImages =
        (chapter['md_images'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];

    // ComicK 图片 CDN(meo.comick.pictures)要求带 Referer: https://comick.dev/。
    final imageHeaders = <String, String>{'Referer': '$_siteBase/'};

    final images = <ChapterImage>[];
    for (final img in mdImages) {
      final b2key = img['b2key'] as String?;
      if (b2key == null || b2key.isEmpty) continue;
      images.add(
        ChapterImage(
          url: '$_imageBase/$b2key',
          headers: imageHeaders,
        ),
      );
    }

    // ComicK 本质是漫画追踪/聚合器,大量章节不托管图片(md_images=[]),
    // 而是把内容托管在外部站点(external_type,如 mangasee)或仅提供跳转链接。
    if (images.isEmpty) {
      // 回退 1:若该章节带有 MangaDex 章节 UUID(mdid),说明内容源自
      // MangaDex,可通过 MangaDex at-home 接口取回真实图片。返回空图 +
      // nextExtra(MangaDex at-home URL);框架会二次请求该 URL 并交给
      // parseChapterImagePage 解析出图片(E-Hentai 式 indirection 流程)。
      final mdid = chapter['mdid'] as String?;
      if (mdid != null && mdid.isNotEmpty) {
        return ChapterResult(
          chapter: Chapter(
            id: chapterId,
            mangaId: mangaId,
            title: '',
            images: const [],
          ),
          nextExtra: jsonEncode(['$_mdApiBase/at-home/server/$mdid']),
        );
      }

      // 回退 2:既无本地图片也无 MangaDex 来源 —— 抛出带友好中文提示的异常。
      // ReaderBloc 的 onError 会捕获并在阅读器显示该提示,而不是留一个空白页。
      final externalType = chapter['external_type'] as String?;
      final external = chapter['external'];
      final externalUrl = map['externalUrl'];
      final site = (externalUrl is String && externalUrl.isNotEmpty)
          ? externalUrl
          : (external is String && external.isNotEmpty ? external : null);
      final buffer = StringBuffer('本章节 ComicK 未托管图片');
      if (externalType != null && externalType.isNotEmpty) {
        buffer.write('(内容托管在外部站点:$externalType)');
      }
      buffer.write(',需到外部站点阅读。');
      if (site != null) {
        buffer.write('\n$site');
      }
      throw Exception(buffer.toString());
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

  /// 解析 MangaDex at-home 服务器响应,取回真实图片。
  ///
  /// 当 [parseChapter] 检测到章节自身无图但带有 `mdid` 时,会返回一个
  /// `nextExtra` 列表,内含 MangaDex at-home URL。框架请求该 URL 后把响应
  /// 交给本方法。响应形如:
  /// `{baseUrl, chapter:{hash, data:[...], dataSaver:[...]}}`。
  /// 图片 URL 规则:`{baseUrl}/{data|data-saver}/{hash}/{filename}`。
  ///
  /// 返回非 null(哪怕空列表)以进入框架的「一页多图」模式,避免其回退到
  /// 逐页提取单个 `<img id="img">` 的默认逻辑。
  @override
  List<ChapterImage>? parseChapterImagePage(dynamic response) {
    final Map<String, dynamic> map;
    try {
      map = response is String
          ? jsonDecode(response) as Map<String, dynamic>
          : response as Map<String, dynamic>;
    } catch (_) {
      return const [];
    }

    final baseUrl = map['baseUrl'] as String?;
    final chapter = map['chapter'] as Map<String, dynamic>? ?? const {};
    final hash = chapter['hash'] as String?;
    if (baseUrl == null || hash == null) return const [];

    // 优先用 dataSaver 压缩图(缓存命中率更高、更少 404、加载更快),
    // 缺失时回退到全质量 data。
    final saverFiles =
        (chapter['dataSaver'] as List?)?.cast<String>() ?? const <String>[];
    final fullFiles =
        (chapter['data'] as List?)?.cast<String>() ?? const <String>[];
    final useSaver = saverFiles.isNotEmpty;
    final files = useSaver ? saverFiles : fullFiles;
    final pathSegment = useSaver ? 'data-saver' : 'data';

    // MangaDex@Home CDN(*.mangadex.network)要求带 Referer: https://mangadex.org/,
    // 否则返回 404。Web 端 ImageProxy.safeHeaders 会把 referer 转 X-Proxy-Referer,
    // cors_proxy.js 再还原为真实 Referer;Native 端 header 直接透传。
    final imageHeaders = <String, String>{'Referer': '$_mdSiteBase/'};

    final images = <ChapterImage>[];
    for (final file in files) {
      images.add(
        ChapterImage(
          url: '$baseUrl/$pathSegment/$hash/$file',
          headers: imageHeaders,
        ),
      );
    }
    return images;
  }

  // ---- Helpers ----

  List<MangaSummary> _parseMangaList(dynamic response) {
    final decoded = response is String ? jsonDecode(response) : response;
    // search 端点返回 JSON 数组。
    final list = decoded is List
        ? decoded.cast<Map<String, dynamic>>()
        : const <Map<String, dynamic>>[];

    final result = <MangaSummary>[];
    for (final item in list) {
      // 章节列表接口 /comic/{id}/chapters 只认 hid(不认 slug),
      // 而详情接口 slug/hid 均可,故统一用 hid 作为全局 id。
      final slug = item['slug'] as String?;
      final hid = item['hid'] as String?;
      final id = hid ?? slug;
      if (id == null) continue;

      result.add(
        MangaSummary(
          id: id,
          sourceId: sourceId,
          title: _pickListTitle(item),
          coverUrl: _buildCoverFromList(item),
          author: '',
          latestChapter: _stringify(item['last_chapter']),
          headers: defaultHeaders,
        ),
      );
    }
    return result;
  }

  /// 列表项标题:优先 md_titles 里的中文,否则 title。
  String _pickListTitle(Map<String, dynamic> item) {
    final localized = _pickLocalizedTitle(item['md_titles']);
    if (localized != null && localized.isNotEmpty) return localized;
    final title = item['title'] as String?;
    return (title != null && title.isNotEmpty) ? title : '未知标题';
  }

  /// 详情 comic 标题:优先 md_titles 里的中文,否则 title。
  String _pickComicTitle(Map<String, dynamic> comic) {
    final localized = _pickLocalizedTitle(comic['md_titles']);
    if (localized != null && localized.isNotEmpty) return localized;
    final title = comic['title'] as String?;
    return (title != null && title.isNotEmpty) ? title : '未知标题';
  }

  /// 从 md_titles: [{title, lang, is_default}] 中优先取中文(zh/zh-hk)。
  String? _pickLocalizedTitle(dynamic mdTitles) {
    if (mdTitles is! List) return null;
    final titles = mdTitles.cast<dynamic>();
    // 优先简/繁中文。
    for (final key in const ['zh', 'zh-hk']) {
      for (final t in titles) {
        if (t is Map && t['lang'] == key) {
          final title = t['title'] as String?;
          if (title != null && title.isNotEmpty) return title;
        }
      }
    }
    return null;
  }

  /// 列表项封面:md_covers[0].b2key。
  String _buildCoverFromList(Map<String, dynamic> item) {
    final covers = item['md_covers'] as List?;
    return _firstCoverUrl(covers);
  }

  /// 详情封面:comic.md_covers[0].b2key。
  String _buildCoverFromComic(Map<String, dynamic> comic) {
    final covers = comic['md_covers'] as List?;
    return _firstCoverUrl(covers);
  }

  String _firstCoverUrl(List? covers) {
    if (covers == null || covers.isEmpty) return '';
    final first = covers.first;
    if (first is Map) {
      final b2key = first['b2key'] as String?;
      if (b2key != null && b2key.isNotEmpty) {
        return '$_imageBase/$b2key';
      }
    }
    return '';
  }

  /// 作者:authors: [{name, slug}]。
  String _pickAuthor(dynamic authors) {
    if (authors is! List) return '';
    for (final a in authors) {
      if (a is Map) {
        final n = a['name'] as String?;
        if (n != null && n.isNotEmpty) return n;
      }
    }
    return '';
  }

  /// 体裁:md_comic_md_genres: [{md_genres:{name}}]。
  List<String> _pickGenres(dynamic genres) {
    if (genres is! List) return const [];
    final result = <String>[];
    for (final g in genres) {
      if (g is Map) {
        final md = g['md_genres'] as Map<String, dynamic>?;
        final name = md?['name'] as String?;
        if (name != null && name.isNotEmpty) result.add(name);
      }
    }
    return result;
  }

  /// ComicK status: 1=连载中, 2=已完结, 其他=未知。
  MangaStatus _mapStatus(dynamic status) {
    final s = status is num ? status.toInt() : null;
    switch (s) {
      case 1:
        return MangaStatus.ongoing;
      case 2:
        return MangaStatus.completed;
      default:
        return MangaStatus.unknown;
    }
  }

  String _buildChapterTitle(Map<String, dynamic> item) {
    final buffer = StringBuffer();
    final vol = _stringify(item['vol']);
    final chap = _stringify(item['chap']);
    final title = item['title'] as String?;
    final lang = item['lang'] as String?;

    if (vol != null && vol.isNotEmpty) {
      buffer.write('第$vol卷 ');
    }
    if (chap != null && chap.isNotEmpty) {
      buffer.write('第$chap话');
    } else {
      buffer.write('单话');
    }
    if (title != null && title.isNotEmpty) {
      buffer.write(' $title');
    }

    // 语言标记。
    switch (lang) {
      case 'zh':
        buffer.write(' [简]');
        break;
      case 'zh-hk':
        buffer.write(' [繁]');
        break;
      case null:
      case '':
        break;
      default:
        buffer.write(' [${lang.toUpperCase()}]');
    }

    // 汉化/扫描组:group_name: [...]。
    final groups = item['group_name'];
    if (groups is List && groups.isNotEmpty) {
      final first = groups.first;
      if (first is String && first.isNotEmpty) {
        buffer.write(' - $first');
      }
    }

    return buffer.toString().trim();
  }

  /// ComicK 的 chap/vol/last_chapter 可能是 String 或 num,统一转 String。
  String? _stringify(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num) {
      // 去掉整数的 .0 后缀。
      if (value == value.truncate()) return value.toInt().toString();
      return value.toString();
    }
    return value.toString();
  }
}
