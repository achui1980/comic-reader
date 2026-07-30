import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

// Conditional imports for platform-specific file I/O
import 'local_storage_io.dart' if (dart.library.html) 'local_storage_web.dart'
    as platform;

/// Simple JSON local storage.
/// Uses file system on native, localStorage on web.
class LocalStorage {
  final platform.StorageBackend _backend = platform.StorageBackend();

  Future<Map<String, dynamic>?> read(String name) async {
    try {
      final content = await _backend.readString(name);
      if (content != null) {
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[LocalStorage] Failed to read "$name": $e');
    }
    return null;
  }

  Future<void> write(String name, Map<String, dynamic> data) async {
    await _backend.writeString(name, jsonEncode(data));
  }

  Future<void> delete(String name) async {
    await _backend.deleteKey(name);
  }
}
