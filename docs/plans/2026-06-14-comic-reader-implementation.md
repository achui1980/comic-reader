# comic-reader Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a cross-platform (iOS/Android/Web/Desktop) manga reader in Flutter with an immersive reading experience and a plugin system ported from MangaReader's 14 source plugins.

**Architecture:** Clean Architecture with 4 layers: Presentation (Bloc/Cubit + Flutter Widgets), Domain (Entities + Use Cases + Repository Interfaces), Data (Plugin System + Isar DB + Dio HTTP), Infrastructure (Platform Channels). The reader is a full-screen immersive widget with horizontal page-flip, vertical webtoon scroll, and seamless chapter transitions.

**Tech Stack:** Flutter 3.x, Dart, flutter_bloc, isar, dio, go_router, cached_network_image, extended_image, html (parsing), pointycastle/encrypt (crypto), get_it (DI)

---

## Phase 1: Project Scaffold & Core Infrastructure

### Task 1: Create Flutter Project

**Files:**
- Create: `comic-reader/` (Flutter project root)

**Step 1: Generate Flutter project**

```bash
cd /Users/portz/js/comic
# Remove the empty git-only directory first
rm -rf comic-reader/.git
rm -rf comic-reader
flutter create --org com.comicreader --project-name comic_reader --platforms ios,android,web,macos comic-reader
```

**Step 2: Verify project builds**

```bash
cd /Users/portz/js/comic/comic-reader
flutter pub get
flutter analyze
```

Expected: No errors

**Step 3: Initialize git**

```bash
cd /Users/portz/js/comic/comic-reader
git init
git add .
git commit -m "chore: initial Flutter project scaffold"
```

---

### Task 2: Add Core Dependencies

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Update pubspec.yaml with all required dependencies**

Replace the `dependencies` and `dev_dependencies` sections in `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  # State management
  flutter_bloc: ^8.1.6
  equatable: ^2.0.5
  # Navigation
  go_router: ^14.2.0
  # Network
  dio: ^5.4.0
  dio_cookie_manager: ^3.1.0
  cookie_jar: ^4.0.8
  # HTML parsing
  html: ^0.15.4
  # Local storage
  isar: ^3.1.0+1
  isar_flutter_libs: ^3.1.0+1
  path_provider: ^2.1.2
  # Image
  cached_network_image: ^3.3.1
  extended_image: ^8.2.1
  # Crypto
  pointycastle: ^3.7.4
  encrypt: ^5.0.3
  # DI
  get_it: ^7.6.7
  injectable: ^2.3.5
  # UI
  flutter_screenutil: ^5.9.0
  shimmer: ^3.0.0
  # Utils
  collection: ^1.18.0
  intl: ^0.19.0
  logging: ^1.2.0
  uuid: ^4.3.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.8
  isar_generator: ^3.1.0+1
  injectable_generator: ^2.4.2
  bloc_test: ^9.1.7
  mocktail: ^1.0.3
```

**Step 2: Run pub get**

```bash
cd /Users/portz/js/comic/comic-reader
flutter pub get
```

Expected: Dependencies resolve without errors

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add core dependencies"
```

---

### Task 3: Set Up Directory Structure

**Files:**
- Create: `lib/` directory tree

**Step 1: Create full directory structure**

```bash
cd /Users/portz/js/comic/comic-reader
mkdir -p lib/app/theme
mkdir -p lib/app/di
mkdir -p lib/app/router
mkdir -p lib/core/models
mkdir -p lib/core/errors
mkdir -p lib/core/utils
mkdir -p lib/core/constants
mkdir -p lib/data/sources
mkdir -p lib/data/repositories
mkdir -p lib/data/local/schemas
mkdir -p lib/data/local/dao
mkdir -p lib/data/remote
mkdir -p lib/domain/entities
mkdir -p lib/domain/repositories
mkdir -p lib/domain/usecases
mkdir -p lib/presentation/reader/bloc
mkdir -p lib/presentation/reader/widgets
mkdir -p lib/presentation/home/bloc
mkdir -p lib/presentation/home/widgets
mkdir -p lib/presentation/discovery/bloc
mkdir -p lib/presentation/discovery/widgets
mkdir -p lib/presentation/detail/bloc
mkdir -p lib/presentation/detail/widgets
mkdir -p lib/presentation/search/bloc
mkdir -p lib/presentation/search/widgets
mkdir -p lib/presentation/settings/bloc
mkdir -p lib/presentation/settings/widgets
mkdir -p lib/presentation/widgets
mkdir -p test/data/sources
mkdir -p test/domain/usecases
mkdir -p test/presentation
```

**Step 2: Commit**

```bash
git add .
git commit -m "chore: create directory structure"
```

---

### Task 4: Core Domain Entities

**Files:**
- Create: `lib/domain/entities/manga.dart`
- Create: `lib/domain/entities/chapter.dart`
- Create: `lib/domain/entities/plugin_info.dart`
- Create: `lib/domain/entities/entities.dart` (barrel)

**Step 1: Write manga entity**

```dart
// lib/domain/entities/manga.dart
import 'package:equatable/equatable.dart';

enum MangaStatus { unknown, serial, ended }

class MangaSummary extends Equatable {
  final String hash;
  final String sourceId;
  final String sourceName;
  final String mangaId;
  final String title;
  final String bookCover;
  final String? author;
  final String? updateTime;
  final List<String> tags;
  final String? href;
  final Map<String, String>? headers;

  const MangaSummary({
    required this.hash,
    required this.sourceId,
    required this.sourceName,
    required this.mangaId,
    required this.title,
    required this.bookCover,
    this.author,
    this.updateTime,
    this.tags = const [],
    this.href,
    this.headers,
  });

  @override
  List<Object?> get props => [hash, sourceId, mangaId];
}

class MangaDetail extends Equatable {
  final String hash;
  final String sourceId;
  final String sourceName;
  final String mangaId;
  final String title;
  final String bookCover;
  final String? infoCover;
  final List<String> authors;
  final List<String> tags;
  final MangaStatus status;
  final String? updateTime;
  final String? latest;
  final String? href;
  final String? description;

  const MangaDetail({
    required this.hash,
    required this.sourceId,
    required this.sourceName,
    required this.mangaId,
    required this.title,
    required this.bookCover,
    this.infoCover,
    this.authors = const [],
    this.tags = const [],
    this.status = MangaStatus.unknown,
    this.updateTime,
    this.latest,
    this.href,
    this.description,
  });

  @override
  List<Object?> get props => [hash, sourceId, mangaId];
}
```

**Step 2: Write chapter entity**

```dart
// lib/domain/entities/chapter.dart
import 'package:equatable/equatable.dart';

enum ScrambleType { none, jmc, rm5 }

class ChapterItem extends Equatable {
  final String hash;
  final String mangaId;
  final String chapterId;
  final String title;
  final String? href;

  const ChapterItem({
    required this.hash,
    required this.mangaId,
    required this.chapterId,
    required this.title,
    this.href,
  });

  @override
  List<Object?> get props => [hash];
}

class ChapterImage extends Equatable {
  final String uri;
  final ScrambleType scrambleType;
  final Map<String, String>? headers;

  const ChapterImage({
    required this.uri,
    this.scrambleType = ScrambleType.none,
    this.headers,
  });

  @override
  List<Object?> get props => [uri];
}

class Chapter extends Equatable {
  final String hash;
  final String mangaId;
  final String chapterId;
  final String title;
  final String? name;
  final List<ChapterImage> images;
  final Map<String, String>? headers;

  const Chapter({
    required this.hash,
    required this.mangaId,
    required this.chapterId,
    required this.title,
    this.name,
    required this.images,
    this.headers,
  });

  @override
  List<Object?> get props => [hash];
}

class ChapterListResult {
  final List<ChapterItem> chapters;
  final bool canLoadMore;
  final int? nextPage;

  const ChapterListResult({
    required this.chapters,
    this.canLoadMore = false,
    this.nextPage,
  });
}

class ChapterResult {
  final Chapter chapter;
  final bool canLoadMore;
  final int? nextPage;
  final Map<String, dynamic>? nextExtra;

  const ChapterResult({
    required this.chapter,
    this.canLoadMore = false,
    this.nextPage,
    this.nextExtra,
  });
}
```

**Step 3: Write plugin info entity**

```dart
// lib/domain/entities/plugin_info.dart
import 'package:equatable/equatable.dart';

class FilterOption extends Equatable {
  final String name;
  final String defaultValue;
  final List<FilterChoice> choices;

  const FilterOption({
    required this.name,
    this.defaultValue = r'$$DEFAULT$$',
    required this.choices,
  });

  @override
  List<Object?> get props => [name];
}

class FilterChoice extends Equatable {
  final String label;
  final String value;

  const FilterChoice({required this.label, required this.value});

  @override
  List<Object?> get props => [value];
}

class PluginInfo extends Equatable {
  final String id;
  final String name;
  final String shortName;
  final String? description;
  final int score;
  final String href;
  final bool disabled;
  final List<FilterOption> discoveryFilters;
  final List<FilterOption> searchFilters;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.shortName,
    this.description,
    required this.score,
    required this.href,
    this.disabled = false,
    this.discoveryFilters = const [],
    this.searchFilters = const [],
  });

  @override
  List<Object?> get props => [id];
}
```

**Step 4: Write barrel export**

```dart
// lib/domain/entities/entities.dart
export 'manga.dart';
export 'chapter.dart';
export 'plugin_info.dart';
```

**Step 5: Commit**

```bash
git add lib/domain/entities/
git commit -m "feat: add core domain entities (Manga, Chapter, PluginInfo)"
```

---

### Task 5: Plugin System Abstract Base

**Files:**
- Create: `lib/data/sources/manga_source.dart`
- Create: `lib/data/sources/source_registry.dart`
- Create: `lib/core/utils/hash_utils.dart`
- Create: `lib/core/models/fetch_config.dart`

**Step 1: Write FetchConfig model**

```dart
// lib/core/models/fetch_config.dart

enum HttpMethod { get, post }

class FetchConfig {
  final String url;
  final HttpMethod method;
  final Map<String, dynamic>? queryParams;
  final dynamic body;
  final Map<String, String>? headers;
  final int? timeout;

  const FetchConfig({
    required this.url,
    this.method = HttpMethod.get,
    this.queryParams,
    this.body,
    this.headers,
    this.timeout,
  });
}
```

**Step 2: Write hash utility**

```dart
// lib/core/utils/hash_utils.dart

/// Combines plugin id, mangaId, and optional chapterId into a hash string.
/// Format: "PLUGIN_ID&mangaId" or "PLUGIN_ID&mangaId&chapterId"
String combineHash(String pluginId, String mangaId, [String? chapterId]) {
  if (chapterId == null || chapterId.isEmpty) {
    return '$pluginId&$mangaId';
  }
  return '$pluginId&$mangaId&$chapterId';
}

/// Splits a hash string back into (pluginId, mangaId, chapterId).
(String pluginId, String mangaId, String chapterId) splitHash(String hash) {
  final parts = hash.split('&');
  return (
    parts.isNotEmpty ? parts[0] : '',
    parts.length > 1 ? parts[1] : '',
    parts.length > 2 ? parts[2] : '',
  );
}
```

**Step 3: Write MangaSource abstract class**

```dart
// lib/data/sources/manga_source.dart
import 'package:dio/dio.dart';
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Abstract base class for all manga source plugins.
/// Each plugin must implement request building (prepare*) and response parsing (parse*).
abstract class MangaSource {
  /// Unique plugin identifier (e.g., 'COPY', 'MHGM', 'JMC')
  String get id;

  /// Display name (e.g., '拷贝漫画')
  String get name;

  /// Short name for compact UI
  String get shortName;

  /// Description text
  String get description;

  /// Quality score (0-5)
  int get score;

  /// Base website URL
  String get baseUrl;

  /// Custom User-Agent string
  String? get userAgent => null;

  /// Default HTTP headers for all requests from this source
  Map<String, String> get defaultHeaders => {};

  /// Whether this plugin is disabled (hidden from user)
  bool get disabled => false;

  /// Delay between batch requests in milliseconds
  int get batchDelay => 1500;

  /// Filter options for discovery page
  List<FilterOption> get discoveryFilters => [];

  /// Filter options for search page
  List<FilterOption> get searchFilters => [];

  /// JavaScript to inject in WebView for auth token extraction
  String? get injectedJavaScript => null;

  /// Build the PluginInfo metadata object
  PluginInfo get info => PluginInfo(
        id: id,
        name: name,
        shortName: shortName,
        description: description,
        score: score,
        href: baseUrl,
        disabled: disabled,
        discoveryFilters: discoveryFilters,
        searchFilters: searchFilters,
      );

  // --- Request builders ---

  FetchConfig prepareDiscovery(int page, Map<String, String> filters);
  FetchConfig prepareSearch(String keyword, int page, Map<String, String> filters);
  FetchConfig prepareMangaInfo(String mangaId);
  FetchConfig? prepareChapterList(String mangaId, int page);
  FetchConfig prepareChapter(String mangaId, String chapterId, int page, Map<String, dynamic> extra);

  // --- Response parsers ---

  List<MangaSummary> parseDiscovery(Response response);
  List<MangaSummary> parseSearch(Response response);
  MangaDetail parseMangaInfo(Response response, String mangaId);
  ChapterListResult parseChapterList(Response response, String mangaId);
  ChapterResult parseChapter(Response response, String mangaId, String chapterId, int page);

  // --- Optional overrides ---

  /// Called with auth data from WebView
  void syncExtraData(Map<String, dynamic> data) {}

  /// Check if response indicates Cloudflare protection
  bool isCloudflareBlocked(String html) {
    return html.contains('<title>Just a moment...</title>');
  }
}
```

**Step 4: Write source registry**

```dart
// lib/data/sources/source_registry.dart
import 'manga_source.dart';

class SourceRegistry {
  final Map<String, MangaSource> _sources = {};

  void register(MangaSource source) {
    _sources[source.id] = source;
  }

  MangaSource? get(String id) => _sources[id];

  List<MangaSource> get all => _sources.values.toList();

  List<MangaSource> get enabled =>
      _sources.values.where((s) => !s.disabled).toList();

  MangaSource get defaultSource => enabled.first;
}
```

**Step 5: Commit**

```bash
git add lib/core/ lib/data/sources/
git commit -m "feat: add plugin system base (MangaSource abstract, registry, FetchConfig)"
```

---

### Task 6: Dio HTTP Client Setup

**Files:**
- Create: `lib/data/remote/http_client.dart`
- Create: `lib/data/remote/source_interceptor.dart`

**Step 1: Write HTTP client wrapper**

```dart
// lib/data/remote/http_client.dart
import 'package:dio/dio.dart';
import 'package:comic_reader/core/models/fetch_config.dart';

class HttpClient {
  late final Dio _dio;

  HttpClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
    ));
  }

  Dio get dio => _dio;

  /// Execute a FetchConfig and return the Dio Response
  Future<Response> execute(FetchConfig config) async {
    final options = Options(
      method: config.method == HttpMethod.get ? 'GET' : 'POST',
      headers: config.headers,
      responseType: ResponseType.plain,
    );

    if (config.timeout != null) {
      options.receiveTimeout = Duration(milliseconds: config.timeout!);
    }

    if (config.method == HttpMethod.post) {
      return _dio.request(
        config.url,
        data: config.body,
        queryParameters: config.queryParams,
        options: options,
      );
    }

    return _dio.request(
      config.url,
      queryParameters: config.queryParams ?? config.body,
      options: options,
    );
  }
}
```

**Step 2: Write source interceptor**

```dart
// lib/data/remote/source_interceptor.dart
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

/// Logs all requests and handles common errors
class SourceInterceptor extends Interceptor {
  final _log = Logger('SourceInterceptor');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log.fine('${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log.warning('HTTP Error: ${err.response?.statusCode} ${err.requestOptions.uri}');
    handler.next(err);
  }
}
```

**Step 3: Commit**

```bash
git add lib/data/remote/
git commit -m "feat: add Dio HTTP client with source interceptor"
```

---

### Task 7: CopyManga Plugin (First Port)

**Files:**
- Create: `lib/data/sources/copy_manga.dart`
- Create: `lib/core/utils/crypto_utils.dart`
- Create: `test/data/sources/copy_manga_test.dart`

**Step 1: Write crypto utility (AES decrypt for CopyManga)**

```dart
// lib/core/utils/crypto_utils.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';

/// AES-CBC decryption used by CopyManga.
/// The IV is the first 16 characters of the content string.
String aesDecrypt(String content, String keyStr) {
  if (content.isEmpty || keyStr.isEmpty) return '';
  
  final iv = IV.fromUtf8(content.substring(0, 16));
  final encrypted = content.substring(16);
  final key = Key.fromUtf8(keyStr);

  final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
  return encrypter.decrypt64(encrypted, iv: iv);
}
```

**Step 2: Write CopyManga plugin**

```dart
// lib/data/sources/copy_manga.dart
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/utils/hash_utils.dart';
import 'package:comic_reader/core/utils/crypto_utils.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'manga_source.dart';
import 'dart:convert';

const _defaultFilter = r'$$DEFAULT$$';

class CopyManga extends MangaSource {
  String _aesKey = 'xxxmanga.woo.key';

  static const _fetchHeaders = {
    'webp': '1',
    'region': '1',
    'platform': '3',
    'version': '2.3.1',
    'accept': 'application/json',
    'User-Agent': 'COPY/2.3.1',
  };

  static const _imageHeaders = {
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
  };

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36';

  @override
  String get id => 'COPY';

  @override
  String get name => '拷贝漫画';

  @override
  String get shortName => 'COPY';

  @override
  String get description => '';

  @override
  int get score => 5;

  @override
  String get baseUrl => 'https://www.mangacopy.com';

  @override
  String? get userAgent => _ua;

  @override
  Map<String, String> get defaultHeaders => {
        'Referer': 'https://www.mangacopy.com',
        'User-Agent': _ua,
        'Accept-Encoding': 'gzip, deflate, br',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };

  @override
  List<FilterOption> get discoveryFilters => [
        FilterOption(
          name: 'type',
          choices: [
            const FilterChoice(label: '选择分类', value: _defaultFilter),
            const FilterChoice(label: '愛情', value: 'aiqing'),
            const FilterChoice(label: '歡樂向', value: 'huanlexiang'),
            const FilterChoice(label: '冒险', value: 'maoxian'),
            const FilterChoice(label: '奇幻', value: 'qihuan'),
            const FilterChoice(label: '百合', value: 'baihe'),
            const FilterChoice(label: '校园', value: 'xiaoyuan'),
            const FilterChoice(label: '科幻', value: 'kehuan'),
            const FilterChoice(label: '生活', value: 'shenghuo'),
            const FilterChoice(label: '格鬥', value: 'gedou'),
            const FilterChoice(label: '悬疑', value: 'xuanyi'),
            const FilterChoice(label: '热血', value: 'rexue'),
          ],
        ),
        FilterOption(
          name: 'region',
          choices: [
            const FilterChoice(label: '选择地区', value: _defaultFilter),
            const FilterChoice(label: '日本', value: 'japan'),
            const FilterChoice(label: '韩国', value: 'korea'),
            const FilterChoice(label: '欧美', value: 'west'),
            const FilterChoice(label: '完结', value: 'finish'),
          ],
        ),
        FilterOption(
          name: 'sort',
          choices: [
            const FilterChoice(label: '更新时间↓', value: _defaultFilter),
            const FilterChoice(label: '更新时间↑', value: 'datetime_updated'),
            const FilterChoice(label: '热度↓', value: '-popular'),
            const FilterChoice(label: '热度↑', value: 'popular'),
          ],
        ),
      ];

  @override
  FetchConfig prepareDiscovery(int page, Map<String, String> filters) {
    final type = filters['type'];
    final region = filters['region'];
    final sort = filters['sort'];
    return FetchConfig(
      url: 'https://api.mangacopy.com/api/v3/comics',
      queryParams: {
        'free_type': '1',
        'limit': '21',
        'offset': '${(page - 1) * 21}',
        'ordering': (sort == null || sort == _defaultFilter) ? '-datetime_updated' : sort,
        if (type != null && type != _defaultFilter) 'theme': type,
        if (region != null && region != _defaultFilter) 'top': region,
        '_update': 'true',
      },
      headers: _fetchHeaders,
    );
  }

  @override
  FetchConfig prepareSearch(String keyword, int page, Map<String, String> filters) {
    return FetchConfig(
      url: 'https://api.mangacopy.com/api/v3/search/comic',
      queryParams: {
        'platform': '1',
        'q': keyword,
        'limit': '20',
        'offset': '${(page - 1) * 20}',
        'q_type': '',
        '_update': 'true',
      },
      headers: {..._fetchHeaders, 'platform': '2'},
    );
  }

  @override
  FetchConfig prepareMangaInfo(String mangaId) {
    return FetchConfig(
      url: 'https://www.mangacopy.com/comic/$mangaId',
      headers: {'User-Agent': _ua},
    );
  }

  @override
  FetchConfig prepareChapterList(String mangaId, int page) {
    return FetchConfig(
      url: 'https://www.mangacopy.com/comicdetail/$mangaId/chapters',
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://www.mangacopy.com/comic/$mangaId',
      },
    );
  }

  @override
  FetchConfig prepareChapter(String mangaId, String chapterId, int page, Map<String, dynamic> extra) {
    return FetchConfig(
      url: 'https://www.mangacopy.com/comic/$mangaId/chapter/$chapterId',
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://www.mangacopy.com/comic/$mangaId',
      },
    );
  }

  @override
  List<MangaSummary> parseDiscovery(Response response) {
    final data = jsonDecode(response.data as String);
    final list = data['results']['list'] as List;
    return list.map((item) {
      return MangaSummary(
        hash: combineHash(id, item['path_word']),
        sourceId: id,
        sourceName: name,
        mangaId: item['path_word'],
        title: item['name'],
        bookCover: item['cover'],
        updateTime: item['datetime_updated'],
        author: (item['author'] as List?)?.map((a) => a['name'] as String).join(', '),
        tags: (item['theme'] as List?)?.map((t) => t['name'] as String).toList() ?? [],
      );
    }).toList();
  }

  @override
  List<MangaSummary> parseSearch(Response response) {
    final data = jsonDecode(response.data as String);
    final list = data['results']['list'] as List;
    return list.map((item) {
      return MangaSummary(
        hash: combineHash(id, item['path_word']),
        sourceId: id,
        sourceName: name,
        mangaId: item['path_word'],
        title: item['name'],
        bookCover: item['cover'],
      );
    }).toList();
  }

  @override
  MangaDetail parseMangaInfo(Response response, String mangaId) {
    final html = response.data as String;

    // Extract AES key from page
    final keyMatch = RegExp(r"var ccx = '(.*?)'").firstMatch(html);
    if (keyMatch != null) {
      _aesKey = keyMatch.group(1)!;
    }

    final doc = html_parser.parse(html);
    final cover = doc.querySelector('.comicParticulars-left-img img')
        ?.attributes['data-src'] ?? '';
    final title = doc.querySelector('.comicParticulars-title-right h6')
        ?.text.trim() ?? '';

    final lis = doc.querySelectorAll(
        '.comicParticulars-title .comicParticulars-title-right ul li');

    List<String> authors = [];
    String? updateTime;
    List<String> tags = [];
    MangaStatus status = MangaStatus.unknown;

    for (final li in lis) {
      final label = li.querySelector('span')?.text.trim() ?? '';
      switch (label) {
        case '作者：':
          authors = li.querySelectorAll('.comicParticulars-right-txt a')
              .map((a) => a.text.trim())
              .toList();
          break;
        case '最後更新：':
          updateTime = li.querySelector('.comicParticulars-right-txt')?.text.trim();
          break;
        case '狀態：':
          final statusText = li.querySelector('.comicParticulars-right-txt')?.text.trim() ?? '';
          if (statusText.contains('連載中')) status = MangaStatus.serial;
          if (statusText.contains('已完結')) status = MangaStatus.ended;
          break;
        case '題材：':
          tags = li.querySelectorAll('.comicParticulars-tag a')
              .map((a) => a.text.trim())
              .toList();
          break;
      }
    }

    return MangaDetail(
      hash: combineHash(id, mangaId),
      sourceId: id,
      sourceName: name,
      mangaId: mangaId,
      title: title,
      bookCover: cover,
      infoCover: cover,
      authors: authors,
      tags: tags,
      status: status,
      updateTime: updateTime,
      href: 'https://www.mangacopy.com/comic/$mangaId',
    );
  }

  @override
  ChapterListResult parseChapterList(Response response, String mangaId) {
    final data = jsonDecode(response.data as String);
    final decrypted = aesDecrypt(data['results'] ?? '', _aesKey);
    final info = jsonDecode(decrypted);
    final pathWord = info['build']['path_word'] as String;
    final groups = info['groups'] as Map<String, dynamic>;

    List<Map<String, dynamic>> allChapters = [];
    final defaultGroup = groups['default'];
    if (defaultGroup != null) {
      allChapters = List<Map<String, dynamic>>.from(defaultGroup['chapters']);
    }
    for (final key in groups.keys.where((k) => k != 'default')) {
      final chapters = groups[key]['chapters'] as List;
      allChapters = [...chapters.cast<Map<String, dynamic>>(), ...allChapters];
    }

    final chapters = allChapters.reversed.map((item) {
      return ChapterItem(
        hash: combineHash(id, pathWord, item['id']),
        mangaId: pathWord,
        chapterId: item['id'],
        title: item['name'],
      );
    }).toList();

    return ChapterListResult(chapters: chapters, canLoadMore: false);
  }

  @override
  ChapterResult parseChapter(Response response, String mangaId, String chapterId, int page) {
    final html = response.data as String;

    final doc = html_parser.parse(html);
    final header = doc.querySelector('h4.header')?.text ?? '';
    final parts = header.split('/');
    final chapterName = parts.isNotEmpty ? parts[0].trim() : '';
    final chapterTitle = parts.length > 1 ? parts[1].trim() : '';

    // Extract AES key from page
    final keyMatch = RegExp(r"var ccy = '(.*?)'").firstMatch(html);
    final key = keyMatch?.group(1) ?? _aesKey;

    // Extract encrypted image data
    final imageDataEl = doc.querySelector('div.imageData');
    final contentKey = imageDataEl?.attributes['contentkey'] ?? '';
    final decrypted = aesDecrypt(contentKey, key);
    final images = (jsonDecode(decrypted) as List).map((item) {
      final url = (item['url'] as String)
          .replaceAll(RegExp(r'\.c[0-9]+x\.'), '.c1500x.');
      return ChapterImage(uri: url, headers: _imageHeaders);
    }).toList();

    return ChapterResult(
      chapter: Chapter(
        hash: combineHash(id, mangaId, chapterId),
        mangaId: mangaId,
        chapterId: chapterId,
        title: chapterTitle,
        name: chapterName,
        images: images,
        headers: _imageHeaders,
      ),
      canLoadMore: false,
    );
  }
}
```

**Step 3: Write basic unit test**

```dart
// test/data/sources/copy_manga_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/sources/copy_manga.dart';
import 'package:comic_reader/core/utils/hash_utils.dart';

void main() {
  late CopyManga source;

  setUp(() {
    source = CopyManga();
  });

  group('CopyManga metadata', () {
    test('has correct id and name', () {
      expect(source.id, 'COPY');
      expect(source.name, '拷贝漫画');
      expect(source.score, 5);
    });

    test('has discovery filters', () {
      expect(source.discoveryFilters.length, 3);
      expect(source.discoveryFilters[0].name, 'type');
      expect(source.discoveryFilters[1].name, 'region');
      expect(source.discoveryFilters[2].name, 'sort');
    });
  });

  group('CopyManga request builders', () {
    test('prepareDiscovery builds correct URL', () {
      final config = source.prepareDiscovery(1, {});
      expect(config.url, 'https://api.mangacopy.com/api/v3/comics');
      expect(config.queryParams?['offset'], '0');
      expect(config.queryParams?['limit'], '21');
    });

    test('prepareSearch builds correct URL', () {
      final config = source.prepareSearch('one piece', 2, {});
      expect(config.url, 'https://api.mangacopy.com/api/v3/search/comic');
      expect(config.queryParams?['q'], 'one piece');
      expect(config.queryParams?['offset'], '20');
    });

    test('prepareMangaInfo builds correct URL', () {
      final config = source.prepareMangaInfo('test-manga');
      expect(config.url, 'https://www.mangacopy.com/comic/test-manga');
    });
  });

  group('hash utils', () {
    test('combineHash creates correct format', () {
      expect(combineHash('COPY', 'manga1'), 'COPY&manga1');
      expect(combineHash('COPY', 'manga1', 'ch1'), 'COPY&manga1&ch1');
    });

    test('splitHash reverses combineHash', () {
      final (pluginId, mangaId, chapterId) = splitHash('COPY&manga1&ch1');
      expect(pluginId, 'COPY');
      expect(mangaId, 'manga1');
      expect(chapterId, 'ch1');
    });
  });
}
```

**Step 4: Run tests**

```bash
cd /Users/portz/js/comic/comic-reader
flutter test test/data/sources/copy_manga_test.dart
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add lib/data/sources/copy_manga.dart lib/core/utils/crypto_utils.dart test/
git commit -m "feat: port CopyManga plugin from MangaReader"
```

---

### Task 8: Repository Layer

**Files:**
- Create: `lib/domain/repositories/manga_repository.dart`
- Create: `lib/data/repositories/manga_repository_impl.dart`

**Step 1: Write repository interface**

```dart
// lib/domain/repositories/manga_repository.dart
import 'package:comic_reader/domain/entities/entities.dart';

abstract class MangaRepository {
  Future<List<MangaSummary>> getDiscovery(String sourceId, int page, Map<String, String> filters);
  Future<List<MangaSummary>> search(String sourceId, String keyword, int page, Map<String, String> filters);
  Future<MangaDetail> getMangaInfo(String sourceId, String mangaId);
  Future<ChapterListResult> getChapterList(String sourceId, String mangaId, int page);
  Future<ChapterResult> getChapter(String sourceId, String mangaId, String chapterId, int page, Map<String, dynamic> extra);
}
```

**Step 2: Write repository implementation**

```dart
// lib/data/repositories/manga_repository_impl.dart
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';

class MangaRepositoryImpl implements MangaRepository {
  final HttpClient _httpClient;
  final SourceRegistry _registry;

  MangaRepositoryImpl({
    required HttpClient httpClient,
    required SourceRegistry registry,
  })  : _httpClient = httpClient,
        _registry = registry;

  @override
  Future<List<MangaSummary>> getDiscovery(
      String sourceId, int page, Map<String, String> filters) async {
    final source = _registry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    final config = source.prepareDiscovery(page, filters);
    final response = await _httpClient.execute(config);
    return source.parseDiscovery(response);
  }

  @override
  Future<List<MangaSummary>> search(
      String sourceId, String keyword, int page, Map<String, String> filters) async {
    final source = _registry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    final config = source.prepareSearch(keyword, page, filters);
    final response = await _httpClient.execute(config);
    return source.parseSearch(response);
  }

  @override
  Future<MangaDetail> getMangaInfo(String sourceId, String mangaId) async {
    final source = _registry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    final config = source.prepareMangaInfo(mangaId);
    final response = await _httpClient.execute(config);
    return source.parseMangaInfo(response, mangaId);
  }

  @override
  Future<ChapterListResult> getChapterList(String sourceId, String mangaId, int page) async {
    final source = _registry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    final config = source.prepareChapterList(mangaId, page);
    if (config == null) return const ChapterListResult(chapters: []);

    final response = await _httpClient.execute(config);
    return source.parseChapterList(response, mangaId);
  }

  @override
  Future<ChapterResult> getChapter(
      String sourceId, String mangaId, String chapterId, int page, Map<String, dynamic> extra) async {
    final source = _registry.get(sourceId);
    if (source == null) throw Exception('Source not found: $sourceId');

    final config = source.prepareChapter(mangaId, chapterId, page, extra);
    final response = await _httpClient.execute(config);
    return source.parseChapter(response, mangaId, chapterId, page);
  }
}
```

**Step 3: Commit**

```bash
git add lib/domain/repositories/ lib/data/repositories/
git commit -m "feat: add MangaRepository interface and implementation"
```

---

## Phase 2: App Shell & Navigation

### Task 9: Theme System

**Files:**
- Create: `lib/app/theme/app_theme.dart`
- Create: `lib/app/theme/colors.dart`

**Step 1: Write color tokens**

```dart
// lib/app/theme/colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Light theme
  static const lightPrimary = Color(0xFF6750A4);
  static const lightSurface = Color(0xFFFFFBFE);
  static const lightBackground = Color(0xFFF8F6FC);
  static const lightCard = Colors.white;
  static const lightText = Color(0xFF1C1B1F);
  static const lightSubText = Color(0xFF49454F);

  // Dark theme
  static const darkPrimary = Color(0xFFD0BCFF);
  static const darkSurface = Color(0xFF1C1B1F);
  static const darkBackground = Color(0xFF141218);
  static const darkCard = Color(0xFF2B2930);
  static const darkText = Color(0xFFE6E1E5);
  static const darkSubText = Color(0xFFCAC4D0);

  // AMOLED
  static const amoledBackground = Colors.black;
  static const amoledSurface = Color(0xFF0A0A0A);
}
```

**Step 2: Write theme configuration**

```dart
// lib/app/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'colors.dart';

enum AppThemeMode { light, dark, amoled, system }

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: AppColors.lightPrimary,
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardColor: AppColors.lightCard,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: AppColors.darkPrimary,
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkCard,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData amoled() {
    return dark().copyWith(
      scaffoldBackgroundColor: AppColors.amoledBackground,
      cardColor: AppColors.amoledSurface,
    );
  }
}
```

**Step 3: Commit**

```bash
git add lib/app/theme/
git commit -m "feat: add theme system with light/dark/AMOLED modes"
```

---

### Task 10: Router Setup

**Files:**
- Create: `lib/app/router/app_router.dart`
- Create: `lib/app/router/routes.dart`

**Step 1: Write route definitions**

```dart
// lib/app/router/routes.dart

class AppRoutes {
  static const home = '/';
  static const discovery = '/discovery';
  static const search = '/search';
  static const detail = '/detail/:sourceId/:mangaId';
  static const chapter = '/chapter/:sourceId/:mangaId/:chapterId';
  static const settings = '/settings';
  static const webview = '/webview';

  static String detailPath(String sourceId, String mangaId) =>
      '/detail/$sourceId/$mangaId';
  static String chapterPath(String sourceId, String mangaId, String chapterId) =>
      '/chapter/$sourceId/$mangaId/$chapterId';
}
```

**Step 2: Write router configuration**

```dart
// lib/app/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'routes.dart';

// Placeholder screens - will be replaced with real implementations
class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen(this.title);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Text(title)),
      );
}

GoRouter createRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _PlaceholderScreen('Home'),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (context, state) => const _PlaceholderScreen('Discovery'),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) {
          final keyword = state.uri.queryParameters['keyword'] ?? '';
          final sourceId = state.uri.queryParameters['sourceId'] ?? '';
          return _PlaceholderScreen('Search: $keyword');
        },
      ),
      GoRoute(
        path: '/detail/:sourceId/:mangaId',
        builder: (context, state) {
          return _PlaceholderScreen('Detail: ${state.pathParameters['mangaId']}');
        },
      ),
      GoRoute(
        path: '/chapter/:sourceId/:mangaId/:chapterId',
        builder: (context, state) {
          return _PlaceholderScreen('Chapter');
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const _PlaceholderScreen('Settings'),
      ),
    ],
  );
}
```

**Step 3: Commit**

```bash
git add lib/app/router/
git commit -m "feat: add GoRouter navigation setup with route definitions"
```

---

### Task 11: App Entry Point & DI

**Files:**
- Modify: `lib/main.dart`
- Create: `lib/app/app.dart`
- Create: `lib/app/di/injection.dart`

**Step 1: Write DI setup**

```dart
// lib/app/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:comic_reader/data/remote/http_client.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/data/sources/copy_manga.dart';
import 'package:comic_reader/data/repositories/manga_repository_impl.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // HTTP
  getIt.registerLazySingleton<HttpClient>(() => HttpClient());

  // Sources
  getIt.registerLazySingleton<SourceRegistry>(() {
    final registry = SourceRegistry();
    registry.register(CopyManga());
    // TODO: Register more plugins here
    return registry;
  });

  // Repositories
  getIt.registerLazySingleton<MangaRepository>(
    () => MangaRepositoryImpl(
      httpClient: getIt<HttpClient>(),
      registry: getIt<SourceRegistry>(),
    ),
  );
}
```

**Step 2: Write App widget**

```dart
// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:comic_reader/app/router/app_router.dart';
import 'package:comic_reader/app/theme/app_theme.dart';

class ComicReaderApp extends StatelessWidget {
  const ComicReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = createRouter();

    return MaterialApp.router(
      title: 'Comic Reader',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

**Step 3: Update main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/app.dart';
import 'app/di/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait on mobile
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await configureDependencies();

  runApp(const ComicReaderApp());
}
```

**Step 4: Verify app builds and runs**

```bash
cd /Users/portz/js/comic/comic-reader
flutter analyze
flutter build web --release 2>&1 | tail -5
```

Expected: No analysis errors, web build succeeds

**Step 5: Commit**

```bash
git add lib/main.dart lib/app/
git commit -m "feat: app entry point with DI, router, and theme"
```

---

## Phase 3: Immersive Reader (Core Feature)

### Task 12: Reader Bloc (State Management)

**Files:**
- Create: `lib/presentation/reader/bloc/reader_state.dart`
- Create: `lib/presentation/reader/bloc/reader_event.dart`
- Create: `lib/presentation/reader/bloc/reader_bloc.dart`

**Step 1: Write reader state**

```dart
// lib/presentation/reader/bloc/reader_state.dart
import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';

enum ReaderStatus { initial, loading, loaded, error }
enum LayoutMode { horizontal, vertical }
enum ReadingDirection { ltr, rtl }

class ReaderState extends Equatable {
  final ReaderStatus status;
  final Chapter? chapter;
  final List<ChapterImage> images; // flattened images (may span chapters)
  final int currentPage;
  final int totalPages;
  final LayoutMode layoutMode;
  final ReadingDirection direction;
  final bool controlsVisible;
  final bool isFullScreen;
  final String? error;
  final String? chapterTitle;
  final String? mangaTitle;
  // Seamless chapter loading
  final bool loadingNextChapter;
  final bool loadingPrevChapter;
  final List<ChapterItem> chapterList;
  final int currentChapterIndex;

  const ReaderState({
    this.status = ReaderStatus.initial,
    this.chapter,
    this.images = const [],
    this.currentPage = 0,
    this.totalPages = 0,
    this.layoutMode = LayoutMode.horizontal,
    this.direction = ReadingDirection.ltr,
    this.controlsVisible = false,
    this.isFullScreen = true,
    this.error,
    this.chapterTitle,
    this.mangaTitle,
    this.loadingNextChapter = false,
    this.loadingPrevChapter = false,
    this.chapterList = const [],
    this.currentChapterIndex = 0,
  });

  ReaderState copyWith({
    ReaderStatus? status,
    Chapter? chapter,
    List<ChapterImage>? images,
    int? currentPage,
    int? totalPages,
    LayoutMode? layoutMode,
    ReadingDirection? direction,
    bool? controlsVisible,
    bool? isFullScreen,
    String? error,
    String? chapterTitle,
    String? mangaTitle,
    bool? loadingNextChapter,
    bool? loadingPrevChapter,
    List<ChapterItem>? chapterList,
    int? currentChapterIndex,
  }) {
    return ReaderState(
      status: status ?? this.status,
      chapter: chapter ?? this.chapter,
      images: images ?? this.images,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      layoutMode: layoutMode ?? this.layoutMode,
      direction: direction ?? this.direction,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      isFullScreen: isFullScreen ?? this.isFullScreen,
      error: error ?? this.error,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      mangaTitle: mangaTitle ?? this.mangaTitle,
      loadingNextChapter: loadingNextChapter ?? this.loadingNextChapter,
      loadingPrevChapter: loadingPrevChapter ?? this.loadingPrevChapter,
      chapterList: chapterList ?? this.chapterList,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
    );
  }

  @override
  List<Object?> get props => [
        status, chapter, images, currentPage, totalPages,
        layoutMode, direction, controlsVisible, isFullScreen,
        error, loadingNextChapter, loadingPrevChapter,
        currentChapterIndex,
      ];
}
```

**Step 2: Write reader events**

```dart
// lib/presentation/reader/bloc/reader_event.dart
import 'package:equatable/equatable.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'reader_state.dart';

abstract class ReaderEvent extends Equatable {
  const ReaderEvent();
  @override
  List<Object?> get props => [];
}

class LoadChapter extends ReaderEvent {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final List<ChapterItem> chapterList;
  final int initialPage;

  const LoadChapter({
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    required this.chapterList,
    this.initialPage = 0,
  });

  @override
  List<Object?> get props => [sourceId, mangaId, chapterId];
}

class PageChanged extends ReaderEvent {
  final int page;
  const PageChanged(this.page);
  @override
  List<Object?> get props => [page];
}

class ToggleControls extends ReaderEvent {
  const ToggleControls();
}

class HideControls extends ReaderEvent {
  const HideControls();
}

class ChangeLayoutMode extends ReaderEvent {
  final LayoutMode mode;
  const ChangeLayoutMode(this.mode);
  @override
  List<Object?> get props => [mode];
}

class ChangeDirection extends ReaderEvent {
  final ReadingDirection direction;
  const ChangeDirection(this.direction);
  @override
  List<Object?> get props => [direction];
}

class LoadNextChapter extends ReaderEvent {
  const LoadNextChapter();
}

class LoadPreviousChapter extends ReaderEvent {
  const LoadPreviousChapter();
}
```

**Step 3: Write reader bloc**

```dart
// lib/presentation/reader/bloc/reader_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'reader_event.dart';
import 'reader_state.dart';

class ReaderBloc extends Bloc<ReaderEvent, ReaderState> {
  final MangaRepository _repository;

  ReaderBloc({required MangaRepository repository})
      : _repository = repository,
        super(const ReaderState()) {
    on<LoadChapter>(_onLoadChapter);
    on<PageChanged>(_onPageChanged);
    on<ToggleControls>(_onToggleControls);
    on<HideControls>(_onHideControls);
    on<ChangeLayoutMode>(_onChangeLayoutMode);
    on<ChangeDirection>(_onChangeDirection);
    on<LoadNextChapter>(_onLoadNextChapter);
    on<LoadPreviousChapter>(_onLoadPreviousChapter);
  }

  Future<void> _onLoadChapter(LoadChapter event, Emitter<ReaderState> emit) async {
    emit(state.copyWith(status: ReaderStatus.loading));
    try {
      final result = await _repository.getChapter(
        event.sourceId, event.mangaId, event.chapterId, 1, {},
      );

      final chapterIndex = event.chapterList.indexWhere(
        (c) => c.chapterId == event.chapterId,
      );

      emit(state.copyWith(
        status: ReaderStatus.loaded,
        chapter: result.chapter,
        images: result.chapter.images,
        currentPage: event.initialPage,
        totalPages: result.chapter.images.length,
        chapterTitle: result.chapter.title,
        mangaTitle: result.chapter.name,
        chapterList: event.chapterList,
        currentChapterIndex: chapterIndex >= 0 ? chapterIndex : 0,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ReaderStatus.error,
        error: e.toString(),
      ));
    }
  }

  void _onPageChanged(PageChanged event, Emitter<ReaderState> emit) {
    emit(state.copyWith(currentPage: event.page));

    // Auto-load next chapter when near end
    if (event.page >= state.totalPages - 2 && !state.loadingNextChapter) {
      add(const LoadNextChapter());
    }
  }

  void _onToggleControls(ToggleControls event, Emitter<ReaderState> emit) {
    emit(state.copyWith(controlsVisible: !state.controlsVisible));
  }

  void _onHideControls(HideControls event, Emitter<ReaderState> emit) {
    emit(state.copyWith(controlsVisible: false));
  }

  void _onChangeLayoutMode(ChangeLayoutMode event, Emitter<ReaderState> emit) {
    emit(state.copyWith(layoutMode: event.mode));
  }

  void _onChangeDirection(ChangeDirection event, Emitter<ReaderState> emit) {
    emit(state.copyWith(direction: event.direction));
  }

  Future<void> _onLoadNextChapter(LoadNextChapter event, Emitter<ReaderState> emit) async {
    if (state.currentChapterIndex >= state.chapterList.length - 1) return;
    if (state.loadingNextChapter) return;

    emit(state.copyWith(loadingNextChapter: true));

    try {
      final nextChapter = state.chapterList[state.currentChapterIndex + 1];
      final sourceId = state.chapter?.mangaId != null
          ? state.images.first.uri.isNotEmpty ? state.chapter!.mangaId : ''
          : '';

      // Get the source ID from the chapter hash
      final parts = nextChapter.hash.split('&');
      final sId = parts.isNotEmpty ? parts[0] : '';

      final result = await _repository.getChapter(
        sId, nextChapter.mangaId, nextChapter.chapterId, 1, {},
      );

      final newImages = [...state.images, ...result.chapter.images];
      emit(state.copyWith(
        images: newImages,
        totalPages: newImages.length,
        loadingNextChapter: false,
        currentChapterIndex: state.currentChapterIndex + 1,
      ));
    } catch (e) {
      emit(state.copyWith(loadingNextChapter: false));
    }
  }

  Future<void> _onLoadPreviousChapter(LoadPreviousChapter event, Emitter<ReaderState> emit) async {
    if (state.currentChapterIndex <= 0) return;
    if (state.loadingPrevChapter) return;

    emit(state.copyWith(loadingPrevChapter: true));

    try {
      final prevChapter = state.chapterList[state.currentChapterIndex - 1];
      final parts = prevChapter.hash.split('&');
      final sId = parts.isNotEmpty ? parts[0] : '';

      final result = await _repository.getChapter(
        sId, prevChapter.mangaId, prevChapter.chapterId, 1, {},
      );

      final newImages = [...result.chapter.images, ...state.images];
      final offset = result.chapter.images.length;
      emit(state.copyWith(
        images: newImages,
        totalPages: newImages.length,
        currentPage: state.currentPage + offset,
        loadingPrevChapter: false,
        currentChapterIndex: state.currentChapterIndex - 1,
      ));
    } catch (e) {
      emit(state.copyWith(loadingPrevChapter: false));
    }
  }
}
```

**Step 4: Commit**

```bash
git add lib/presentation/reader/bloc/
git commit -m "feat: add ReaderBloc with seamless chapter loading"
```

---

### Task 13: Immersive Reader Widget (Horizontal Mode)

**Files:**
- Create: `lib/presentation/reader/reader_screen.dart`
- Create: `lib/presentation/reader/widgets/reader_controls.dart`
- Create: `lib/presentation/reader/widgets/horizontal_reader.dart`
- Create: `lib/presentation/reader/widgets/manga_image.dart`

**Step 1: Write manga image widget**

```dart
// lib/presentation/reader/widgets/manga_image.dart
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:comic_reader/domain/entities/entities.dart';

class MangaImage extends StatelessWidget {
  final ChapterImage image;
  final BoxFit fit;
  final double? width;
  final double? height;

  const MangaImage({
    super.key,
    required this.image,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ExtendedImage.network(
      image.uri,
      fit: fit,
      width: width,
      height: height,
      headers: image.headers,
      cache: true,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          case LoadState.failed:
            return GestureDetector(
              onTap: () => state.reLoadImage(),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('点击重试', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            );
          case LoadState.completed:
            return null; // Use default rendering
        }
      },
    );
  }
}
```

**Step 2: Write horizontal reader widget**

```dart
// lib/presentation/reader/widgets/horizontal_reader.dart
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'manga_image.dart';

class HorizontalReader extends StatefulWidget {
  final List<ChapterImage> images;
  final int initialPage;
  final bool rtl;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapCenter;

  const HorizontalReader({
    super.key,
    required this.images,
    this.initialPage = 0,
    this.rtl = false,
    required this.onPageChanged,
    required this.onTapCenter,
  });

  @override
  State<HorizontalReader> createState() => _HorizontalReaderState();
}

class _HorizontalReaderState extends State<HorizontalReader> {
  late ExtendedPageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ExtendedPageController(
      initialPage: widget.initialPage,
      pageSpacing: 0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    final third = screenWidth / 3;

    if (x < third) {
      // Left third: previous page (or next in RTL)
      final target = widget.rtl
          ? _controller.page!.round() + 1
          : _controller.page!.round() - 1;
      if (target >= 0 && target < widget.images.length) {
        _controller.animateToPage(target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    } else if (x > third * 2) {
      // Right third: next page (or previous in RTL)
      final target = widget.rtl
          ? _controller.page!.round() - 1
          : _controller.page!.round() + 1;
      if (target >= 0 && target < widget.images.length) {
        _controller.animateToPage(target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    } else {
      // Center third: toggle controls
      widget.onTapCenter();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: _handleTap,
      child: ExtendedImageGesturePageView.builder(
        controller: _controller,
        reverse: widget.rtl,
        itemCount: widget.images.length,
        onPageChanged: widget.onPageChanged,
        itemBuilder: (context, index) {
          return ExtendedImageGesture(
            child: MangaImage(
              image: widget.images[index],
              fit: BoxFit.contain,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
            ),
          );
        },
      ),
    );
  }
}
```

**Step 3: Write reader controls overlay**

```dart
// lib/presentation/reader/widgets/reader_controls.dart
import 'package:flutter/material.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';

class ReaderControls extends StatelessWidget {
  final String? title;
  final int currentPage;
  final int totalPages;
  final LayoutMode layoutMode;
  final VoidCallback onBack;
  final VoidCallback onToggleLayout;
  final ValueChanged<int> onSliderChanged;

  const ReaderControls({
    super.key,
    this.title,
    required this.currentPage,
    required this.totalPages,
    required this.layoutMode,
    required this.onBack,
    required this.onToggleLayout,
    required this.onSliderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Top bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                ],
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
              left: 8,
              right: 8,
              bottom: 16,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    title ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    layoutMode == LayoutMode.horizontal
                        ? Icons.view_day
                        : Icons.view_carousel,
                    color: Colors.white,
                  ),
                  onPressed: onToggleLayout,
                ),
              ],
            ),
          ),
        ),

        // Bottom bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                ],
              ),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 8,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Row(
              children: [
                Text(
                  '${currentPage + 1}',
                  style: const TextStyle(color: Colors.white),
                ),
                Expanded(
                  child: Slider(
                    value: currentPage.toDouble(),
                    min: 0,
                    max: (totalPages - 1).toDouble().clamp(0, double.infinity),
                    onChanged: (v) => onSliderChanged(v.round()),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white38,
                  ),
                ),
                Text(
                  '$totalPages',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
```

**Step 4: Write main reader screen**

```dart
// lib/presentation/reader/reader_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:comic_reader/app/di/injection.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'bloc/reader_bloc.dart';
import 'bloc/reader_event.dart';
import 'bloc/reader_state.dart';
import 'widgets/horizontal_reader.dart';
import 'widgets/reader_controls.dart';

class ReaderScreen extends StatefulWidget {
  final String sourceId;
  final String mangaId;
  final String chapterId;

  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  @override
  void initState() {
    super.initState();
    // Enter immersive full-screen mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ReaderBloc(repository: getIt<MangaRepository>())
        ..add(LoadChapter(
          sourceId: widget.sourceId,
          mangaId: widget.mangaId,
          chapterId: widget.chapterId,
          chapterList: [], // TODO: pass from navigation
        )),
      child: const _ReaderView(),
    );
  }
}

class _ReaderView extends StatelessWidget {
  const _ReaderView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocBuilder<ReaderBloc, ReaderState>(
        builder: (context, state) {
          if (state.status == ReaderStatus.loading) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (state.status == ReaderStatus.error) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white54, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    state.error ?? '加载失败',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            );
          }

          if (state.images.isEmpty) {
            return const Center(
              child: Text('暂无内容', style: TextStyle(color: Colors.white54)),
            );
          }

          return Stack(
            children: [
              // Reader content
              HorizontalReader(
                images: state.images,
                initialPage: state.currentPage,
                rtl: state.direction == ReadingDirection.rtl,
                onPageChanged: (page) {
                  context.read<ReaderBloc>().add(PageChanged(page));
                },
                onTapCenter: () {
                  context.read<ReaderBloc>().add(const ToggleControls());
                },
              ),

              // Controls overlay (animated)
              AnimatedOpacity(
                opacity: state.controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !state.controlsVisible,
                  child: ReaderControls(
                    title: state.chapterTitle,
                    currentPage: state.currentPage,
                    totalPages: state.totalPages,
                    layoutMode: state.layoutMode,
                    onBack: () => Navigator.of(context).pop(),
                    onToggleLayout: () {
                      final newMode = state.layoutMode == LayoutMode.horizontal
                          ? LayoutMode.vertical
                          : LayoutMode.horizontal;
                      context.read<ReaderBloc>().add(ChangeLayoutMode(newMode));
                    },
                    onSliderChanged: (page) {
                      context.read<ReaderBloc>().add(PageChanged(page));
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

**Step 5: Commit**

```bash
git add lib/presentation/reader/
git commit -m "feat: add immersive reader with horizontal mode and controls overlay"
```

---

### Task 14: Vertical Webtoon Reader

**Files:**
- Create: `lib/presentation/reader/widgets/vertical_reader.dart`
- Modify: `lib/presentation/reader/reader_screen.dart`

**Step 1: Write vertical reader widget**

```dart
// lib/presentation/reader/widgets/vertical_reader.dart
import 'package:flutter/material.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'manga_image.dart';

class VerticalReader extends StatefulWidget {
  final List<ChapterImage> images;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapCenter;
  final VoidCallback? onReachEnd;

  const VerticalReader({
    super.key,
    required this.images,
    this.initialPage = 0,
    required this.onPageChanged,
    required this.onTapCenter,
    this.onReachEnd,
  });

  @override
  State<VerticalReader> createState() => _VerticalReaderState();
}

class _VerticalReaderState extends State<VerticalReader> {
  late ScrollController _scrollController;
  int _currentVisibleIndex = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Detect when reaching bottom for seamless chapter loading
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      widget.onReachEnd?.call();
    }
  }

  void _handleTap(TapUpDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final y = details.globalPosition.dy;
    final third = screenHeight / 3;

    if (y > third && y < third * 2) {
      widget.onTapCenter();
    }
    // Top/bottom thirds do nothing in vertical mode (scroll handles it)
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTapUp: _handleTap,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.images.length,
        cacheExtent: screenWidth * 5, // Preload 5 screens worth
        itemBuilder: (context, index) {
          return MangaImage(
            image: widget.images[index],
            fit: BoxFit.fitWidth,
            width: screenWidth,
          );
        },
      ),
    );
  }
}
```

**Step 2: Update reader_screen.dart to support layout switching**

In `_ReaderView`, replace the `HorizontalReader` section with layout mode switching:

```dart
// In the Stack children, replace HorizontalReader with:
if (state.layoutMode == LayoutMode.horizontal)
  HorizontalReader(
    images: state.images,
    initialPage: state.currentPage,
    rtl: state.direction == ReadingDirection.rtl,
    onPageChanged: (page) {
      context.read<ReaderBloc>().add(PageChanged(page));
    },
    onTapCenter: () {
      context.read<ReaderBloc>().add(const ToggleControls());
    },
  )
else
  VerticalReader(
    images: state.images,
    initialPage: state.currentPage,
    onPageChanged: (page) {
      context.read<ReaderBloc>().add(PageChanged(page));
    },
    onTapCenter: () {
      context.read<ReaderBloc>().add(const ToggleControls());
    },
    onReachEnd: () {
      context.read<ReaderBloc>().add(const LoadNextChapter());
    },
  ),
```

**Step 3: Commit**

```bash
git add lib/presentation/reader/
git commit -m "feat: add vertical webtoon reader with seamless chapter loading"
```

---

## Phase 4: Discovery, Detail & Home Screens

### Task 15: Discovery Bloc & Screen

**Files:**
- Create: `lib/presentation/discovery/bloc/discovery_cubit.dart`
- Create: `lib/presentation/discovery/bloc/discovery_state.dart`
- Create: `lib/presentation/discovery/discovery_screen.dart`

(Implementation follows same Bloc pattern - loads manga list from source with pagination and filters)

### Task 16: Detail Bloc & Screen

**Files:**
- Create: `lib/presentation/detail/bloc/detail_cubit.dart`
- Create: `lib/presentation/detail/bloc/detail_state.dart`
- Create: `lib/presentation/detail/detail_screen.dart`

(Shows manga info, chapter list grid, tap chapter to enter reader)

### Task 17: Home Screen (Bookshelf)

**Files:**
- Create: `lib/presentation/home/bloc/home_cubit.dart`
- Create: `lib/presentation/home/bloc/home_state.dart`
- Create: `lib/presentation/home/home_screen.dart`

(Grid of favorited manga, stored in Isar)

### Task 18: Search Screen

**Files:**
- Create: `lib/presentation/search/bloc/search_cubit.dart`
- Create: `lib/presentation/search/search_screen.dart`

(Search with keyword + plugin filter + pagination)

---

## Phase 5: Local Storage (Isar)

### Task 19: Isar Schema & DAO

**Files:**
- Create: `lib/data/local/schemas/manga_schema.dart`
- Create: `lib/data/local/schemas/reading_record_schema.dart`
- Create: `lib/data/local/dao/manga_dao.dart`
- Create: `lib/data/local/dao/record_dao.dart`
- Create: `lib/data/local/database.dart`

(Isar collections for: favorites, reading history/progress, chapter cache, settings)

---

## Phase 6: Additional Plugin Ports

### Task 20: Manhuagui Mobile Plugin

**Files:**
- Create: `lib/data/sources/manhuagui_mobile.dart`

(HTML scraping + LZString decompression + eval pattern)

### Task 21: JMComic Plugin

**Files:**
- Create: `lib/data/sources/jm_comic.dart`
- Create: `lib/core/utils/scramble_utils.dart`

(Image scramble/descramble logic ported from MangaReader's JMC plugin)

---

## Phase 7: Polish & Platform Adaptation

### Task 22: Desktop & Web Adaptations

- Keyboard shortcuts (arrow keys, space for page turn)
- Mouse hover scroll for vertical mode
- Responsive layouts for wider screens

### Task 23: Settings Screen

- Theme selection (light/dark/AMOLED/system)
- Default reading mode
- Default direction (LTR/RTL)
- Image quality preference
- Cache management

---

## Execution Order Summary

| Phase | Tasks | Key Deliverable |
|-------|-------|-----------------|
| 1 | 1-8 | Project scaffold + plugin system + CopyManga + repository |
| 2 | 9-11 | Theme + router + DI + app shell running |
| 3 | 12-14 | **Immersive reader** (horizontal + vertical + controls) |
| 4 | 15-18 | Discovery + Detail + Home + Search screens |
| 5 | 19 | Isar persistence (favorites, reading progress) |
| 6 | 20-21 | Additional plugins (Manhuagui, JMComic) |
| 7 | 22-23 | Desktop/web polish + settings |

**First milestone (Tasks 1-14):** App builds, CopyManga works end-to-end, immersive reader functional.
