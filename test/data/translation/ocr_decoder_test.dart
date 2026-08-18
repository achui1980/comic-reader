import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/ocr_decoder.dart';

void main() {
  group('argmaxLastRow', () {
    test('返回最大值下标', () {
      final logits = [0.1, 0.9, 0.3, 0.2];
      expect(argmaxLastRow(logits, 4), 1);
    });
    test('平局取第一个', () {
      final logits = [0.5, 0.5, 0.1];
      expect(argmaxLastRow(logits, 3), 0);
    });
  });

  group('decodeTokens', () {
    final vocab = List<String>.generate(10, (i) => 'T$i');
    test('跳过 <5 的特殊 token', () {
      expect(decodeTokens([2, 5, 6, 3], vocab), 'T5T6');
    });
    test('遇到 EOS(3) 停止', () {
      expect(decodeTokens([7, 3, 8], vocab), 'T7');
    });
    test('空序列返回空串', () {
      expect(decodeTokens([], vocab), '');
    });
  });

  test('常量值正确', () {
    expect(kOcrStartToken, 2);
    expect(kOcrEosToken, 3);
    expect(kOcrSpecialTokenThreshold, 5);
    expect(kOcrMaxSteps, 300);
    expect(kOcrVocabSize, 6144);
  });
}
