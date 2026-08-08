/// Parses Manga-Bubble-YOLO's `output0` tensor: flattened `[1, 300, 6]`,
/// each row `[x1, y1, x2, y2, conf, cls]` in xyxy corner coordinates
/// relative to the 1280x1280 input space (NMS-free model). Rows with
/// `conf < threshold` are dropped; surviving boxes are mapped back to
/// original-image coordinates via [scaleX]/[scaleY] and converted from
/// xyxy to xywh. Returns `[x, y, w, h]` boxes in original-image pixels.
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
