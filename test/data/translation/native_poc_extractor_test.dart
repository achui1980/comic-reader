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

  group('parseYoloDetections', () {
    test('按 conf 阈值过滤并把 xyxy 映射回原图 xywh', () {
      // 两行：第一行 conf=0.9 保留，第二行 conf=0.1 过滤。
      // scaleX=scaleY=2：x1=100->ox=200, ow=(300-100)*2=400 等。
      final out = <double>[
        100, 200, 300, 500, 0.9, 0,
        10, 10, 20, 20, 0.1, 0,
      ];
      final boxes = parseYoloDetections(out, 0.3, 2.0, 2.0);
      expect(boxes.length, 1);
      expect(boxes.first, [200, 400, 400, 600]);
    });

    test('全部低于阈值返回空', () {
      final out = <double>[0, 0, 10, 10, 0.2, 0];
      expect(parseYoloDetections(out, 0.3, 1.0, 1.0), isEmpty);
    });
  });
}
