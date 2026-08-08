import 'dart:io' as io;

import 'package:path_provider/path_provider.dart';

/// Describes one downloadable model asset used by the translation pipeline.
class ModelFileSpec {
  const ModelFileSpec({
    required this.relativePath,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  /// Path relative to the models directory, e.g. `comic-bubble-yolo.onnx`
  /// or `manga-ocr/encoder_model.onnx`.
  final String relativePath;
  final String url;
  final String sha256;
  final int sizeBytes;
}

/// The four model files required by `NativeMangaTextExtractor`.
const List<ModelFileSpec> kTranslationModelFiles = [
  ModelFileSpec(
    relativePath: 'comic-bubble-yolo.onnx',
    url:
        'https://huggingface.co/Kiuyha/Manga-Bubble-YOLO/resolve/main/onnx/yolo26n.onnx',
    sha256:
        'b45c2e12cf0c3c1d2abfbbb9123c9f96f040f2ac36a0842382ecd9d859c851c7',
    sizeBytes: 6069760,
  ),
  ModelFileSpec(
    relativePath: 'manga-ocr/encoder_model.onnx',
    url:
        'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/encoder_model.onnx',
    sha256:
        '15fa8155fe9bc1a7d25d9bb353debaa4def033d0174e907dbd2dd6d995def85f',
    sizeBytes: 343454249,
  ),
  ModelFileSpec(
    relativePath: 'manga-ocr/decoder_model.onnx',
    url:
        'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/decoder_model.onnx',
    sha256:
        'ef7765261e9d1cdc34d89356986c2bbc2a082897f753a89605ae80fdfa61f5e8',
    sizeBytes: 117480262,
  ),
  ModelFileSpec(
    relativePath: 'manga-ocr/vocab.txt',
    url:
        'https://huggingface.co/mayocream/manga-ocr-onnx/resolve/main/vocab.txt',
    sha256:
        '5cb5c5586d98a2f331d9f8828e4586479b0611bfba5d8c3b6dadffc84d6a36a3',
    sizeBytes: 30216,
  ),
];

/// Thrown by [TranslationModelManager.ensureReady] when one or more model
/// files are missing (or have the wrong size) in local storage.
class ModelNotReadyException implements Exception {
  ModelNotReadyException(this.missing);
  final List<String> missing;
  @override
  String toString() => 'ModelNotReadyException: missing ${missing.join(", ")}';
}

/// Downloads and verifies the ONNX model files used for on-device manga
/// translation, storing them under the app's documents directory (not
/// bundled as assets — they total ~460MB).
class TranslationModelManager {
  TranslationModelManager({
    List<ModelFileSpec>? files,
    Future<String> Function()? baseDirResolver,
  })  : _files = files ?? kTranslationModelFiles,
        _baseDirResolver = baseDirResolver ?? _defaultBaseDir;

  final List<ModelFileSpec> _files;
  final Future<String> Function() _baseDirResolver;

  static Future<String> _defaultBaseDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> modelsDir() async {
    final base = await _baseDirResolver();
    return '$base/models/translation';
  }

  Future<String> pathFor(String relativePath) async {
    final dir = await modelsDir();
    return '$dir/$relativePath';
  }

  /// Checks whether every model file exists and has the expected size.
  Future<bool> isReady() async {
    for (final spec in _files) {
      final path = await pathFor(spec.relativePath);
      final file = io.File(path);
      if (!await file.exists()) return false;
      if (await file.length() != spec.sizeBytes) return false;
    }
    return true;
  }

  /// Throws [ModelNotReadyException] listing every missing/invalid file.
  Future<void> ensureReady() async {
    final missing = <String>[];
    for (final spec in _files) {
      final path = await pathFor(spec.relativePath);
      final file = io.File(path);
      final ok = await file.exists() && await file.length() == spec.sizeBytes;
      if (!ok) missing.add(spec.relativePath);
    }
    if (missing.isNotEmpty) throw ModelNotReadyException(missing);
  }

  /// Downloads every model file that is missing or has the wrong size,
  /// streaming to disk. [onProgress] reports `(relativePath, receivedBytes,
  /// totalBytes)` for each file as it downloads (and once immediately, with
  /// received==total, for files that are already present).
  Future<void> downloadAll({
    void Function(String file, int received, int total)? onProgress,
  }) async {
    for (final spec in _files) {
      final path = await pathFor(spec.relativePath);
      final file = io.File(path);
      if (await file.exists() && await file.length() == spec.sizeBytes) {
        onProgress?.call(spec.relativePath, spec.sizeBytes, spec.sizeBytes);
        continue;
      }
      await file.parent.create(recursive: true);
      final client = io.HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(spec.url));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw StateError(
              '下载失败 ${spec.relativePath}: HTTP ${response.statusCode}');
        }
        final sink = file.openWrite();
        var received = 0;
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(spec.relativePath, received, spec.sizeBytes);
          }
        } finally {
          await sink.close();
        }
      } catch (e) {
        if (await file.exists()) await file.delete();
        rethrow;
      } finally {
        client.close(force: true);
      }
    }
  }
}
