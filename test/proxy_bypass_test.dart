import 'package:comic_reader/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// Importing `main.dart` does not execute `main()`, so this test does not need
/// `configureDependencies()` (unlike `test/widget_test.dart`, which pumps the
/// whole app and fails for that reason).
void main() {
  group('MyHttpOverrides.shouldBypassProxy', () {
    test('bypasses 51manga and every subdomain the source actually uses', () {
      // The source talks to m. for pages and www. for the Referer/browser URL.
      expect(MyHttpOverrides.shouldBypassProxy('51manga.com'), isTrue);
      expect(MyHttpOverrides.shouldBypassProxy('m.51manga.com'), isTrue);
      expect(MyHttpOverrides.shouldBypassProxy('www.51manga.com'), isTrue);
    });

    test('bypasses the image CDN so pages and images share one exit IP', () {
      // A split exit is more likely to trip the CDN's anti-hotlink Referer
      // check than a direct CDN fetch is to be blocked.
      expect(MyHttpOverrides.shouldBypassProxy('img1.baipiaoguai.org'), isTrue);
      expect(MyHttpOverrides.shouldBypassProxy('baipiaoguai.org'), isTrue);
    });

    test('is case-insensitive, since hostnames are', () {
      expect(MyHttpOverrides.shouldBypassProxy('M.51Manga.COM'), isTrue);
    });

    test('does not bypass unrelated hosts', () {
      expect(MyHttpOverrides.shouldBypassProxy('example.com'), isFalse);
      expect(MyHttpOverrides.shouldBypassProxy('copymanga.site'), isFalse);
    });

    test('anchors the suffix on a dot so a lookalike domain is not bypassed', () {
      // The bug a bare `endsWith` would have: an attacker- or typo-registered
      // domain silently inheriting the bypass and leaking the real IP.
      expect(MyHttpOverrides.shouldBypassProxy('not51manga.com'), isFalse);
      expect(MyHttpOverrides.shouldBypassProxy('evil-51manga.com'), isFalse);
      // ...and the reverse direction: a matching prefix is not a match either.
      expect(MyHttpOverrides.shouldBypassProxy('51manga.com.evil.net'), isFalse);
    });
  });
}
