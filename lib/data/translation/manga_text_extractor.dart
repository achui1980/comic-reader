import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'models/text_region.dart';
import 'ocr_decoder.dart';
import 'ocr_preprocess.dart';
import 'translation_model_manager.dart';
import 'yolo_detections.dart';

/// Extracts text regions (bubble box + original-language text) from a
/// manga page image. Implementations do not translate — that is
/// `TranslationPipeline`'s job, via the app-wide BYOK `AiClient`.
abstract class MangaTextExtractor {
  Future<void> loadModels();
  Future<List<TextRegion>> extract(Uint8List imageBytes);
}

/// On-device implementation using Manga-Bubble-YOLO (bubble detection) +
/// manga-ocr (VisionEncoderDecoder Japanese OCR), both running through
/// flutter_onnxruntime. Model weights are downloaded to the app's
/// documents directory by [TranslationModelManager] (not bundled as
/// Flutter assets).
class NativeMangaTextExtractor implements MangaTextExtractor {
  NativeMangaTextExtractor({
    required this.runtime,
    required this.modelManager,
  });

  final OnnxRuntime runtime;
  final TranslationModelManager modelManager;

  OrtSession? _detector;
  OrtSession? _ocrEncoder;
  OrtSession? _ocrDecoder;
  List<String> _vocab = const [];

  @override
  Future<void> loadModels() async {
    if (_detector != null && _ocrEncoder != null && _ocrDecoder != null) {
      return;
    }
    final detectorPath = await modelManager.pathFor('comic-bubble-yolo.onnx');
    final encoderPath =
        await modelManager.pathFor('manga-ocr/encoder_model.onnx');
    final decoderPath =
        await modelManager.pathFor('manga-ocr/decoder_model.onnx');
    final vocabPath = await modelManager.pathFor('manga-ocr/vocab.txt');

    _detector = await runtime.createSession(detectorPath);
    _ocrEncoder = await runtime.createSession(encoderPath);
    _ocrDecoder = await runtime.createSession(decoderPath);

    final vocabRaw = await File(vocabPath).readAsString();
    _vocab = vocabRaw.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  }

  @override
  Future<List<TextRegion>> extract(Uint8List imageBytes) async {
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
    final outKey =
        detOut.containsKey('output0') ? 'output0' : detector.outputNames.first;
    // asFlattenedList() 返回展平的 1D 列表；asList() 会按张量 shape 做 reshape
    // 成嵌套 List，对 [1,300,6] 这种 3 维输出会导致长度=1（外层 batch 维），
    // 必须用 asFlattenedList() 才能拿到真正的 1800 个 float。
    final yoloOut = (await detOut[outKey]!.asFlattenedList()).cast<double>();
    final scaleX = decoded.width / 1280.0;
    final scaleY = decoded.height / 1280.0;
    // parseYoloDetections 已把坐标映射回原图并转成 xywh。
    final boxes = parseYoloDetections(yoloOut, 0.3, scaleX, scaleY);

    // 2. 逐 box 裁剪 -> resize 224 -> manga-ocr 贪婪解码
    final regions = <TextRegion>[];
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
      regions.add(TextRegion(box: [ox, oy, ow, oh], originalText: text));
    }
    return regions;
  }

  /// manga-ocr 是 VisionEncoderDecoder 双文件模型：
  /// 先 encoder(pixel_values -> last_hidden_state[1,197,768])，
  /// 再 decoder 贪婪循环(input_ids + encoder_hidden_states -> logits[1,seq,6144])。
  Future<String> _runOcrGreedy(
      OrtSession encoder, OrtSession decoder, Float32List imageTensor) async {
    // encoder 只跑一次，hidden 复用于每一步 decoder。
    final pixelValues = await OrtValue.fromList(
        imageTensor, [1, 3, kOcrInputSize, kOcrInputSize]);
    final encOut = await encoder.run({encoder.inputNames.first: pixelValues});
    final hidden = encOut['last_hidden_state']!;

    final tokens = <int>[kOcrStartToken];
    for (var step = 0; step < kOcrMaxSteps; step++) {
      final idsVal = await OrtValue.fromList(
          Int64List.fromList(tokens), [1, tokens.length]);
      final out = await decoder.run({
        'input_ids': idsVal,
        'encoder_hidden_states': hidden,
      });
      final logits = (await out['logits']!.asFlattenedList()).cast<double>();
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
