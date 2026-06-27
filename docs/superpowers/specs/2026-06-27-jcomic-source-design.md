# JComic Source Design

**Date:** 2026-06-27
**Source:** jcomic.net
**Type:** HTML scraping (RegExp-based)

## Overview

Add JComic (jcomic.net) as a new manga data source plugin. JComic is a traditional Chinese manga site with no authentication required, no Cloudflare protection, and a clean HTML structure that's straightforward to parse.

## Source Identity

| Field | Value |
|-------|-------|
| id | `jcomic` |
| name | `JComic` |
| shortName | `JC` |
| description | `jcomic.net` |
| score | `4.0` |
| href | `https://jcomic.net` |
| needsProxy | `false` |
| needsCloudflare | `false` |

## File Location

- Source: `lib/data/sources/jcomic.dart`
- Registration: `lib/app/di/injection.dart` via `registry.register(JComic())`

## Key Design Decisions

1. **mangaId** = title string from URL path (e.g., the `{title}` in `/eps/{title}`)
2. **Single vs Multi-chapter distinction**: mangaId prefixed with `__single__` for single-chapter manga, plain for multi-chapter
3. **chapterId** = episode number string (e.g., `"1"`, `"2"`); fixed `"1"` for single-chapter
4. **All categories exposed** as filter options (36 total)
5. **No special handling for S3 presigned URL expiry** — images load in one batch, 60s is sufficient
6. **Chapter list embedded in info page** — `prepareChapterListFetch` returns `null`

## Discovery

### Filters

Single filter: `category` (分類), default `最近更新`

Full list: 最近更新, 隨機, 全彩, 長篇, 單行本, 同人, 短篇, Cosplay, 歐美, WEBTOON, 圓神領域, 碧藍幻想, CG雜圖, 英語 ENG, 生肉, 純愛, 百合花園, 耽美花園, 偽娘哲學, 後宮閃光, 扶他樂園, 姐姐系, 妹妹系, SM, 性轉換, 足の恋, 重口地帶, 人妻, NTR, 強暴, 非人類, 艦隊收藏, Love Live, SAO 刀劍神域, Fate, 東方, 禁書目錄

### Fetch

```
GET https://jcomic.net/cat/{category}/{page}
```

Category value is URL-encoded in the path.

### Parse

Each item is a `<div class="row col-lg-4 col-md-6 col-xs-12">` block:

- **mangaId**: Extract from `<a href="/page/{id}">` or `<a href="/eps/{id}">`
  - If href starts with `/page/` → prefix mangaId with `__single__`
  - If href starts with `/eps/` → use as-is
- **title**: `<p class='comic-title'>` text, strip trailing ` (N)` count
- **coverUrl**: `<img class="img-responsive comic-thumb" src="...">`
- **author**: Text inside `<a href="/author/..."><button>` element
- **updateTime**: Date from `<p class='comic-date'>最後更新: {date}</p>`
- **headers**: `{'Referer': 'https://jcomic.net'}` for cover image loading

## Search

### Fetch

```
GET https://jcomic.net/search/{keyword}
```

Keyword is URL-encoded. No pagination support (page > 1 returns empty).

### Parse

Same HTML structure as discovery listing. Reuse the same parsing method.

## Manga Info

### Fetch

Based on mangaId prefix:
- Multi-chapter (no prefix): `GET https://jcomic.net/eps/{mangaId}`
- Single-chapter (`__single__` prefix): `GET https://jcomic.net/page/{strippedId}`

### Parse — Multi-chapter (`/eps/{title}`)

Left column metadata:
- **title**: `<p class='comic-title'>` or `<h1>`
- **coverUrl**: `<img class="img-responsive comic-thumb">`
- **author**: `<a href="/author/...">` button text
- **tags**: All `<a href="/cat/...">` button texts
- **updateTime**: `<p class='comic-date'>` content

Right column chapter list:
- Each `<a href="/page/{title}/{epNum}"><button>{chapterTitle}</button></a>` becomes a `ChapterItem`:
  - `id`: epNum string (e.g., `"1"`, `"2"`)
  - `mangaId`: the manga's mangaId
  - `title`: button text content

### Parse — Single-chapter (`/page/{title}`)

Extract metadata from the reading page itself:
- **title**: `<h1>` text, strip trailing ` (N)`
- **coverUrl**: first `<img class="img-responsive comic-thumb">`
- **author**: author button text
- **tags**: category button texts

Generate fixed chapter list:
```dart
chapters: [ChapterItem(id: "1", mangaId: mangaId, title: "全一話")]
```

## Chapter List

`prepareChapterListFetch` returns `null` — chapters are fully embedded in the manga info page response.

## Chapter Content

### Fetch

```
Multi-chapter: GET https://jcomic.net/page/{mangaId}/{chapterId}
Single-chapter: GET https://jcomic.net/page/{strippedMangaId}
```

Where `strippedMangaId` = mangaId with `__single__` prefix removed.

### Parse

Extract all `<img class="img-responsive comic-thumb" src="...">` elements from the page body (excluding any navigation/header images if needed).

Each image becomes:
```dart
ChapterImage(
  url: fullS3PresignedUrl,
  scrambleType: ScrambleType.none,
  headers: {'Referer': 'https://jcomic.net'},
)
```

Result: `ChapterResult(chapter: ..., canLoadMore: false)`

### getChapterWebUrl

Override to return the reading page URL:
- Multi-chapter: `https://jcomic.net/page/{mangaId}/{chapterId}`
- Single-chapter: `https://jcomic.net/page/{strippedMangaId}`

## Headers

Default headers for all requests:
```dart
{
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36',
  'Referer': 'https://jcomic.net',
}
```

Image headers:
```dart
{'Referer': 'https://jcomic.net'}
```

## HTML Parsing Strategy

Use RegExp patterns matching the site's consistent class naming:
- `comic-title`, `comic-author`, `comic-date`, `comic-category`
- `img-responsive comic-thumb` for images
- `/page/` and `/eps/` href patterns for link type detection

## Edge Cases

1. **URL encoding**: manga titles may contain brackets `[]`, parentheses `()`, CJK characters — all must be properly URL-encoded in paths
2. **Image filtering**: The reading page may contain a cover thumbnail in breadcrumb area; filter by context (only images within the main content area)
3. **Empty results**: Some categories may have no results on higher page numbers; return empty list gracefully
4. **Title cleanup**: Strip ` (N)` suffix from titles where N is the image count
