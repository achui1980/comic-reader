import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/local/settings_store.dart';

void main() {
  group('AppSettings.discoveryViewMode', () {
    test('defaults to grid', () {
      const settings = AppSettings();
      expect(settings.discoveryViewMode, DiscoveryViewMode.grid);
    });

    test('copyWith updates discoveryViewMode', () {
      const settings = AppSettings();
      final updated = settings.copyWith(
        discoveryViewMode: DiscoveryViewMode.list,
      );
      expect(updated.discoveryViewMode, DiscoveryViewMode.list);
    });

    test('toJson/fromJson round-trip preserves discoveryViewMode', () {
      const settings = AppSettings(discoveryViewMode: DiscoveryViewMode.list);
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.discoveryViewMode, DiscoveryViewMode.list);
    });

    test('fromJson defaults to grid when field is missing', () {
      final restored = AppSettings.fromJson(<String, dynamic>{});
      expect(restored.discoveryViewMode, DiscoveryViewMode.grid);
    });
  });

  group('AppSettings.mangaTranslationEnabled', () {
    test('defaults to false', () {
      const settings = AppSettings();
      expect(settings.mangaTranslationEnabled, isFalse);
    });

    test('copyWith updates mangaTranslationEnabled', () {
      const settings = AppSettings();
      final updated = settings.copyWith(mangaTranslationEnabled: true);
      expect(updated.mangaTranslationEnabled, isTrue);
    });

    test('toJson/fromJson round-trip preserves mangaTranslationEnabled', () {
      const settings = AppSettings(mangaTranslationEnabled: true);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.mangaTranslationEnabled, isTrue);
    });

    test('fromJson defaults to false when field is missing', () {
      final restored = AppSettings.fromJson(<String, dynamic>{});
      expect(restored.mangaTranslationEnabled, isFalse);
    });
  });
}
