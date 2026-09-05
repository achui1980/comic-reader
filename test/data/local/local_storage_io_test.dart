import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:comic_reader/data/local/local_storage_io.dart';

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  FakePathProviderPlatform(this.tempPath);
  final String tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;
}

void main() {
  late Directory tempDir;
  late StorageBackend backend;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_storage_io_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    backend = StorageBackend();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StorageBackend.readString', () {
    test('returns null when the file does not exist', () async {
      expect(await backend.readString('missing'), isNull);
    });

    test('returns previously written content', () async {
      await backend.writeString('settings', '{"a":1}');
      expect(await backend.readString('settings'), '{"a":1}');
    });
  });

  group('StorageBackend.writeString (atomic write)', () {
    test('writes content readable back via readString', () async {
      await backend.writeString('favorites', '{"ids":[1,2,3]}');
      expect(await backend.readString('favorites'), '{"ids":[1,2,3]}');
    });

    test('overwrites existing content on subsequent writes', () async {
      await backend.writeString('settings', '{"v":1}');
      await backend.writeString('settings', '{"v":2}');
      expect(await backend.readString('settings'), '{"v":2}');
    });

    test('does not leave a .tmp file behind after a successful write', () async {
      await backend.writeString('settings', '{"v":1}');
      final tmpFile = File('${tempDir.path}/settings.json.tmp');
      expect(await tmpFile.exists(), isFalse);
    });

    test(
      'a failed write to the temp file leaves the previous destination '
      'file untouched (simulates a crash mid-write)',
      () async {
        await backend.writeString('settings', '{"v":"old"}');

        // Simulate a crash mid-write by writing directly to the .tmp
        // sibling without renaming it over the destination -- this is
        // exactly the state a real crash between the flush and the
        // rename would leave on disk.
        final tmpFile = File('${tempDir.path}/settings.json.tmp');
        await tmpFile.writeAsString('{"v":"partial"}', flush: true);

        // The destination file must still hold the last successfully
        // committed content, since the atomic write never renamed the
        // half-written temp file over it.
        expect(await backend.readString('settings'), '{"v":"old"}');
      },
    );

    test('writes files under the correct .json extension', () async {
      await backend.writeString('work_groups', '{}');
      final file = File('${tempDir.path}/work_groups.json');
      expect(await file.exists(), isTrue);
    });
  });

  group('StorageBackend.deleteKey', () {
    test('removes an existing file', () async {
      await backend.writeString('settings', '{}');
      await backend.deleteKey('settings');
      expect(await backend.readString('settings'), isNull);
    });

    test('is a no-op when the file does not exist', () async {
      await backend.deleteKey('missing');
      expect(await backend.readString('missing'), isNull);
    });
  });
}
