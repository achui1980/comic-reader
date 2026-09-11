import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:comic_reader/core/utils/image_response_decoder.dart';
import 'package:comic_reader/data/sources/source_image_transform.dart';
import 'package:comic_reader/domain/entities/entities.dart';

/// Save an image from URL to device gallery.
///
/// [sourceId] is used to apply the owning source's raw-bytes transform (e.g.
/// per-site image decryption); without it, sources that serve encrypted images
/// would write ciphertext to the gallery.
Future<bool> saveImageToGallery(
  String url, {
  Map<String, String>? headers,
  ImageResponseEncoding responseEncoding = ImageResponseEncoding.binary,
  String? sourceId,
}) async {
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

    final bytes = applySourceImageTransform(
      decodeImageResponseBytes(
        Uint8List.fromList(response.data!),
        responseEncoding,
      ),
      sourceId,
    );
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
