# Hot Manga (热辣漫画) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manga2026.com as a new MangaSource plugin called "热辣漫画"

**Architecture:** Single-file data source extending MangaSource, reusing existing `aesDecrypt` from crypto_utils.dart. Same backend as CopyManga with different domain/CDN.

**Tech Stack:** Dart/Flutter, AES-CBC encryption (existing `encrypt` package), HMAC-SHA256 (existing `crypto` package)

---

### Task 1: Create hot_manga.dart source file

**Files:**
- Create: `lib/data/sources/hot_manga.dart`

- [ ] **Step 1: Create the source file with full implementation**

See design spec for API details. The implementation mirrors `copy_manga.dart` with:
- Dual domain support (manga2026.com / manga2026.xyz)
- Discovery via `/api/v3/comics` JSON API
- Search via `/api/v3/search/comic` JSON API  
- Manga info parsed from HTML page
- Chapter list from `/comicdetail/{path_word}/chapters` with AES decryption
- Chapter images via APP API with HMAC auth, HTML fallback
- Image URL high-quality replacement (`.c{N}x.` → `.c1500x.`)

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/data/sources/hot_manga.dart`
Expected: No issues found

### Task 2: Register in dependency injection

**Files:**
- Modify: `lib/app/di/injection.dart`

- [ ] **Step 1: Add import and registration**

Add import:
```dart
import 'package:comic_reader/data/sources/hot_manga.dart';
```

Add registration after the last `registry.register(...)` call:
```dart
registry.register(HotManga());
```

- [ ] **Step 2: Run full static analysis**

Run: `flutter analyze`
Expected: No issues found

### Task 3: Verify build

- [ ] **Step 1: Run flutter build to ensure no compile errors**

Run: `flutter build web --no-tree-shake-icons` (or `flutter analyze` for quick check)
Expected: Build succeeds
