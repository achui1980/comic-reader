// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Web storage backend using browser localStorage.
class StorageBackend {
  Future<String?> readString(String name) async {
    return html.window.localStorage['comic_reader_$name'];
  }

  Future<void> writeString(String name, String content) async {
    html.window.localStorage['comic_reader_$name'] = content;
  }

  Future<void> deleteKey(String name) async {
    html.window.localStorage.remove('comic_reader_$name');
  }
}
