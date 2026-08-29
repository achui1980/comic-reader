import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/chapter_cache_service.dart';
import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/settings/bloc/settings_cubit.dart';

class MockSettingsStore extends Mock implements SettingsStore {}

class MockLocalStorage extends Mock implements LocalStorage {}

class MockSourceRegistry extends Mock implements SourceRegistry {}

class MockFavoritesStore extends Mock implements FavoritesStore {}

void main() {
  // `setDownloadDirectory` now (Task 12) invokes a MethodChannel on macOS
  // to persist a security-scoped bookmark; MethodChannel access requires
  // the services binding to be initialized in a plain `flutter test` VM.
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookmarkChannel = MethodChannel(
    'com.comicreader.comicReader/download_bookmark',
  );

  late MockSettingsStore settingsStore;
  late SettingsCubit cubit;

  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    settingsStore = MockSettingsStore();
    when(() => settingsStore.save(any())).thenAnswer((_) async {});
    cubit = SettingsCubit(
      settingsStore: settingsStore,
      localStorage: MockLocalStorage(),
      sourceRegistry: MockSourceRegistry(),
      favoritesStore: MockFavoritesStore(),
    );
    // This test suite runs on a real macOS host, so `Platform.isMacOS` is
    // true and `setDownloadDirectory` will attempt the native bookmark
    // channel for real. Stub it out so these Cubit-level tests aren't
    // coupled to (or broken by) the native bridge's behavior.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bookmarkChannel, (call) async => true);
  });

  tearDown(() {
    // Reset the static field so other test files aren't affected by this
    // process-wide leakage between test cases.
    ChapterCacheService.customDownloadDirectory = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bookmarkChannel, null);
  });

  group('SettingsCubit.setDownloadDirectory', () {
    test('updates state.settings.downloadDirectory and persists it',
        () async {
      await cubit.setDownloadDirectory('/custom/path');

      expect(cubit.state.settings.downloadDirectory, '/custom/path');
      verify(() => settingsStore.save(any())).called(1);
    });

    test('syncs ChapterCacheService.customDownloadDirectory', () async {
      await cubit.setDownloadDirectory('/custom/path');

      expect(ChapterCacheService.customDownloadDirectory, '/custom/path');
    });

    test('passing null clears both state.settings and the static field',
        () async {
      await cubit.setDownloadDirectory('/custom/path');
      await cubit.setDownloadDirectory(null);

      // AppSettings.copyWith uses an `Object? = _unset` sentinel for
      // downloadDirectory (unlike the plain `x ?? this.x` used by every
      // other, non-nullable field) specifically so an explicit null clears
      // it back to the platform default instead of being ignored.
      expect(cubit.state.settings.downloadDirectory, isNull);
      expect(ChapterCacheService.customDownloadDirectory, isNull);
    });
  });
}
