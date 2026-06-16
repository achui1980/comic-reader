// Quick verification script for PICA image URLs
// Run: HTTPS_PROXY="http://127.0.0.1:2222" dart run test/verify_pica_images.dart

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

const baseUrl = 'https://picaapi.picacomic.com';
const apiKey = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';
const secretKey = r'~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';
const defaultEmail = 'iz9xgh420260616u';
const defaultPassword = 'iz9xgh420260616p';

Map<String, String> buildHeaders(String path, String method, {String? token}) {
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final nonce = 'abcdef1234567890abcdef1234567890';
  final raw = (path + ts + nonce + method.toLowerCase() + apiKey).toLowerCase();
  final hmacSha256 = Hmac(sha256, utf8.encode(secretKey));
  final signature = hmacSha256.convert(utf8.encode(raw)).toString();

  final headers = <String, String>{
    'api-key': apiKey,
    'accept': 'application/vnd.picacomic.com.v1+json',
    'app-channel': '2',
    'app-version': '2.2.1.2.3.3',
    'app-build-version': '44',
    'app-platform': 'android',
    'app-uuid': 'defaultUuid',
    'User-Agent': 'okhttp/3.8.1',
    'Content-Type': 'application/json; charset=UTF-8',
    'Time': ts,
    'Nonce': nonce,
    'Signature': signature,
    'image-quality': 'original',
  };
  if (token != null) headers['Authorization'] = token;
  return headers;
}

Future<String> login() async {
  final path = 'auth/sign-in';
  final headers = buildHeaders(path, 'POST');
  final client = HttpClient();
  
  // Use system proxy
  final proxy = Platform.environment['HTTPS_PROXY'] ?? Platform.environment['https_proxy'];
  if (proxy != null) {
    client.findProxy = (uri) => 'PROXY ${Uri.parse(proxy).host}:${Uri.parse(proxy).port}';
  }
  client.badCertificateCallback = (_, __, ___) => true;
  
  final request = await client.postUrl(Uri.parse('$baseUrl/$path'));
  headers.forEach((k, v) => request.headers.set(k, v));
  request.write(jsonEncode({'email': defaultEmail, 'password': defaultPassword}));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  final json = jsonDecode(body);
  return json['data']['token'] as String;
}

Future<Map<String, dynamic>> fetchApi(String path, String token, HttpClient client) async {
  final headers = buildHeaders(path, 'GET', token: token);
  final request = await client.getUrl(Uri.parse('$baseUrl/$path'));
  headers.forEach((k, v) => request.headers.set(k, v));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return jsonDecode(body) as Map<String, dynamic>;
}

void main() async {
  print('Logging in...');
  final token = await login();
  print('Token: ${token.substring(0, 20)}...');

  final client = HttpClient();
  final proxy = Platform.environment['HTTPS_PROXY'] ?? Platform.environment['https_proxy'];
  if (proxy != null) {
    client.findProxy = (uri) => 'PROXY ${Uri.parse(proxy).host}:${Uri.parse(proxy).port}';
  }
  client.badCertificateCallback = (_, __, ___) => true;

  // Fetch leaderboard to get some manga
  print('\n=== Fetching comics/leaderboard ===');
  final leaderboard = await fetchApi('comics/leaderboard?tt=H24&ct=VC', token, client);
  final comics = leaderboard['data']?['comics'] as List? ?? [];
  print('Got ${comics.length} comics from leaderboard');

  // Print first 5 thumbs
  for (var i = 0; i < 5 && i < comics.length; i++) {
    final comic = comics[i] as Map;
    final title = comic['title'];
    final thumb = comic['thumb'] as Map?;
    print('\n[$i] "$title"');
    print('    thumb: $thumb');
    if (thumb != null) {
      final fs = thumb['fileServer'] ?? '(null)';
      final p = thumb['path'] ?? '(null)';
      print('    fileServer: $fs');
      print('    path: $p');
    }
  }

  // Now search for a specific manga to test different patterns
  print('\n\n=== Searching "真白しらこ" ===');
  final searchPath = 'comics/advanced-search?page=1';
  final searchHeaders = buildHeaders(searchPath, 'POST', token: token);
  final searchReq = await client.postUrl(Uri.parse('$baseUrl/$searchPath'));
  searchHeaders.forEach((k, v) => searchReq.headers.set(k, v));
  searchReq.write(jsonEncode({'keyword': '真白しらこ', 'sort': 'dd'}));
  final searchResp = await searchReq.close();
  final searchBody = await searchResp.transform(utf8.decoder).join();
  final searchJson = jsonDecode(searchBody);
  final searchComics = searchJson['data']?['comics']?['docs'] as List? ?? [];
  print('Found ${searchComics.length} results');

  for (var i = 0; i < 3 && i < searchComics.length; i++) {
    final comic = searchComics[i] as Map;
    final title = comic['title'];
    final thumb = comic['thumb'] as Map?;
    final id = comic['_id'];
    print('\n[$i] "$title" (id=$id)');
    print('    thumb: $thumb');

    // Fetch detail
    final detail = await fetchApi('comics/$id', token, client);
    final dComic = detail['data']?['comic'] as Map?;
    if (dComic != null) {
      final dThumb = dComic['thumb'] as Map?;
      print('    detail.thumb: $dThumb');
    }

    // Fetch chapter images
    final eps = await fetchApi('comics/$id/eps?page=1', token, client);
    final epDocs = eps['data']?['eps']?['docs'] as List? ?? [];
    if (epDocs.isNotEmpty) {
      final firstOrder = (epDocs.first as Map)['order'];
      print('    first ep order: $firstOrder');
      final pages = await fetchApi('comics/$id/order/$firstOrder/pages?page=1', token, client);
      final pageDocs = pages['data']?['pages']?['docs'] as List? ?? [];
      print('    page count: ${pageDocs.length}');
      if (pageDocs.isNotEmpty) {
        final firstMedia = (pageDocs.first as Map)['media'] as Map?;
        print('    first image media: $firstMedia');
        if (pageDocs.length > 1) {
          final secondMedia = (pageDocs[1] as Map)['media'] as Map?;
          print('    second image media: $secondMedia');
        }
      }
    }
  }

  client.close();
  print('\nDone.');
}
