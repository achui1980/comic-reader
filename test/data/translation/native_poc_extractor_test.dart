import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/poc/native_poc_extractor.dart';

void main() {
  group('postprocessDetectorBoxes', () {
    test('全 0 分割图返回空', () {
      final seg = List<double>.filled(16, 0.0);
      expect(postprocessDetectorBoxes(seg, 4, 4, 0.3), isEmpty);
    });

    test('单个高亮块提取出外接框', () {
      // 4x4 图，中间 2x2 (行1-2 列1-2) 为高亮
      final seg = <double>[
        0, 0, 0, 0,
        0, 1, 1, 0,
        0, 1, 1, 0,
        0, 0, 0, 0,
      ];
      final boxes = postprocessDetectorBoxes(seg, 4, 4, 0.3);
      expect(boxes.length, 1);
      // box = [x, y, w, h] = [1, 1, 2, 2]
      expect(boxes.first, [1, 1, 2, 2]);
    });
  });
}
