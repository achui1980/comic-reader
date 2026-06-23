import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:comic_reader/data/sources/wu55comic_decoder.dart';

void main() async {
  final dio = Dio();
  
  // Test with one of the failing images from user's log
  final originalUrl = 'https://bmigmij-wuwu.sqxxov.com/break_2/static/upload/book/5336/34679/1814840.jpg';
  
  print('=== Testing Wu55ComicDecoder ===');
  print('Original URL: $originalUrl');
  
  // Step 1: Build shard URLs
  final shardUrls = Wu55ComicDecoder.buildShardUrls(originalUrl);
  print('\nShard 0: ${shardUrls[0]}');
  print('Shard 1: ${shardUrls[1]}');
  
  // Step 2: Download shards
  print('\n--- Downloading shards ---');
  try {
    final resp0 = await dio.get<List<int>>(shardUrls[0], options: Options(responseType: ResponseType.bytes));
    print('Shard 0: status=${resp0.statusCode}, type=${resp0.data.runtimeType}, len=${resp0.data!.length}');
    
    final resp1 = await dio.get<List<int>>(shardUrls[1], options: Options(responseType: ResponseType.bytes));
    print('Shard 1: status=${resp1.statusCode}, type=${resp1.data.runtimeType}, len=${resp1.data!.length}');
    
    // Step 3: Combine
    final combined = Uint8List.fromList([...resp0.data!, ...resp1.data!]);
    print('\nCombined: ${combined.length} bytes');
    print('First 32 bytes (hex): ${combined.sublist(0, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Step 4: Decrypt
    print('\n--- Decrypting ---');
    final decrypted = Wu55ComicDecoder.decryptAES(combined);
    print('Decrypted: ${decrypted.length} bytes');
    print('First 16 bytes: ${decrypted.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('Type code (byte[0]): ${decrypted[0]}');
    print('Sub-type (byte[1]): ${decrypted[1]}');
    
    // Step 5: Restore image
    print('\n--- Restoring image ---');
    final result = Wu55ComicDecoder.decode(combined);
    print('MIME: ${result.mimeType}');
    print('Needs unscramble: ${result.needsUnscramble}');
    print('BookId: ${result.bookId}');
    print('PageNumber: ${result.pageNumber}');
    print('Image bytes length: ${result.imageBytes.length}');
    print('First 12 bytes: ${result.imageBytes.sublist(0, 12).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Step 6: Verify it's a valid JPEG
    if (result.imageBytes[0] == 0xFF && result.imageBytes[1] == 0xD8) {
      print('\n✓ Valid JPEG file header detected!');
      
      // Save to verify
      File('/tmp/wu55_test_output.jpg').writeAsBytesSync(result.imageBytes);
      print('Saved to /tmp/wu55_test_output.jpg');
    } else {
      print('\n✗ NOT a valid JPEG! First bytes: ${result.imageBytes.sublist(0, 4)}');
    }
    
  } catch (e, stack) {
    print('ERROR: $e');
    print('Stack: $stack');
  }
  
  exit(0);
}
