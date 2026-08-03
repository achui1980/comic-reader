import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/remote/http_client.dart';

/// Information about an available app update, derived from the latest
/// published GitHub Release.
class AppUpdateInfo {
  final String version;
  final String htmlUrl;
  final String releaseName;
  final String changelog;

  const AppUpdateInfo({
    required this.version,
    required this.htmlUrl,
    required this.releaseName,
    required this.changelog,
  });
}

/// Checks GitHub Releases for a newer app version than the one currently
/// installed, and remembers which version the user chose to skip.
///
/// This only applies to platforms that receive build artifacts from the
/// project's GitHub Releases (macOS/Windows/Android). iOS and Web builds are
/// not distributed there, so [checkForUpdate] always returns null on those
/// platforms.
class AppUpdateService {
  static const String _repoApiUrl =
      'https://api.github.com/repos/achui1980/comic-reader/releases/latest';
  static const String _storageKey = 'app_update';

  final HttpClient httpClient;
  final LocalStorage localStorage;

  AppUpdateService({required this.httpClient, required this.localStorage});

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isAndroid;
  }

  /// Returns update info if a newer version is available, or null if the
  /// app is already up to date, the platform isn't supported, or (unless
  /// [ignoreSkipped] is true) the user previously chose to skip this
  /// version.
  ///
  /// Network or parsing errors are allowed to propagate to the caller.
  Future<AppUpdateInfo?> checkForUpdate({bool ignoreSkipped = false}) async {
    if (!_isSupportedPlatform) return null;

    final response = await httpClient.execute(
      const FetchConfig(
        url: _repoApiUrl,
        headers: {'User-Agent': 'ComicReader-App'},
      ),
    );

    final data = _asMap(response.data);
    if (data == null) return null;

    final tagName = data['tag_name'] as String?;
    if (tagName == null || tagName.isEmpty) return null;

    final remoteVersion = _stripTag(tagName);
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    if (!_isNewer(remoteVersion, currentVersion)) return null;

    if (!ignoreSkipped) {
      final skipped = await _skippedVersion();
      if (skipped == remoteVersion) return null;
    }

    return AppUpdateInfo(
      version: remoteVersion,
      htmlUrl: (data['html_url'] as String?) ?? '',
      releaseName: (data['name'] as String?) ?? tagName,
      changelog: (data['body'] as String?) ?? '',
    );
  }

  /// Persists [version] so future silent startup checks won't re-prompt for
  /// it. Manual checks (`ignoreSkipped: true`) still surface it.
  Future<void> skipVersion(String version) async {
    await localStorage.write(_storageKey, {'skippedVersion': version});
  }

  Future<String?> _skippedVersion() async {
    final stored = await localStorage.read(_storageKey);
    return stored?['skippedVersion'] as String?;
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Strips a leading 'v' and any '-build.N' style suffix from a release
  /// tag, e.g. 'v1.3.0-build.2' -> '1.3.0'.
  String _stripTag(String tagName) {
    var version = tagName.trim();
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    final dashIndex = version.indexOf('-');
    if (dashIndex != -1) {
      version = version.substring(0, dashIndex);
    }
    return version;
  }

  bool _isNewer(String remote, String current) {
    final remoteParts = _versionParts(remote);
    final currentParts = _versionParts(current);
    for (var i = 0; i < 3; i++) {
      if (remoteParts[i] != currentParts[i]) {
        return remoteParts[i] > currentParts[i];
      }
    }
    return false;
  }

  List<int> _versionParts(String version) {
    final segments = version.split('.');
    return List.generate(3, (i) {
      if (i >= segments.length) return 0;
      return int.tryParse(segments[i]) ?? 0;
    });
  }
}
