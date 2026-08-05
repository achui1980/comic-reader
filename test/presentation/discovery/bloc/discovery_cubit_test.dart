import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/presentation/discovery/bloc/discovery_cubit.dart';
import 'package:comic_reader/presentation/discovery/bloc/discovery_state.dart';

class MockMangaRepository extends Mock implements MangaRepository {}

class MockSettingsStore extends Mock implements SettingsStore {}

void main() {
  late MockMangaRepository repository;
  late MockSettingsStore settingsStore;
  late SourceRegistry registry;

  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    repository = MockMangaRepository();
    settingsStore = MockSettingsStore();
    registry = SourceRegistry();
    when(() => settingsStore.load()).thenAnswer(
      (_) async => const AppSettings(discoveryViewMode: DiscoveryViewMode.grid),
    );
    when(() => settingsStore.save(any())).thenAnswer((_) async {});
  });

  DiscoveryCubit buildCubit() => DiscoveryCubit(
        repository: repository,
        registry: registry,
        settingsStore: settingsStore,
      );

  group('DiscoveryCubit.toggleViewMode', () {
    blocTest<DiscoveryCubit, DiscoveryState>(
      'toggles viewMode from grid to list and persists the change',
      build: buildCubit,
      act: (cubit) => cubit.toggleViewMode(),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.viewMode, 'viewMode', DiscoveryViewMode.list),
      ],
      verify: (_) {
        final captured =
            verify(() => settingsStore.save(captureAny())).captured;
        expect(
          (captured.single as AppSettings).discoveryViewMode,
          DiscoveryViewMode.list,
        );
      },
    );

    blocTest<DiscoveryCubit, DiscoveryState>(
      'toggles viewMode from list back to grid',
      build: buildCubit,
      seed: () => const DiscoveryState(viewMode: DiscoveryViewMode.list),
      act: (cubit) => cubit.toggleViewMode(),
      wait: const Duration(milliseconds: 10),
      expect: () => [
        isA<DiscoveryState>()
            .having((s) => s.viewMode, 'viewMode', DiscoveryViewMode.grid),
      ],
    );
  });
}
