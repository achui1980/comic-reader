# Manhuaren (漫画人) Data Source Design

## Overview

Implement a new data source for manhuaren.com using their internal mobile API (`mangaapi.manhuaren.com`). This source uses JSON API with GSN signature authentication rather than HTML scraping.

## Decisions

- **API approach**: Full mobile API with RSA encryption + anonymous user creation + GSN signing
- **Auth persistence**: Memory-only cache; re-authenticate on each app restart
- **Discovery filters**: Full filtering (genre, region, status, sort)
- **Chapter list**: Embedded in manga detail response (prepareChapterListFetch returns null)

## Architecture

### File Structure

- `lib/data/sources/manhuaren.dart` — single file containing ManhuarenSource class

### Authentication Flow

```
First request → check needsAuth → yes →
  1. Generate random IMEI (14 digits + Luhn checksum)
  2. RSA-encrypt device info JSON with public key
  3. POST /v1/user/createAnonyUser2 with encrypted body
  4. Parse response → cache userId, authScheme, authParameter
  → proceed with original request
```

Memory-cached fields:
- `_userId`: String
- `_authScheme`: String (e.g. "Bearer")
- `_authParameter`: String (token value)
- `_imei`: String (generated once per session)
- `_lastUsedTime`: int (timestamp for common params)

### Repository Integration

Add ManhuarenSource pre-request auth check in `manga_repository_impl.dart`, following the Hitomi gg.js pattern:

```dart
// Before any ManhuarenSource request:
if (source is ManhuarenSource && source.needsAuth) {
  final authConfig = source.prepareAuthFetch();
  final authMerged = _mergeHeaders(authConfig, source);
  final authResponse = await _httpClient.execute(authMerged);
  source.parseAuthResponse(authResponse.data);
}
```

### GSN Signature Algorithm

Every request requires a `gsn` query parameter computed as:

```
gsn = MD5(salt + METHOD + sorted(params.keys).map(k => k + customUrlEncode(params[k])).join('') + salt)
```

- Salt: `"4e0a48e1c0b54041bce9c8f0e036124d"`
- For POST requests, include `"body"` key in params map
- Custom URL encoding: standard percent-encoding but `+` → `%20`, `%7E` → `~`, `*` → `%2A`

### Common Query Parameters

Every API request includes these base parameters:

```
gsm=md5, gft=json, gak=android_manhuaren2, gat=,
gui={userId}, gts={timestamp}, gut=0, gem=1, gaui={userId},
gln=, gcy=US, gle=zh, gcl=dm5, gos=1, gov=33_13, gav=7.0.1,
gdi={imei}, gfcl=dm5, gfut={lastUsedTime}, glut={lastUsedTime},
gpt=com.mhr.mangamini, gciso=us, glot=, glat=, gflot=, gflat=,
glbsaut=0, gac=, gcut=GMT+8, gfcc=, gflg=, glcn=, glcc=, gflcc=
```

### Request Headers

```
User-Agent: Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TP1A.220624.021)
X-Yq-Yqci: {"le":"zh","os":"1","ov":"33_13","av":"7.0.1"}
X-Yq-Key: {userId}
yq_is_anonymous: 1
x-request-id: {uuid}
Authorization: {authScheme} {authParameter}
```

## API Endpoints

| Method Pair | HTTP | Endpoint | Key Params |
|---|---|---|---|
| Discovery | GET | `/v2/manga/getCategoryMangas` | subCategoryType, subCategoryId, start, limit, sort |
| Search | GET | `/v1/search/getSearchManga` | keywords, start, limit |
| MangaInfo | GET | `/v1/manga/getDetail` | mangaId |
| ChapterList | null | (embedded in detail) | — |
| Chapter | GET | `/v1/manga/getRead` | mangaSectionId |

## Discovery Filters

### Genre (subCategoryId)
0=全部, 1=热血, 2=恋爱, 3=校园, 4=搞笑, 5=格斗, 6=冒险, 7=科幻, 8=魔幻, 9=神鬼, 10=悬疑, 11=唯美, 12=惊悚, 13=职场, 14=萌系, 15=治愈, 16=历史, 17=美食, 18=同人, 19=运动, 20=励志, 21=生活, 22=战争, 23=长条

### Region (subCategoryType)
0=全部, 1=日漫, 2=韩漫, 3=国漫

### Status (status filter via subCategoryType second dimension)
0=全部, 1=连载中, 2=已完结

### Sort
0=热门, 1=更新, 2=新作

## Response Parsing

### Discovery / Search → MangaSummary

JSON field mapping:
- `mangaId` → id (as string)
- `mangaName` → title
- `mangaCoverimageUrl` → coverUrl
- `mangaAuthor` → author
- `mangaIsOver` → (0=ongoing, 1=completed)
- `mangaNewestContent` → latestChapter

### MangaInfo → MangaDetail

JSON field mapping:
- `mangaId` → id
- `mangaName` → title
- `mangaCoverimageUrl` → coverUrl
- `mangaDescription` → description
- `mangaAuthor` → author
- `mangaTheme` → tags (comma-separated string → list)
- `mangaIsOver` → status
- `mangaSections` → chapters (array of section objects)

Chapter sections structure:
- Each section has `sectionId`, `sectionName`, `sectionTitle`
- Map to ChapterItem: sectionId → id, sectionTitle/sectionName → title

### Chapter → ChapterResult

JSON field mapping:
- `mangaSectionImages` → images array
- Each image: `imageUrl` → ChapterImage.url
- Images returned as complete list (no pagination expected from API)

## RSA Encryption (for auth)

Public key (PKCS#1 format, base64):
```
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmFCg289dTws27v8GtqIffkP4zgFR+MYIuUIeVO5AGiBV0rfpRh5gg7i8RrT12E9j6XwKoe3xJz1khDnPc65P5f7CJcNJ9A8bj7Al5K4jYGxz+4Q+n0YzSllXPit/Vz/iW5jFdlP6CTIgUVwvIoGEL2sS4cqqqSpCDKHSeiXh9CtMsktc6YyrSN+8mQbBvoSSew18r/vC07iQiaYkClcs7jIPq9tuilL//2uR9kWn5jsp8zHKVjmXuLtHDhM9lObZGCVJwdlN2KDKTh276u/pzQ1s5u8z/ARtK26N8e5w8mNlGcHcHfwyhjfEQurvrnkqYH37+12U3jGk5YNHGyOPcwIDAQAB
```

Device info JSON to encrypt:
```json
{
  "osType": "1",
  "osVersion": "33",
  "imei": "{imei}",
  "deviceName": "Pixel 7",
  "deviceModel": "Pixel 7"
}
```

## IMEI Generation

Generate a valid 15-digit IMEI:
1. Generate 14 random digits
2. Compute Luhn checksum digit
3. Append checksum as 15th digit

## Error Handling

- Auth failure (401/token expired): Clear cached auth, retry once with fresh auth
- Rate limiting: Respect batchDelay (default 1500ms)
- Network errors: Let framework handle via standard DioException flow

## Dependencies

Dart packages needed (check if already in pubspec.yaml):
- `crypto` — for MD5 hash
- `pointycastle` or `encrypt` — for RSA encryption
- `uuid` — for x-request-id header generation
