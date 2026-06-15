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

  Future<void> writeString(String name, String content) async {
    final dir = await _path;
    final file = File('$dir/$name.json');
    await file.writeAsString(content);
  }

  Future<void> deleteKey(String name) async {
    final dir = await _path;
    final file = File('$dir/$name.json');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
