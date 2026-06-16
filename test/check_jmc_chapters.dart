import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as e;

void main() async {
  final dio = Dio();
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final token = md5.convert(utf8.encode('${ts}18comicAPP')).toString();
  final tokenparam = '$ts,2.0.21';

  // Test multiple albums - single chapter and multi-chapter
  final testIds = ['440808', '400222', '152637', '1446861'];
  for (final albumId in testIds) {
    final ts2 = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final token2 = md5.convert(utf8.encode('${ts2}18comicAPP')).toString();
    final tokenparam2 = '$ts2,2.0.21';

    try {
      final resp2 = await dio.get('https://www.cdngwc.cc/album',
        queryParameters: {'id': albumId},
        options: Options(headers: {'token': token2, 'tokenparam': tokenparam2,
          'User-Agent': 'Mozilla/5.0 (Linux; Android 9) Chrome/91.0.4472.114'}));

      final json2 = jsonDecode(resp2.data.toString());
      final keyHex2 = md5.convert(utf8.encode('${ts2}185Hcomic3PAPP7R')).toString();
      final dataBytes2 = base64.decode(json2['data']);
      final key2 = e.Key(Uint8List.fromList(utf8.encode(keyHex2)));
      final enc2 = e.Encrypter(e.AES(key2, mode: e.AESMode.ecb, padding: 'PKCS7'));
      final dec2 = enc2.decrypt(e.Encrypted(dataBytes2));
      final data2 = jsonDecode(dec2) as Map;

      final series2 = data2['series'] as List? ?? [];
      print('\n--- Album $albumId: ${data2["name"]} ---');
      print('  series: ${series2.length} chapters');
      if (series2.isEmpty) {
        // Single chapter manga - album_id is also the photo_id
        print('  (single chapter, use album_id as chapter_id)');
      } else {
        for (int i = 0; i < series2.length && i < 3; i++) {
          print('  [$i]: ${jsonEncode(series2[i])}');
        }
      }
    } catch (err) {
      print('\n--- Album $albumId: ERROR: $err');
    }
  }
}
