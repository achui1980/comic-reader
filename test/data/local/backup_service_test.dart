import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/backup_service.dart';
import 'package:comic_reader/data/local/local_storage.dart';

class MockLocalStorage extends Mock implements LocalStorage {}

void main() {
  late MockLocalStorage storage;
  late BackupService service;

  setUp(() {
    storage = MockLocalStorage();
    service = BackupService(storage: storage);
  });

  group('BackupService.exportData', () {
    test('includes all expected storage keys when present', () async {
      when(() => storage.read(any())).thenAnswer((invocation) async {
        final key = invocation.positionalArguments.first as String;
        return {'value': key};
      });

      final json = await service.exportData();
      final data = jsonDecode(json) as Map<String, dynamic>;

      expect(data['app'], 'comic-reader');
      expect(data['version'], 1);
      expect(data['favorites'], {'value': 'favorites'});
      expect(data['reading_history'], {'value': 'reading_history'});
      expect(data['settings'], {'value': 'settings'});
      expect(data['update_status'], {'value': 'update_status'});
      expect(data['categories'], {'value': 'categories'});
      expect(data['ai_metadata'], {'value': 'ai_metadata'});
      expect(data['work_groups'], {'value': 'work_groups'});
    });

    test('never includes auth or download_tasks keys', () async {
      when(() => storage.read(any())).thenAnswer((invocation) async {
        final key = invocation.positionalArguments.first as String;
        // Even if these happened to be readable under the same
        // LocalStorage, the backup key list must not request them.
        return {'value': key};
      });

      final json = await service.exportData();
      final data = jsonDecode(json) as Map<String, dynamic>;

      expect(data.containsKey('auth'), isFalse);
      expect(data.containsKey('download_tasks'), isFalse);
      verifyNever(() => storage.read('auth'));
      verifyNever(() => storage.read('download_tasks'));
    });

    test('omits keys whose stored value is null', () async {
      when(() => storage.read(any())).thenAnswer((_) async => null);

      final json = await service.exportData();
      final data = jsonDecode(json) as Map<String, dynamic>;

      for (final key in [
        'favorites',
        'reading_history',
        'settings',
        'update_status',
        'categories',
        'ai_metadata',
        'work_groups',
      ]) {
        expect(data.containsKey(key), isFalse, reason: 'key "$key" should be omitted');
      }
    });
  });

  group('BackupService.importData', () {
    test('restores all new fields (categories/ai_metadata/work_groups)', () async {
      when(() => storage.write(any(), any())).thenAnswer((_) async {});

      final backup = jsonEncode({
        'app': 'comic-reader',
        'version': 1,
        'categories': {'ids': ['a', 'b']},
        'ai_metadata': {'foo': 'bar'},
        'work_groups': {'g1': ['m1', 'm2']},
      });

      final result = await service.importData(backup);

      expect(result, isTrue);
      verify(() => storage.write('categories', {'ids': ['a', 'b']})).called(1);
      verify(() => storage.write('ai_metadata', {'foo': 'bar'})).called(1);
      verify(() => storage.write('work_groups', {'g1': ['m1', 'm2']})).called(1);
    });

    test('never writes auth or download_tasks even if present in backup JSON',
        () async {
      when(() => storage.write(any(), any())).thenAnswer((_) async {});

      final backup = jsonEncode({
        'app': 'comic-reader',
        'version': 1,
        'auth': {'token': 'secret'},
        'download_tasks': {'q': []},
      });

      final result = await service.importData(backup);

      expect(result, isTrue);
      verifyNever(() => storage.write('auth', any()));
      verifyNever(() => storage.write('download_tasks', any()));
    });

    test('rejects backups with wrong app identifier', () async {
      final backup = jsonEncode({'app': 'other-app', 'version': 1});
      final result = await service.importData(backup);
      expect(result, isFalse);
    });

    test('rejects backups with version below 1', () async {
      final backup = jsonEncode({'app': 'comic-reader', 'version': 0});
      final result = await service.importData(backup);
      expect(result, isFalse);
    });

    test('returns false on malformed JSON', () async {
      final result = await service.importData('not valid json{{{');
      expect(result, isFalse);
    });
  });
}
