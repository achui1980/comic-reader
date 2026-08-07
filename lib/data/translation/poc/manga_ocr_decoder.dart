/// manga-ocr 贪婪解码相关常量与纯函数（PoC）。
const int kOcrStartToken = 2;
const int kOcrEosToken = 3;
const int kOcrSpecialTokenThreshold = 5;
const int kOcrMaxSteps = 300;
const int kOcrVocabSize = 6144;

/// 在一行 logits（长度 vocabSize）里取 argmax token id。平局取第一个。
int argmaxLastRow(List<double> logitsFlat, int vocabSize) {
  var best = 0;
  var bestVal = logitsFlat[0];
  for (var i = 1; i < vocabSize; i++) {
    if (logitsFlat[i] > bestVal) {
      bestVal = logitsFlat[i];
      best = i;
    }
  }
  return best;
}

/// 把 token id 序列转成字符串：遇到 EOS(3) 停止，<5 的特殊 token 跳过，
/// 其余查 vocab 拼接。
String decodeTokens(List<int> tokenIds, List<String> vocab) {
  final buffer = StringBuffer();
  for (final id in tokenIds) {
    if (id == kOcrEosToken) break;
    if (id < kOcrSpecialTokenThreshold) continue;
    if (id < vocab.length) buffer.write(vocab[id]);
  }
  return buffer.toString();
}
