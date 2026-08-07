import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/poc/ocr_preprocess.dart';

void main() {
  test('kOcrInputSize 为 224', () {
    expect(kOcrInputSize, 224);
  });

  test('输出长度为 3*H*W 且 CHW 归一化正确', () {
    // 2x1 图（宽2高1），像素: (255,0,0) (0,255,0)
    final rgb = [255, 0, 0, 0, 255, 0];
    final t = imageToOcrTensor(rgb, 2, 1);
    expect(t.length, 3 * 1 * 2);
    // R 平面: 255->(1-0.5)/0.5=1.0 ; 0->-1.0
    expect(t[0], closeTo(1.0, 1e-6));
    expect(t[1], closeTo(-1.0, 1e-6));
    // G 平面(偏移 H*W=2): 0->-1.0 ; 255->1.0
    expect(t[2], closeTo(-1.0, 1e-6));
    expect(t[3], closeTo(1.0, 1e-6));
    // B 平面(偏移 2*H*W=4): 都是 0->-1.0
    expect(t[4], closeTo(-1.0, 1e-6));
    expect(t[5], closeTo(-1.0, 1e-6));
  });
}
