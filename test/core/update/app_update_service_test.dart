import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:comic_reader/core/models/fetch_config.dart';
import 'package:comic_reader/core/update/app_update_service.dart';
import 'package:comic_reader/data/local/local_storage.dart';
import 'package:comic_reader/data/remote/http_client.dart';

class MockHttpClient extends Mock implements HttpClient {}

class MockLocalStorage extends Mock implements LocalStorage {}

Response<dynamic> _okResponse(dynamic data) =>
    Response<dynamic>(requestOptions: RequestOptions(path: ''), data: data);

Map<String, dynamic> _releaseJson({
  required String tagName,
  String htmlUrl = 'https://github.com/achui1980/comic-reader/releases/tag/x',
  String body = 'changelog',
  String? name,
}) {
  return {
    'tag_name': tagName,
    'html_url': htmlUrl,
    'body': body,
    'name': name ?? tagName,
  };
}

void main() {
  setUpAll(() {
    registerFallbackValue(const FetchConfig(url: ''));
    // Current installed app version used as the comparison baseline.
    PackageInfo.setMockInitialValues(
      appName: 'Comic Reader',
      packageName: 'com.example.comic_reader',
      version: '1.2.1',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  late MockHttpClient httpClient;
  late MockLocalStorage localStorage;
  late AppUpdateService service;

  setUp(() {
    httpClient = MockHttpClient();
    localStorage = MockLocalStorage();
    service = AppUpdateService(
      httpClient: httpClient,
      localStorage: localStorage,
    );
    // Default: nothing skipped yet.
    when(() => localStorage.read(any())).thenAnswer((_) async => null);
    when(
      () => localStorage.write(any(), any()),
    ).thenAnswer((_) async {});
  });

  test('detects a newer tag_name as an available update', () async {
    when(() => httpClient.execute(any())).thenAnswer(
      (_) async => _okResponse(_releaseJson(tagName: 'v1.3.0')),
    );

    final info = await service.checkForUpdate();

    expect(info, isNotNull);
    expect(info!.version, '1.3.0');
  });

  test('returns null when remote tag is same or older', () async {
    when(() => httpClient.execute(any())).thenAnswer(
      (_) async => _okResponse(_releaseJson(tagName: 'v1.2.1')),
    );

    final info = await service.checkForUpdate();

    expect(info, isNull);
  });

  test('does not mis-detect a -build.N suffix as newer', () async {
    when(() => httpClient.execute(any())).thenAnswer(
      (_) async => _okResponse(_releaseJson(tagName: 'v1.2.1-build.5')),
    );

    final info = await service.checkForUpdate();

    expect(info, isNull);
  });

  test(
    'skipped version is not returned by a silent check (ignoreSkipped: false)',
    () async {
      when(() => httpClient.execute(any())).thenAnswer(
        (_) async => _okResponse(_releaseJson(tagName: 'v1.3.0')),
      );
      when(() => localStorage.read('app_update')).thenAnswer(
        (_) async => {'skippedVersion': '1.3.0'},
      );

      final info = await service.checkForUpdate();

      expect(info, isNull);
    },
  );

  test(
    'a manual check (ignoreSkipped: true) still returns a skipped version',
    () async {
      when(() => httpClient.execute(any())).thenAnswer(
        (_) async => _okResponse(_releaseJson(tagName: 'v1.3.0')),
      );
      when(() => localStorage.read('app_update')).thenAnswer(
        (_) async => {'skippedVersion': '1.3.0'},
      );

      final info = await service.checkForUpdate(ignoreSkipped: true);

      expect(info, isNotNull);
      expect(info!.version, '1.3.0');
    },
  );

  test('propagates exceptions thrown by the http client', () async {
    when(() => httpClient.execute(any())).thenThrow(Exception('network down'));

    expect(() => service.checkForUpdate(), throwsException);
  });

  test('skipVersion persists the skipped version tag', () async {
    await service.skipVersion('1.3.0');

    verify(
      () => localStorage.write('app_update', {'skippedVersion': '1.3.0'}),
    ).called(1);
  });
}
