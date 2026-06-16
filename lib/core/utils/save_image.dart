import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Save an image from URL to device gallery.
Future<bool> saveImageToGallery(String url, {Map<String, String>? headers}) async {
  if (kIsWeb) return false;

  try {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
      ),
    );

    final bytes = Uint8List.fromList(response.data!);
    final dir = await getTemporaryDirectory();
    final ext = url.contains('.png') ? 'png' : 'jpg';
    final file = File('${dir.path}/save_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(bytes);

    await Gal.putImage(file.path);
    await file.delete();
    return true;
  } catch (_) {
    return false;
  }
}
