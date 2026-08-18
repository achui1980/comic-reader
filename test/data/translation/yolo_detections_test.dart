import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/yolo_detections.dart';

void main() {
  group('parseYoloDetections', () {
    test('按 conf 阈值过滤并把 xyxy 映射回原图 xywh', () {
      // 两行:第一行 conf=0.9 保留,第二行 conf=0.1 过滤。
      // scaleX=scaleY=2:x1=100->ox=200, ow=(300-100)*2=400 等。
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

    test('多行时保留每一行满足阈值的框', () {
      final out = <double>[
        0, 0, 10, 10, 0.5, 0,
        20, 20, 30, 30, 0.6, 0,
      ];
      final boxes = parseYoloDetections(out, 0.4, 1.0, 1.0);
      expect(boxes.length, 2);
      expect(boxes[0], [0, 0, 10, 10]);
      expect(boxes[1], [20, 20, 10, 10]);
    });
  });
}
