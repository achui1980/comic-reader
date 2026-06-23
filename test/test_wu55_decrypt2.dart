import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

void main() async {
  final dio = Dio();
  
  final originalUrl = 'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/5336/34679/1814840.jpg';
  
  print('=== Testing Wu55ComicDecoder (separate decrypt mode) ===');
  
  final shardUrls = Wu55ComicDecoder.buildShardUrls(originalUrl);
  print('Shard 0: ${shardUrls[0]}');
  print('Shard 1: ${shardUrls[1]}');
  
  try {
    final resp0 = await dio.get<List<int>>(shardUrls[0], options: Options(responseType: ResponseType.bytes));
    final resp1 = await dio.get<List<int>>(shardUrls[1], options: Options(responseType: ResponseType.bytes));
    print('Shard 0: ${resp0.data!.length} bytes');
    print('Shard 1: ${resp1.data!.length} bytes');
    
    // Method A: Current approach - combine first, then decrypt
    print('\n--- Method A: Combine then decrypt ---');
    final combinedFirst = Uint8List.fromList([...resp0.data!, ...resp1.data!]);
    try {
      final decryptedA = Wu55ComicDecoder.decryptAES(combinedFirst);
      print('Decrypted: ${decryptedA.length} bytes, byte[0]=${decryptedA[0]}, byte[1]=${decryptedA[1]}');
    } catch (e) {
      print('ERROR: $e');
    }
    
    // Method B: Decrypt each shard separately, then combine
    print('\n--- Method B: Decrypt separately then combine ---');
    final decrypted0 = Wu55ComicDecoder.decryptAES(Uint8List.fromList(resp0.data!));
    final decrypted1 = Wu55ComicDecoder.decryptAES(Uint8List.fromList(resp1.data!));
    final combinedAfter = Uint8List.fromList([...decrypted0, ...decrypted1]);
    print('Shard 0 decrypted: ${decrypted0.length} bytes, first 8: ${decrypted0.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('Shard 1 decrypted: ${decrypted1.length} bytes, first 8: ${decrypted1.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('Combined: ${combinedAfter.length} bytes');
    print('Type code: ${combinedAfter[0]}, Sub-type: ${combinedAfter[1]}');
    
    if (combinedAfter[0] == 0 || combinedAfter[0] == 3 || combinedAfter[0] == 4) {
      final result = Wu55ComicDecoder.restoreImage(combinedAfter);
      print('\n✓ SUCCESS! MIME: ${result.mimeType}, unscramble: ${result.needsUnscramble}');
      print('  BookId: ${result.bookId}, PageNumber: ${result.pageNumber}');
      print('  Image size: ${result.imageBytes.length} bytes');
      File('/tmp/wu55_test_output.jpg').writeAsBytesSync(result.imageBytes);
      print('  Saved to /tmp/wu55_test_output.jpg');
    } else {
      print('Method B also failed: byte[0]=${combinedAfter[0]}');
      
      // Method C: Just decrypt shard0 alone
      print('\n--- Method C: Just shard 0 decrypted ---');
      print('Shard 0 byte[0]=${decrypted0[0]}, byte[1]=${decrypted0[1]}');
      if (decrypted0[0] == 0 || decrypted0[0] == 3 || decrypted0[0] == 4) {
        final result = Wu55ComicDecoder.restoreImage(decrypted0);
        print('✓ Shard 0 alone is a valid image!');
        print('  MIME: ${result.mimeType}, unscramble: ${result.needsUnscramble}');
      }
    }
    
  } catch (e, stack) {
    print('ERROR: $e');
    print('Stack: $stack');
  }
  
  exit(0);
}
