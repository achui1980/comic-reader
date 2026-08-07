import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'manga_ocr_decoder.dart';
import 'ocr_preprocess.dart';

/// 检测到的文字区域: box=[x,y,w,h]，text=OCR 出的日文。
class PocTextRegion {
  final List<int> box;
  final String text;
  const PocTextRegion({required this.box, required this.text});
}

/// 把 detector 分割图阈值化后，用简单连通块外接矩形提取 box 列表。
/// segMap: 长度 mapW*mapH 的置信度；thresh: 阈值。
/// 简化版：把所有 >thresh 的像素视为前景，做一次 4-邻接洪泛聚类，
/// 每个连通块取外接框 [x,y,w,h]。
List<List<int>> postprocessDetectorBoxes(
    List<double> segMap, int mapW, int mapH, double thresh) {
  final visited = List<bool>.filled(mapW * mapH, false);
  final boxes = <List<int>>[];
  int idx(int x, int y) => y * mapW + x;

  for (var y = 0; y < mapH; y++) {
    for (var x = 0; x < mapW; x++) {
      if (visited[idx(x, y)] || segMap[idx(x, y)] <= thresh) continue;
      // BFS 洪泛
      var minX = x, maxX = x, minY = y, maxY = y;
      final queue = <List<int>>[[x, y]];
      visited[idx(x, y)] = true;
      while (queue.isNotEmpty) {
        final p = queue.removeLast();
        final px = p[0], py = p[1];
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          final nx = px + d[0], ny = py + d[1];
          if (nx < 0 || ny < 0 || nx >= mapW || ny >= mapH) continue;
          if (visited[idx(nx, ny)] || segMap[idx(nx, ny)] <= thresh) continue;
          visited[idx(nx, ny)] = true;
          queue.add([nx, ny]);
        }
      }
      boxes.add([minX, minY, maxX - minX + 1, maxY - minY + 1]);
    }
  }
  return boxes;
}

class NativePocExtractor {
  NativePocExtractor({required this.runtime});
  final OnnxRuntime runtime;

  OrtSession? _detector;
  OrtSession? _ocr;
  List<String> _vocab = const [];

  static const _detectorAsset = 'assets/models/comictextdetector.onnx';
  static const _ocrAsset = 'assets/models/manga-ocr/model.onnx';
  static const _vocabAsset = 'assets/models/manga-ocr/vocab.txt';

  Future<void> loadModels() async {
    _detector = await runtime.createSessionFromAsset(_detectorAsset);
    _ocr = await runtime.createSessionFromAsset(_ocrAsset);
    final vocabRaw = await rootBundle.loadString(_vocabAsset);
    _vocab = vocabRaw.split('\n');
  }

  Future<List<PocTextRegion>> extract(Uint8List imageBytes) async {
    final detector = _detector;
    final ocr = _ocr;
    if (detector == null || ocr == null) {
      throw StateError('模型未加载，请先调用 loadModels()');
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw StateError('图片解码失败');

    // 1. detector: resize 到 1024，跑分割，后处理出 box
    final detResized = img.copyResize(decoded, width: 1024, height: 1024);
    final detInput = _imageToChwFloat32(detResized, 1024, 1024);
    final detTensor = await OrtValue.fromList(detInput, [1, 3, 1024, 1024]);
    final detOut = await detector.run({detector.inputNames.first: detTensor});
    final segName = detector.outputNames.first;
    final segMap = (await detOut[segName]!.asList()).cast<double>();
    final boxes = postprocessDetectorBoxes(segMap, 1024, 1024, 0.3);

    // 2. 逐 box 裁剪 -> resize 224 -> manga-ocr 贪婪解码
    final regions = <PocTextRegion>[];
    final scaleX = decoded.width / 1024.0;
    final scaleY = decoded.height / 1024.0;
    for (final b in boxes) {
      final ox = (b[0] * scaleX).round();
      final oy = (b[1] * scaleY).round();
      final ow = (b[2] * scaleX).round().clamp(1, decoded.width - ox);
      final oh = (b[3] * scaleY).round().clamp(1, decoded.height - oy);
      final crop = img.copyCrop(decoded, x: ox, y: oy, width: ow, height: oh);
      final ocrResized =
          img.copyResize(crop, width: kOcrInputSize, height: kOcrInputSize);
      final rgb = _extractRgb(ocrResized);
      final ocrTensor = imageToOcrTensor(rgb, kOcrInputSize, kOcrInputSize);
      final text = await _runOcrGreedy(ocr, ocrTensor);
      regions.add(PocTextRegion(box: [ox, oy, ow, oh], text: text));
    }
    return regions;
  }

  Future<String> _runOcrGreedy(OrtSession ocr, Float32List imageTensor) async {
    final imgName = ocr.inputNames[0];
    final tokName = ocr.inputNames[1];
    final logitsName = ocr.outputNames.first;
    final tokens = <int>[kOcrStartToken];
    final imgVal =
        await OrtValue.fromList(imageTensor, [1, 3, kOcrInputSize, kOcrInputSize]);
    for (var step = 0; step < kOcrMaxSteps; step++) {
      final tokVal = await OrtValue.fromList(
          Int64List.fromList(tokens.map((e) => e).toList()), [1, tokens.length]);
      final out = await ocr.run({imgName: imgVal, tokName: tokVal});
      final logits = (await out[logitsName]!.asList()).cast<double>();
      // 取最后一步(最后一行)的 logits
      final lastRow =
          logits.sublist(logits.length - kOcrVocabSize, logits.length);
      final next = argmaxLastRow(lastRow, kOcrVocabSize);
      if (next == kOcrEosToken) break;
      tokens.add(next);
    }
    return decodeTokens(tokens.sublist(1), _vocab);
  }

  Float32List _imageToChwFloat32(img.Image im, int w, int h) {
    final plane = w * h;
    final out = Float32List(3 * plane);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final i = y * w + x;
        out[i] = p.r / 255.0;
        out[plane + i] = p.g / 255.0;
        out[2 * plane + i] = p.b / 255.0;
      }
    }
    return out;
  }

  List<int> _extractRgb(img.Image im) {
    final out = <int>[];
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        out.add(p.r.toInt());
        out.add(p.g.toInt());
        out.add(p.b.toInt());
      }
    }
    return out;
  }
}
