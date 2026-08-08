import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:comic_reader/data/translation/manga_text_extractor.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';

void main() {
  test('extract() throws StateError before loadModels() is called', () async {
    final extractor = NativeMangaTextExtractor(
      runtime: OnnxRuntime(),
      modelManager: TranslationModelManager(
        baseDirResolver: () async => '/tmp/translation-extractor-test',
      ),
    );

    await expectLater(
      extractor.extract(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<StateError>()),
    );
  });
}
