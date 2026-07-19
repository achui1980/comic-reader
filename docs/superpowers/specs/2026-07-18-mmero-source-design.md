# Mmero Source Integration Design

## Goal

Add `mmero.com` as an adult source in the existing comic reader. Users can
browse its public catalog, search comics, view comic details and embedded
chapters, and read chapter images in the app's existing reader.

## Scope

- Add one `MmeroSource` implementation under `lib/data/sources/`.
- Register the source in manual dependency injection.
- Reuse existing discovery, detail, reader, networking, and error UI.
- Add focused unit tests for request construction and response parsing.

No custom screens, authentication, cookie handling, WebView fetching, or
source-specific retries are included.

## Source Configuration

- Source ID: `mmero`.
- Base site URL: `https://mmero.com`.
- Adult flag: enabled.
- Cover URL template: `https://cover.2thewash.com/comic/{id}/cover.jpg`.
- Chapter image URL template:
  `https://c2.2thewash.com/comic/{comicId}/{chapterNumber}/{pageNumber}.jpg`.

The site and CDN constants remain local to the source so a future domain
change has a small, isolated edit surface.

## API Integration

All source methods remain pure prepare/parse methods. `MangaRepositoryImpl`
continues to execute `FetchConfig` requests and pass responses to the source.

| Capability | Request | Mapping |
| --- | --- | --- |
| Catalog / filtered discovery | `GET /api/comic/items` with `pageNo`, `pageSize=30`, optional `channel` and `isEnded` | Paginated `items` become manga summaries. |
| Search | `GET /api/comic/search` with `keyword`, `pageNo`, `pageSize=30`, `type=1` | Same paginated mapping. |
| Comic detail | `POST /api/comic/content` with JSON `{"id": comicId}` | Detail metadata, tags, and embedded chapters become `MangaDetail`. |
| Chapter read | `POST /api/comic/chapter` with JSON `{"id": comicId, "chapter": chapterNumber}` | `pages` generates one ordered image per page. |

Detail responses contain the complete chapter list, so the source does not
make a separate chapter-list request. Each `ChapterItem.id` is the chapter
number; the source-plugin contract passes the comic ID separately to the
chapter request, so no composite ID or cached page state is needed.

## Discovery And Pagination

The source exposes the site's catalog through the existing discovery UI, with
static filters for channel and completion status. It sends the requested page
number as `pageNo` and uses the application's existing list pagination
semantics: a returned empty list ends pagination. The API's `page`, `size`,
and `total` fields are not surfaced because the source-plugin contract returns
only `List<MangaSummary>`.

## Reader Behavior

The chapter endpoint supplies the authoritative page count. The parser creates
`ChapterImage` entries for every integer page from `1` through `pages`, in
order, using the direct CDN template. It does not replicate the web site's
Nuxt base64-to-Blob fallback: verified raw JPEG CDN responses work directly in
the app's image pipeline.

## Failure Behavior

Normal repository/network errors and image failures propagate through existing
framework behavior. The source does not add undocumented headers, cookies,
Cloudflare workarounds, or custom retry behavior. A malformed or missing page
count yields no fabricated image URLs.

## Verification

Focused tests cover:

- Catalog/search/detail/chapter `FetchConfig` URL, query, method, and JSON
  body construction.
- Summary and detail mapping, including generated cover URLs and embedded
  chapter items.
- Chapter response parsing, including ordered URLs from page `1` through the
  declared final page.

Verification runs the focused source test, focused static analysis, and
`graphify update .` after code changes.
