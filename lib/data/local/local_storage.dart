import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Simple JSON file-based local storage.
/// Stores data as JSON files in the app's documents directory.
class LocalStorage {
  String? _basePath;

  Future<String> get _path async {
    _basePath ??= (await getApplicationDocumentsDirectory()).path;
    return _basePath!;
  }

  Future<File> _getFile(String name) async {
    final dir = await _path;
    return File('$dir/$name.json');
  }

  Future<Map<String, dynamic>?> read(String name) async {
    try {
      final file = await _getFile(name);
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> write(String name, Map<String, dynamic> data) async {
    final file = await _getFile(name);
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> delete(String name) async {
    final file = await _getFile(name);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
