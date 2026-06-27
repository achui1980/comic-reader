# Hot Manga (热辣漫画) Data Source Design

## Overview

Add manga2026.com (热辣漫画/HotMangas) as a new `MangaSource` plugin. The site uses the same backend system as CopyManga (mangacopy.com) — same API structure, same AES encryption scheme, same data formats.

## Source Identity

- **ID:** `hot_manga`
- **Name:** 热辣漫画
- **Short Name:** HOT
- **File:** `lib/data/sources/hot_manga.dart`
- **Needs Proxy:** true (Cloudflare protected)
- **Needs Cloudflare:** true

## Domain Configuration

Two domains supported, user-selectable:
- `www.manga2026.com` (international, default)
- `www.manga2026.xyz` (mainland China alternate)

The active domain is stored as instance state. All URLs are constructed from the active domain.

Base URLs:
- Web: `https://{domain}`
- API: `https://{domain}/api/v3` (for search/discovery JSON APIs)
- Chapter list: `https://{domain}/comicdetail/{path_word}/chapters`
- Chapter content: APP API `https://api.{domain-base}/api/v3/comic/{path_word}/chapter2/{uuid}`

If the APP API is not available for this fork, fall back to HTML page parsing with AES decryption.

## Required Headers/Cookies

All requests:
- `Cookie: age=18; webp=1`
- `User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ...`
- `Referer: https://{domain}`

Image requests:
- `Referer: https://{domain}`
- `Accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8`

## API Endpoints & Implementation

### Discovery (prepareDiscoveryFetch / parseDiscovery)

**Request:**
```
GET /api/v3/comics?free_type=1&limit=21&offset={(page-1)*21}&ordering={sort}&theme={type}
Headers: platform=3, version=3.0.0, accept=application/json
```

**Response (JSON):**
```json
{
  "code": 200,
  "results": {
    "list": [
      {
        "path_word": "guichuyinxiong",
        "name": "鬼畜英雄",
        "cover": "https://sg.mangafunb.fun/g/guichuyinxiong/cover/...",
        "author": [{"name": "作者名"}],
        "datetime_updated": "2026-06-26"
      }
    ]
  }
}
```

**Filters:**
- type (题材): aiqing, huanlexiang, maoxian, qihuan, baihe, xiaoyuan, kehuan, dongfang, danmei, shenghuo, gedou, xuanyi, qita, rexue, hougong, dushi, wuxia, xuanhuan, etc.
- sort (排序): `-datetime_updated` (更新时间降序), `datetime_updated`, `-popular`, `popular`

### Search (prepareSearchFetch / parseSearch)

**Request:**
```
GET /api/v3/search/comic?platform=2&q={keyword}&limit=12&offset={(page-1)*12}
```

**Response:** Same structure as discovery.

### Manga Info (prepareMangaInfoFetch / parseMangaInfo)

**Request:**
```
GET /comic/{path_word}  (HTML page)
```

**Parse from HTML:**
- Title: `<h6 title="...">...</h6>` in `.comicParticulars-title-right`
- Cover: `<img>` with `data-src` in `.comicParticulars-left-img`
- Authors: `<a>` tags after `作者：`
- Status: text after `狀態：` (`連載中` → ongoing, `已完結` → completed)
- Tags: `<a>` tags in theme section
- Update time: text after `最後更新：`
- **Encryption key**: Extract from `var cc(?:x|z) = '...'` pattern (same as CopyManga)

### Chapter List (prepareChapterListFetch / parseChapterList)

**Request:**
```
GET /comicdetail/{path_word}/chapters
Headers: Referer: https://{domain}/comic/{path_word}
```

**Response (JSON with encrypted results):**
```json
{
  "code": 200,
  "results": "<encrypted_string>"
}
```

**Decryption:** Use existing `aesDecrypt(encrypted, key)` where:
- `encrypted` = the `results` string (first 16 chars = IV, rest = hex ciphertext)
- `key` = extracted from manga info page HTML (16-char UTF-8 string)
- Default key fallback: same pattern as CopyManga

**Decrypted structure:**
```json
{
  "build": {"path_word": "guichuyinxiong"},
  "groups": {
    "default": {
      "path_word": "default",
      "name": "默认",
      "chapters": [
        {"id": "uuid", "name": "第1话", "type": 1, "datetime_created": "..."}
      ]
    }
  }
}
```

### Chapter Images (prepareChapterFetch / parseChapter)

**Strategy:** Try APP API first, fall back to HTML page decryption.

**Option A - APP API (preferred):**
```
GET /api/v3/comic/{path_word}/chapter2/{uuid}
Headers: HMAC-signed headers (same as CopyManga APP API)
```

Response contains `results.chapter.contents[].url` and `results.chapter.words[]` for reordering.

**Option B - HTML page fallback:**
```
GET /comic/{path_word}/chapter/{uuid}
```

Parse from HTML:
- Key: `<div class="disPass" contentKey="op0zzpvv.nmn.00p"></div>` (16 chars, used as AES key)
- Data: `<div class="disData" contentKey="<encrypted>"></div>`
- Also check: `var contentKey = '<encrypted>'` in script tags

Decrypt with `aesDecrypt(data, key)` → JSON array of image objects with `url` field.

**Image URL processing:**
- Replace `.c{N}x.` patterns with `.c1500x.` for high quality (same as CopyManga)

## Image CDN

Pattern: `https://s{first_letter}.mangafunb.fun/{first_letter}/{path_word}/cover/{timestamp}.{ext}.{size}.jpg`

Sizes observed: `328x422` (thumbnails), full size without suffix.

## Error Handling

- If `code != 200`, return empty results
- If decryption fails, return empty chapter list (key may have rotated)
- Cloudflare challenge: `needsCloudflare = true` enables WebView cookie extraction flow

## Dependencies

- Existing: `crypto_utils.dart` (`aesDecrypt` function)
- Existing: `crypto` package (for HMAC if APP API is used)
- No new dependencies required

## Registration

Add to `lib/app/di/injection.dart`:
```dart
import 'package:comic_reader/data/sources/hot_manga.dart';
registry.register(HotManga());
```

## Implementation Notes

- The site shares infrastructure with CopyManga, so the same `aesDecrypt` utility works directly
- Key extraction pattern (`var ccx/ccz = '...'`) and content key pattern (`imageData contentkey`/`disData contentKey`) need both CopyManga-style and manga2026-style regex support
- Domain switching can be a simple setter that rebuilds the base URL strings
- APP API signature uses the same HMAC-SHA256 scheme as CopyManga (base64-decoded secret + timestamp)
- The APP API secret and version may differ from CopyManga — if it fails, fall back to HTML parsing exclusively
