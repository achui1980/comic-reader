import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/local/settings_store.dart';
import 'package:comic_reader/presentation/discovery/bloc/discovery_state.dart';

void main() {
  group('DiscoveryState.viewMode', () {
    test('defaults to grid', () {
      const state = DiscoveryState();
      expect(state.viewMode, DiscoveryViewMode.grid);
    });

    test('copyWith updates viewMode without affecting other fields', () {
      const state = DiscoveryState(sourceId: 'test');
      final updated = state.copyWith(viewMode: DiscoveryViewMode.list);
      expect(updated.viewMode, DiscoveryViewMode.list);
      expect(updated.sourceId, 'test');
    });

    test('two states with different viewMode are not equal', () {
      const a = DiscoveryState(viewMode: DiscoveryViewMode.grid);
      const b = DiscoveryState(viewMode: DiscoveryViewMode.list);
      expect(a == b, isFalse);
    });
  });
}
