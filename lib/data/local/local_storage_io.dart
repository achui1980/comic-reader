import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Native (iOS/Android/macOS/Linux/Windows) file-based storage backend.
class StorageBackend {
  String? _basePath;

  Future<String> get _path async {
    _basePath ??= (await getApplicationDocumentsDirectory()).path;
    return _basePath!;
  }

  Future<String?> readString(String name) async {
    final dir = await _path;
    final file = File('$dir/$name.json');
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  /// Writes [content] to the storage file for [name] atomically.
  ///
  /// Writes to a temporary sibling file first (flushing to disk), then
  /// renames it over the destination. Rename within the same directory is
  /// atomic on the mainstream filesystems this app targets, so a crash or
  /// kill mid-write can never leave the destination file truncated or
  /// empty — it either has the old content or the new content.
  Future<void> writeString(String name, String content) async {
    final dir = await _path;
    final file = File('$dir/$name.json');
    final tmpFile = File('$dir/$name.json.tmp');
    final sink = tmpFile.openWrite();
    sink.write(content);
    await sink.flush();
    await sink.close();
    await tmpFile.rename(file.path);
  }

  Future<void> deleteKey(String name) async {
    final dir = await _path;
    final file = File('$dir/$name.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
