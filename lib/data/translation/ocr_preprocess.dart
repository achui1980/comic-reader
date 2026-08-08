import 'dart:typed_data';

const int kOcrInputSize = 224;

/// 把 RGB 交错像素（R,G,B,R,G,B...）转成 CHW 排列、归一化的张量。
/// 归一化: (v/255 - 0.5) / 0.5。通道顺序 R 平面 -> G 平面 -> B 平面。
Float32List imageToOcrTensor(List<int> rgbPixels, int width, int height) {
  final plane = width * height;
  final out = Float32List(3 * plane);
  for (var i = 0; i < plane; i++) {
    final r = rgbPixels[i * 3];
    final g = rgbPixels[i * 3 + 1];
    final b = rgbPixels[i * 3 + 2];
    out[i] = (r / 255.0 - 0.5) / 0.5;
    out[plane + i] = (g / 255.0 - 0.5) / 0.5;
    out[2 * plane + i] = (b / 255.0 - 0.5) / 0.5;
  }
  return out;
}
