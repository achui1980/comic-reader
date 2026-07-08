# Webtoons (zh-hant) Source Design

**Date:** 2026-07-08
**Source:** www.webtoons.com/zh-hant
**Type:** HTML scraping (CSS-selector based, `html` package)

## Overview

Add Webtoons (LINE Webtoon international, Traditional Chinese storefront) as a new manga data source plugin. The site shares the same underlying template/engine as `dongmanmanhua.dart` (LINE Webtoon China), so the implementation reuses that source's architecture: instance-level canonical-path caching, mangaId encoding that embeds the resolved path, and forced pagination through the dedicated chapter-list endpoint rather than trusting the info page's embedded list.

Key differences from `dongmanmanhua.dart` that drive design decisions:
- The genre listing page (`/genres/{slug}`) has **real server-side pagination** — no "page>1 returns empty" hack needed.
- The generic placeholder path for chapter list/viewer (`/comic/{titleNo}/...`) triggers a **301 redirect that drops the `page` query parameter** — same pitfall as dongmanmanhua, requiring canonical-path caching for chapter list pagination.
- The generic placeholder path for the **viewer** returns **HTTP 500** (not a redirect) — unlike dongmanmanhua, so the viewer request always needs a resolved canonical path, with no generic fallback URL.
- Chapter/cover images require a `Referer: https://www.webtoons.com/` header on the CDN (`webtoon-phinf.pstatic.net`) or they 403.

## Source Identity

| Field | Value |
|-------|-------|
| id | `webtoons` |
| name | `Webtoons` |
| shortName | `Webtoons` |
| description | `webtoons.com (繁體中文)` |
| href | `https://www.webtoons.com/zh-hant` |
| isAdult | `false` |
| needsProxy | `false` |
| needsCloudflare | `false` |
| usesWebViewFetch | `false` |

## File Location

- Source: `lib/data/sources/webtoons.dart`
- Registration: `lib/app/di/injection.dart` via `registry.register(WebtoonsSource())`

## Key Design Decisions

1. **mangaId encoding**: `"{titleNo}::{genreSlug}/{titleSlug}"` once the canonical path is known, or plain `"{titleNo}"` when it isn't yet (e.g. straight out of discovery/search cards).
2. **`_pathCache<String,String>`**: instance-level map `titleNo -> "genreSlug/titleSlug"`, populated lazily by whichever request resolves it first (manga info, chapter list, or an explicit probe).
3. **`_resolvePath(titleNo)`**: when neither the mangaId nor the cache has a path, issue one probe request to the generic placeholder list URL, follow the 301, and extract the path from the `Location` header or the response's `<link rel="canonical">`. Used by chapter list and viewer fetches when needed.
4. **Discovery default**: `genre = ACTION`, `sortOrder = UPDATE`. Both are exposed as `FilterOption`s so the user can change them in-app.
5. **Search scope**: only officially serialized `WEBTOON` cards (`data-webtoon-type="WEBTOON"`); CANVAS (amateur) results are explicitly filtered out.
6. **Chapter titles**: `"第N話"` format only, no date suffix (matches dongmanmanhua style). `ChapterItem` has no date field, so publish date is not modeled.
7. **`isAdult = false`** at the source level — the site is general-audience with one adult-oriented genre bucket (`ROMANCE_M`), same posture as other aggregator sources (baozi, copy_manga) that don't hide the whole source over one category.
8. **Chapter list is never trusted from the info page** — `parseMangaInfo` always returns `chapters: []`; the app must page through `prepareChapterListFetch`/`parseChapterList` to get the full, correctly-paginated set.
9. **Paywall degradation**: if `#_imageList img._images` yields zero images for a chapter (observed rarely, described in-app as "最新10話僅限APP" for some titles), return an empty image list rather than throwing — the reader shows an empty chapter instead of crashing.

## Discovery

### Filters

- `genre` (`FilterOption`, default `ACTION`): 22 choices, code → 繁中 label:
  `ROMANCE`=愛情, `WESTERN_PALACE`=歐式宮廷, `ADAPTATION`=影視化, `SCHOOL`=校園, `LOCAL`=台灣原創作品, `FANTASY`=奇幻冒險, `THRILLER`=驚悚, `HORROR`=恐怖, `MARTIAL_ARTS`=武俠, `BL_GL`=LGBTQ+, `ROMANCE_M`=大人系, `DRAMA`=劇情, `ACTION`=動作, `SLICE_OF_LIFE`=生活/日常, `COMEDY`=搞笑, `TIME_SLIP`=穿越/轉生, `CITY_OFFICE`=現代/職場, `MYSTERY`=懸疑推理, `HEARTWARMING`=療癒/萌系, `SHONEN`=少年, `EASTERN_PALACE`=古代宮廷, `WEB_NOVEL`=小說
- `sortOrder` (`FilterOption`, default `UPDATE`): `MANA`=人氣排序, `LIKEIT`=愛心排序, `UPDATE`=最近更新

### Fetch

```
GET {baseUrl}/genres/{genreSlug}?sortOrder={sortOrder}&page={page}
```

`genreSlug` = genre code lowercased (e.g. `ACTION` → `action`, `ROMANCE_M` → `romance_m`).

### Parse

- List container: `ul.webtoon_list > li > a.link._genre_title_a[data-title-no]`
- **mangaId**: `data-title-no` value, plain (no `::` suffix — path unknown at this stage)
- **title**: `.info_text .title` text
- **author**: `.info_text .author` text
- **coverUrl**: `img` src within the card
- Pagination: no total-count math needed — if the page yields zero cards, `canLoadMore = false`; otherwise `true` with `nextPage = page + 1`.

## Search

### Fetch

```
GET {baseUrl}/search?keyword={urlEncode(keyword)}
```

No pagination support confirmed; only page 1 is fetched (`firstPage` default of 1 is fine, framework won't request page 2 unless `canLoadMore` says so — this source's `parseSearch` always returns `canLoadMore: false` equivalent, i.e. a plain `List<MangaSummary>` with no follow-up).

### Parse

- List container: `a.link._card_item[data-webtoon-type="WEBTOON"]` (cards without this attribute, or with `data-webtoon-type="CANVAS"`, are skipped)
- Same field extraction as discovery: title/author/cover from `.info_text .title` / `.info_text .author` / `img`
- **mangaId**: `data-title-no`, plain

## Manga Info

### Fetch

- If `_pathOf(mangaId)` resolves: `GET {baseUrl}/{path}/list?title_no={titleNo}`
- Else: `GET {baseUrl}/comic/{titleNo}/list?title_no={titleNo}` (follows 301 to canonical)

### Parse

- **title**: `h1.subj` text
- **coverUrl**: `.detail_header .thmb img` src
- **tags**: `h2.genre` text, whitespace-split
- **author**: `.author_area` text with the inner `<button class="_btnAuthorInfo">作家資訊</button>` text stripped out (clone node / remove child before reading `.text`, mirroring the dongmanmanhua author-parsing trick)
- **description**: best-effort from the detail page's summary block if present in the actual HTML sample (`/tmp/webtoons_detail.html`); if no reliable selector is found at implementation time, leave `null` rather than guess
- **status**: default `ongoing` unless an explicit completed/finale marker is found in the page; no aggressive regex-guessing beyond what's clearly present
- **chapters**: always `[]` (see Key Design Decision #8)
- Side effect: extract canonical path (from `<link rel="canonical">` or the final redirected URL) and write it into `_pathCache[titleNo]`; the mangaId echoed back to the caller (via the returned `MangaDetail`/subsequent calls) is the fully-encoded `"{titleNo}::{path}"` form once known.

## Chapter List

### Fetch

- Resolve path via `_pathOf(mangaId)`, falling back to `_resolvePath(titleNo)` if unknown.
- `GET {baseUrl}/{path}/list?title_no={titleNo}&page={page}` — **must** use the canonical path directly; the generic placeholder + `page` combination silently loses the page parameter after the 301.

### Parse

- List container: `ul#_listUl.detail_list > li._episodeItem[data-episode-no]`
- **id**: `data-episode-no`
- **title**: `span.subj span` text, fallback `"第{episodeNo}話"`
- Pagination: read current page from `div.paginate .on` and max page from `a[href*="page="]` hrefs to compute `canLoadMore`/`nextPage`
- Side effect: same canonical-path cache write as manga info, in case chapter list is hit before info (defensive; normal app flow goes info → chapter list first).

## Chapter Content (Viewer)

### Fetch

- Resolve path via `_pathOf(mangaId)`, falling back to `_resolvePath(titleNo)` if unknown — **no generic fallback URL is attempted** for the viewer itself, since the generic placeholder viewer path returns HTTP 500 on this site (unlike dongmanmanhua).
- `GET {baseUrl}/{path}/x/viewer?title_no={titleNo}&episode_no={chapterId}` (the `x` segment is a fixed placeholder; the server 301s to the real slugged URL — verified to work as long as the genre/title path segments are correct).

### Parse

- **title**: `<title>` text, split on `" - "`, take first segment
- **images**: `#_imageList img._images`, `data-url` attribute preferred, `src` fallback; skip any element whose resolved URL contains `bg_transparency`
- **headers** per image: `{'Referer': 'https://www.webtoons.com/'}` (CDN 403s without it)
- **Empty-image edge case**: if the filtered image list is empty, return `ChapterResult` with an empty `images` list rather than throwing (see Key Design Decision #9)
- `canLoadMore`: `false` (viewer is single-page per chapter)

### getChapterWebUrl

Override to return the same canonical viewer URL pattern (`{baseUrl}/{path}/x/viewer?title_no=...&episode_no=...`); using the `x` placeholder is acceptable here too since it 301s correctly.

## Headers

Default headers for all requests:
```dart
{
  'User-Agent': '<desktop Chrome UA constant>',
  'Referer': '$baseUrl/',
}
```

Image headers (chapter images and covers):
```dart
{'Referer': 'https://www.webtoons.com/'}
```

## HTML Parsing Strategy

Use the `html` package's CSS selectors (`document.querySelector` / `querySelectorAll`), consistent with `dongmanmanhua.dart`:
- `ul.webtoon_list`, `.info_text .title/.author` for listing cards (discovery + search)
- `h1.subj`, `.detail_header .thmb img`, `h2.genre`, `.author_area` for manga info
- `ul#_listUl.detail_list`, `li._episodeItem[data-episode-no]`, `div.paginate` for chapter list + pagination
- `#_imageList img._images` for viewer images
- `<link rel="canonical">` (or redirect `Location` header) for canonical genre-slug/title-slug extraction

## Edge Cases

1. **Canonical path unknown at request time**: any entry point other than "came from manga info/chapter list already fetched" (e.g. a cold viewer request) triggers one extra probe request via `_resolvePath`. Acceptable overhead since normal app navigation always visits the detail page first.
2. **Genre URL slug vs discovery genre code**: discovery filter values are the uppercase/underscore codes (`MARTIAL_ARTS`) used for the `/genres/{slug}` endpoint (lowercased); this is a *different* string space from the canonical detail-page path slug (`martial-arts`, hyphenated) — the two must never be interchanged directly.
3. **CANVAS search results**: explicitly excluded; only `data-webtoon-type="WEBTOON"` cards are parsed.
4. **Paywalled/APP-only latest chapters**: some titles show a "最新10話僅限APP" banner; when this results in zero parsed images, degrade to an empty chapter rather than erroring.
5. **Author text pollution**: `.author_area` contains a nested "作家資訊" button whose text must be excluded from the parsed author string.
6. **Redirect page-param loss**: never construct chapter-list or viewer URLs from the generic placeholder path when a `page`/pagination-sensitive parameter is involved — always resolve and use the canonical path first.
