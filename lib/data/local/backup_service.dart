import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'local_storage.dart';

/// Handles full app data backup and restore.
class BackupService {
  final LocalStorage _storage;

  static const _version = 1;
  static const _storageKeys = [
    'favorites',
    'reading_history',
    'settings',
    'update_status',
  ];

  BackupService({required LocalStorage storage}) : _storage = storage;

  /// Export all app data as a JSON string.
  Future<String> exportData() async {
    final data = <String, dynamic>{
      'version': _version,
      'timestamp': DateTime.now().toIso8601String(),
      'app': 'comic-reader',
    };

    for (final key in _storageKeys) {
      final value = await _storage.read(key);
      if (value != null) {
        data[key] = value;
      }
    }

    return jsonEncode(data);
  }

  /// Share the backup file via system share sheet.
  Future<void> shareBackup() async {
    final json = await exportData();

    if (kIsWeb) {
      throw UnsupportedError('Backup share not supported on web');
    }

    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/comic_reader_backup_$timestamp.json');
    await file.writeAsString(json);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Comic Reader Backup',
    );

    // Clean up temp file after sharing
    try {
      await file.delete();
    } catch (_) {}
  }

  /// Import data from a JSON string. Returns true on success.
  Future<bool> importData(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate
      if (data['app'] != 'comic-reader') return false;
      final version = data['version'] as int? ?? 0;
      if (version < 1) return false;

      // Restore each key
      for (final key in _storageKeys) {
        if (data.containsKey(key) && data[key] is Map<String, dynamic>) {
          await _storage.write(key, data[key] as Map<String, dynamic>);
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}
