import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:crypto/crypto.dart';

Map<String, String> buildSignedHeaders(String urlPath, String method) {
  const apiKey = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';
  const secretKey = r'~d}$Q7$eIni=V)9\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';
  
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random();
  final nonce = List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();

  final raw = ('$urlPath$ts$nonce$method$apiKey').toLowerCase();
  final key = utf8.encode(secretKey);
  final hmacSha256 = Hmac(sha256, key);
  final digest = hmacSha256.convert(utf8.encode(raw));
  final signature = digest.toString();

  return {
    'api-key': apiKey,
    'accept': 'application/vnd.picacomic.com.v1+json',
    'app-channel': '2',
    'time': ts,
    'nonce': nonce,
    'signature': signature,
    'app-version': '2.2.1.2.3.3',
    'app-uuid': 'defaultUuid',
    'app-platform': 'android',
    'app-build-version': '44',
    'content-type': 'application/json; charset=UTF-8',
    'user-agent': 'okhttp/3.8.1',
    'image-quality': 'original',
  };
}

void main() async {
  // Test: sign-in with dummy credentials to verify API accepts the request format
  const path = 'auth/sign-in';
  final headers = buildSignedHeaders(path, 'POST');

  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY 127.0.0.1:2222';
  final request = await client.postUrl(
    Uri.parse('https://picaapi.picacomic.com/$path'),
  );
  headers.forEach((k, v) => request.headers.set(k, v));
  
  // Use fake creds to test API response format
  request.write(jsonEncode({'email': 'test@test.com', 'password': 'wrongpass123'}));
  
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  
  print('Status: ${response.statusCode}');
  print('Body: $body');
  
  client.close();
}
