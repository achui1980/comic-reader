/// A single detected (and optionally translated) text region on a manga
/// page. [box] is `[x, y, w, h]` in original-image pixel coordinates.
/// [translatedText] is null until [TranslationPipeline] fills it in.
class TextRegion {
  const TextRegion({
    required this.box,
    required this.originalText,
    this.translatedText,
  });

  final List<int> box;
  final String originalText;
  final String? translatedText;

  TextRegion copyWith({String? translatedText}) => TextRegion(
        box: box,
        originalText: originalText,
        translatedText: translatedText,
      );

  Map<String, dynamic> toJson() => {
        'box': box,
        'originalText': originalText,
        'translatedText': translatedText,
      };

  factory TextRegion.fromJson(Map<String, dynamic> json) {
    final rawBox = json['box'] as List? ?? const [];
    return TextRegion(
      box: rawBox.map((e) => (e as num).toInt()).toList(),
      originalText: json['originalText'] as String? ?? '',
      translatedText: json['translatedText'] as String?,
    );
  }
}
