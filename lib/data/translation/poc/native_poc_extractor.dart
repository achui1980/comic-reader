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

/// 解析 Manga-Bubble-YOLO 的输出 output0[1,300,6]（扁平后每行
/// x1,y1,x2,y2,conf,cls，坐标相对 1280 输入空间，免 NMS）。
/// conf>=threshold 才保留，xyxy 角点坐标按 scale 映射回原图并转 xywh。
/// 返回 [[ox,oy,ow,oh]...]。
List<List<int>> parseYoloDetections(
    List<double> output, double threshold, double scaleX, double scaleY) {
  final boxes = <List<int>>[];
  final rows = output.length ~/ 6;
  for (var i = 0; i < rows; i++) {
    final base = i * 6;
    final conf = output[base + 4];
    if (conf < threshold) continue;
    final x1 = output[base], y1 = output[base + 1];
    final x2 = output[base + 2], y2 = output[base + 3];
    final ox = (x1 * scaleX).round();
    final oy = (y1 * scaleY).round();
    final ow = ((x2 - x1) * scaleX).round();
    final oh = ((y2 - y1) * scaleY).round();
    boxes.add([ox, oy, ow, oh]);
  }
  return boxes;
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
  OrtSession? _ocrEncoder;
  OrtSession? _ocrDecoder;
  List<String> _vocab = const [];

  static const _detectorAsset = 'assets/models/comic-bubble-yolo.onnx';
  static const _ocrEncoderAsset = 'assets/models/manga-ocr/encoder_model.onnx';
  static const _ocrDecoderAsset = 'assets/models/manga-ocr/decoder_model.onnx';
  static const _vocabAsset = 'assets/models/manga-ocr/vocab.txt';

  Future<void> loadModels() async {
    _detector = await runtime.createSessionFromAsset(_detectorAsset);
    _ocrEncoder = await runtime.createSessionFromAsset(_ocrEncoderAsset);
    _ocrDecoder = await runtime.createSessionFromAsset(_ocrDecoderAsset);
    final vocabRaw = await rootBundle.loadString(_vocabAsset);
    _vocab = vocabRaw.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  }

  Future<List<PocTextRegion>> extract(Uint8List imageBytes) async {
    final detector = _detector;
    final encoder = _ocrEncoder;
    final decoder = _ocrDecoder;
    if (detector == null || encoder == null || decoder == null) {
      throw StateError('模型未加载，请先调用 loadModels()');
    }
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw StateError('图片解码失败');

    // 1. detector: Manga-Bubble-YOLO，resize 到 1280，跑气泡检测。
    //    输出 output0[1,300,6]，每行 [x1,y1,x2,y2,conf,cls]（xyxy，相对 1280，免 NMS）。
    final detResized = img.copyResize(decoded, width: 1280, height: 1280);
    final detInput = _imageToChwFloat32(detResized, 1280, 1280);
    final detTensor = await OrtValue.fromList(detInput, [1, 3, 1280, 1280]);
    final detOut = await detector.run({detector.inputNames.first: detTensor});
    final yoloOut = (await detOut['output0']!.asList()).cast<double>();
    final scaleX = decoded.width / 1280.0;
    final scaleY = decoded.height / 1280.0;
    // parseYoloDetections 已把坐标映射回原图并转成 xywh。
    final boxes = parseYoloDetections(yoloOut, 0.3, scaleX, scaleY);

    // 2. 逐 box 裁剪 -> resize 224 -> manga-ocr 贪婪解码
    final regions = <PocTextRegion>[];
    for (final b in boxes) {
      final ox = b[0].clamp(0, decoded.width - 1);
      final oy = b[1].clamp(0, decoded.height - 1);
      final ow = b[2].clamp(1, decoded.width - ox);
      final oh = b[3].clamp(1, decoded.height - oy);
      final crop = img.copyCrop(decoded, x: ox, y: oy, width: ow, height: oh);
      final ocrResized =
          img.copyResize(crop, width: kOcrInputSize, height: kOcrInputSize);
      final rgb = _extractRgb(ocrResized);
      final ocrTensor = imageToOcrTensor(rgb, kOcrInputSize, kOcrInputSize);
      final text = await _runOcrGreedy(encoder, decoder, ocrTensor);
      regions.add(PocTextRegion(box: [ox, oy, ow, oh], text: text));
    }
    return regions;
  }

  /// manga-ocr 是 VisionEncoderDecoder 双文件模型：
  /// 先 encoder(pixel_values -> last_hidden_state[1,197,768])，
  /// 再 decoder 贪婪循环(input_ids + encoder_hidden_states -> logits[1,seq,6144])。
  Future<String> _runOcrGreedy(
      OrtSession encoder, OrtSession decoder, Float32List imageTensor) async {
    // encoder 只跑一次，hidden 复用于每一步 decoder。
    final pixelValues =
        await OrtValue.fromList(imageTensor, [1, 3, kOcrInputSize, kOcrInputSize]);
    final encOut =
        await encoder.run({encoder.inputNames.first: pixelValues});
    final hidden = encOut['last_hidden_state']!;

    final tokens = <int>[kOcrStartToken];
    for (var step = 0; step < kOcrMaxSteps; step++) {
      final idsVal = await OrtValue.fromList(
          Int64List.fromList(tokens), [1, tokens.length]);
      final out = await decoder.run({
        'input_ids': idsVal,
        'encoder_hidden_states': hidden,
      });
      final logits = (await out['logits']!.asList()).cast<double>();
      // logits 形状 [1, seq, 6144]，取最后一步(最后一行)的 vocab logits。
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
