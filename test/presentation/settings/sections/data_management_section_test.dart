import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:comic_reader/data/local/favorites_store.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/settings/bloc/settings_cubit.dart';
import 'package:comic_reader/presentation/settings/bloc/settings_state.dart';
import 'package:comic_reader/presentation/settings/sections/data_management_section.dart';

class MockSettingsStore extends Mock implements SettingsStore {}

class MockLocalStorage extends Mock implements LocalStorage {}

class MockSourceRegistry extends Mock implements SourceRegistry {}

class MockFavoritesStore extends Mock implements FavoritesStore {}

/// `flutter test` runs on the host VM (`kIsWeb` is always false there), so
/// `Platform.isMacOS`/`isWindows` reflect the actual machine running the
/// suite. The desktop-only tile's tests are skipped on other platforms
/// (e.g. Linux CI) via this same condition the widget itself uses.
bool get _isDesktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows);

void main() {
  late SettingsCubit cubit;

  setUp(() {
    cubit = SettingsCubit(
      settingsStore: MockSettingsStore(),
      localStorage: MockLocalStorage(),
      sourceRegistry: MockSourceRegistry(),
      favoritesStore: MockFavoritesStore(),
    );
  });

  Widget host(SettingsState state) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider<SettingsCubit>.value(
              value: cubit,
              child: DataManagementSection(state: state),
            ),
          ),
        ),
      );

  group('DataManagementSection download directory tile', () {
    testWidgets(
      'shown on macOS/Windows with "默认位置" subtitle when unset',
      (tester) async {
        await tester.pumpWidget(host(const SettingsState(isLoading: false)));

        expect(find.text('下载存储位置'), findsOneWidget);
        expect(find.text('默认位置'), findsOneWidget);
      },
      skip: !_isDesktop,
    );

    testWidgets(
      'shows the configured custom path as its subtitle',
      (tester) async {
        const settings = AppSettings(downloadDirectory: '/custom/path');
        await tester.pumpWidget(
          host(const SettingsState(settings: settings, isLoading: false)),
        );

        expect(find.text('下载存储位置'), findsOneWidget);
        expect(find.text('/custom/path'), findsOneWidget);
        expect(find.text('默认位置'), findsNothing);
      },
      skip: !_isDesktop,
    );
  });
}
