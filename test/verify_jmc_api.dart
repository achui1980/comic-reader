// Quick verification script for JMComic APP API
// Run: dart run test/verify_jmc_api.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

const appTokenSecret = '18comicAPP';
const appDataSecret = '185Hcomic3PAPP7R';
const appVersion = '2.0.21';

const apiDomains = [
  'www.cdnhjk.net',
  'www.cdngwc.cc',
  'www.cdngwc.net',
  'www.cdngwc.club',
  'www.cdnhjk.cc',
];

String md5Hex(String input) =>
    md5.convert(utf8.encode(input)).toString();

Map<String, dynamic>? decryptData(String encryptedData, String ts) {
  final keyHex = md5Hex('$ts$appDataSecret');
  final keyBytes = utf8.encode(keyHex);
  final dataBytes = base64.decode(encryptedData);

  final key = encrypt_pkg.Key(Uint8List.fromList(keyBytes));
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.ecb, padding: 'PKCS7'),
  );
  final decrypted = encrypter.decrypt(encrypt_pkg.Encrypted(dataBytes));
  return jsonDecode(decrypted) as Map<String, dynamic>;
}

void main() async {
  final dio = Dio();

  // Try each domain
  for (final domain in apiDomains) {
    final baseUrl = 'https://$domain';
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final token = md5Hex('$ts$appTokenSecret');
    final tokenparam = '$ts,$appVersion';

    print('--- Testing domain: $domain ---');
    print('  ts=$ts, token=$token, tokenparam=$tokenparam');

    try {
      // Test /categories/filter (discovery)
      final resp = await dio.get(
        '$baseUrl/categories/filter',
        queryParameters: {
          'page': '1',
          'order': '',
          'c': '0',
          'o': 'mr',
        },
        options: Options(
          headers: {
            'token': token,
            'tokenparam': tokenparam,
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) '
                'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36',
            'Accept-Encoding': 'gzip, deflate',
          },
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      print('  Status: ${resp.statusCode}');

      // Parse response (may be String or Map depending on content-type)
      Map<String, dynamic> jsonResp;
      if (resp.data is Map) {
        jsonResp = resp.data as Map<String, dynamic>;
      } else {
        jsonResp = jsonDecode(resp.data.toString()) as Map<String, dynamic>;
      }

      final code = jsonResp['code'];
      print('  Code: $code');

      if (jsonResp['data'] is String && (jsonResp['data'] as String).isNotEmpty) {
        print('  Encrypted data length: ${(jsonResp['data'] as String).length}');

        // Try to decrypt
        try {
          final decrypted = decryptData(jsonResp['data'] as String, ts);
          if (decrypted != null) {
            final content = decrypted['content'] as List?;
            print('  ✅ Decryption SUCCESS!');
            print('  Total results: ${decrypted['total']}');
            if (content != null && content.isNotEmpty) {
              final first = content[0];
              print('  First item: id=${first['id']}, name=${first['name']}');
              print('  Author: ${first['author']}');
            }
          }
        } catch (e) {
          print('  ❌ Decryption failed: $e');
        }
        // One success is enough
        break;
      } else {
        print('  Response data: $jsonResp');
      }
    } on DioException catch (e) {
      print('  ❌ DioError: ${e.type} - ${e.message}');
      if (e.response != null) {
        print('  Status: ${e.response?.statusCode}');
      }
    } catch (e) {
      print('  ❌ Error: $e');
    }
  }

  print('\nDone.');
  exit(0);
}
