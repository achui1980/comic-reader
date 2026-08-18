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

/// 断点续传的三种走向。
enum ResumeAction {
  /// `.part` 已经是完整文件，直接改名转正。
  skip,

  /// `.part` 是有效前缀，带 `Range: bytes=<offset>-` 续下。
  resume,

  /// 没有 `.part`，或 `.part` 比目标还长（脏数据），从 0 重下。
  restart,
}

/// 续传决策结果。[startOffset] 只在 [ResumeAction.resume] 时有意义。
class ResumeDecision {
  const ResumeDecision(this.action, this.startOffset);
  final ResumeAction action;
  final int startOffset;
}

/// 纯函数：根据本地 `.part` 已有字节数 [existingBytes] 与目标总字节数
/// [totalBytes] 决定如何继续下载。抽成纯函数是为了可单测——[downloadAll]
/// 内部用的是裸 `HttpClient`，无法注入 mock。
ResumeDecision decideResume({
  required int existingBytes,
  required int totalBytes,
}) {
  if (existingBytes == totalBytes) {
    return const ResumeDecision(ResumeAction.skip, 0);
  }
  if (existingBytes <= 0 || existingBytes > totalBytes) {
    return const ResumeDecision(ResumeAction.restart, 0);
  }
  return ResumeDecision(ResumeAction.resume, existingBytes);
}

/// 纯函数：判断 206 响应的 `Content-Range` 头能否被安全地当成「接着 `.part`
/// 往后写」来使用。合法头形如 `bytes 400-1023/1024`。
///
/// 头缺失、格式不合法（如 `bytes */1024`）、起点不等于 [expectedStart]、或
/// 总长不等于 [expectedTotal] 时返回 false —— 此时 `[0..N)` 与 `[N..)` 可能
/// 来自服务端/CDN 上两个不同 revision，拼出的长度若恰好等于期望值就会通过
/// [TranslationModelManager.downloadAll] 末尾的长度校验被误转正，而本功能
/// 不提供删除模型的入口，用户无从自救。抽成纯函数是为了可单测——
/// [TranslationModelManager.downloadAll] 内部用的是裸 `HttpClient`，无法注入
/// mock。
bool isResumeContentRangeAcceptable(
  String? header, {
  required int expectedStart,
  required int expectedTotal,
}) {
  if (header == null) return false;
  final match =
      RegExp(r'^\s*bytes\s+(\d+)\s*-\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(header);
  if (match == null) return false;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  final total = int.tryParse(match.group(3)!);
  // `\d+` 已保证是数字，tryParse 只会在超出 int64 时返回 null。
  if (start == null || end == null || total == null) return false;
  if (end < start) return false;
  return start == expectedStart && total == expectedTotal;
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

  /// 下载缺失/字节数不符的模型文件，流式写入 `<name>.part` 后改名转正。
  ///
  /// 断点续传：`.part` 在失败时**保留**，下次调用带 `Range: bytes=N-` 从中断处
  /// 继续；服务器忽略 Range（返回 200 而非 206）时退化为从头重下。
  /// [onProgress] 报告 `(relativePath, receivedBytes, totalBytes)`，已就绪的
  /// 文件会立刻回调一次 received == total。
  ///
  /// 无互斥锁：调用方必须保证同一时刻只有一个 [downloadAll] 在跑（UI 侧用
  /// `PopScope(canPop: false)` + 禁用按钮实现）。
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

      final part = io.File('$path.part');
      final existing = await part.exists() ? await part.length() : 0;
      final decision = decideResume(
        existingBytes: existing,
        totalBytes: spec.sizeBytes,
      );
      if (decision.action == ResumeAction.skip) {
        await part.rename(path);
        onProgress?.call(spec.relativePath, spec.sizeBytes, spec.sizeBytes);
        continue;
      }
      if (decision.action == ResumeAction.restart && existing > 0) {
        await part.delete();
      }

      var received = decision.startOffset;
      final client = io.HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(spec.url));
        if (received > 0) {
          request.headers.set(io.HttpHeaders.rangeHeader, 'bytes=$received-');
        }
        final response = await request.close();
        final code = response.statusCode;
        if (code != 200 && code != 206) {
          throw StateError(
              '下载失败 ${spec.relativePath}: HTTP ${response.statusCode}');
        }
        // 服务器忽略了 Range：只能丢掉已有前缀从头写。
        if (code == 200 && received > 0) received = 0;
        // 206 但 Content-Range 与本次续传请求不符（服务端对象已变更 / CDN 命中
        // 了另一个 revision）：续写会把两个版本的字节拼在一起，长度恰好达标时
        // 会被误转正。等同 restart —— received 归零后下面用 FileMode.write
        // （自带 truncate）丢弃 `.part` 从头写。
        if (code == 206 &&
            !isResumeContentRangeAcceptable(
              response.headers.value(io.HttpHeaders.contentRangeHeader),
              expectedStart: received,
              expectedTotal: spec.sizeBytes,
            )) {
          received = 0;
        }

        final sink = part.openWrite(
          mode: received > 0 ? io.FileMode.append : io.FileMode.write,
        );
        try {
          onProgress?.call(spec.relativePath, received, spec.sizeBytes);
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(spec.relativePath, received, spec.sizeBytes);
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }

      // 失败时不删 `.part`（留给下次续传），只有长度达标才转正。
      final downloaded = await part.length();
      if (downloaded != spec.sizeBytes) {
        throw StateError(
            '下载不完整 ${spec.relativePath}: $downloaded/${spec.sizeBytes}');
      }
      await part.rename(path);
      onProgress?.call(spec.relativePath, spec.sizeBytes, spec.sizeBytes);
    }
  }
}
