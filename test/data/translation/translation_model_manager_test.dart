import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/data/translation/translation_model_manager.dart';

void main() {
  group('kTranslationModelFiles', () {
    test('lists exactly the 4 required model files', () {
      final paths =
          kTranslationModelFiles.map((f) => f.relativePath).toList();
      expect(paths, [
        'comic-bubble-yolo.onnx',
        'manga-ocr/encoder_model.onnx',
        'manga-ocr/decoder_model.onnx',
        'manga-ocr/vocab.txt',
      ]);
    });

    test('every spec has a positive size, sha256 and https url', () {
      for (final spec in kTranslationModelFiles) {
        expect(spec.sizeBytes, greaterThan(0));
        expect(spec.sha256, isNotEmpty);
        expect(spec.url, startsWith('https://'));
      }
    });
  });

  group('TranslationModelManager with small fake specs in a temp dir', () {
    late Directory tempDir;
    late TranslationModelManager manager;
    const specs = [
      ModelFileSpec(
        relativePath: 'a.onnx',
        url: 'https://example.com/a.onnx',
        sha256: 'x',
        sizeBytes: 4,
      ),
      ModelFileSpec(
        relativePath: 'sub/b.onnx',
        url: 'https://example.com/b.onnx',
        sha256: 'y',
        sizeBytes: 8,
      ),
    ];

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('translation_model_test_');
      manager = TranslationModelManager(
        files: specs,
        baseDirResolver: () async => tempDir.path,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('modelsDir points under baseDir/models/translation', () async {
      final dir = await manager.modelsDir();
      expect(dir, '${tempDir.path}/models/translation');
    });

    test('pathFor joins modelsDir with the relative path', () async {
      final path = await manager.pathFor('a.onnx');
      expect(path, '${tempDir.path}/models/translation/a.onnx');
    });

    test('isReady is false when no files exist', () async {
      expect(await manager.isReady(), isFalse);
    });

    test('ensureReady throws ModelNotReadyException listing all missing files',
        () async {
      await expectLater(
        manager.ensureReady(),
        throwsA(isA<ModelNotReadyException>()
            .having((e) => e.missing, 'missing', ['a.onnx', 'sub/b.onnx'])),
      );
    });

    test('isReady is true once every file exists with the right size',
        () async {
      for (final spec in specs) {
        final path = await manager.pathFor(spec.relativePath);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List<int>.filled(spec.sizeBytes, 0));
      }
      expect(await manager.isReady(), isTrue);
      await manager.ensureReady(); // should not throw
    });

    test('isReady is false when a file exists with the wrong size',
        () async {
      for (final spec in specs) {
        final path = await manager.pathFor(spec.relativePath);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List<int>.filled(spec.sizeBytes + 1, 0));
      }
      expect(await manager.isReady(), isFalse);
    });
  });

  group('decideResume', () {
    test('skips when the partial file already has every byte', () {
      final d = decideResume(existingBytes: 100, totalBytes: 100);
      expect(d.action, ResumeAction.skip);
      expect(d.startOffset, 0);
    });

    test('resumes from the existing byte count when partially downloaded', () {
      final d = decideResume(existingBytes: 40, totalBytes: 100);
      expect(d.action, ResumeAction.resume);
      expect(d.startOffset, 40);
    });

    test('restarts when the partial file is longer than expected', () {
      final d = decideResume(existingBytes: 140, totalBytes: 100);
      expect(d.action, ResumeAction.restart);
      expect(d.startOffset, 0);
    });

    test('restarts when nothing has been downloaded yet', () {
      final d = decideResume(existingBytes: 0, totalBytes: 100);
      expect(d.action, ResumeAction.restart);
      expect(d.startOffset, 0);
    });
  });

  group('isResumeContentRangeAcceptable', () {
    test('accepts a well-formed header whose start and total both match', () {
      expect(
        isResumeContentRangeAcceptable(
          'bytes 400-1023/1024',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isTrue,
      );
    });

    test('rejects a header whose start does not match the requested offset',
        () {
      expect(
        isResumeContentRangeAcceptable(
          'bytes 512-1023/1024',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects a header whose total differs from the expected size', () {
      expect(
        isResumeContentRangeAcceptable(
          'bytes 400-2047/2048',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects a missing header', () {
      expect(
        isResumeContentRangeAcceptable(
          null,
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects an unsatisfied-range header with an unknown start', () {
      expect(
        isResumeContentRangeAcceptable(
          'bytes */1024',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects a header with an unknown total length', () {
      expect(
        isResumeContentRangeAcceptable(
          'bytes 400-1023/*',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects garbage', () {
      expect(
        isResumeContentRangeAcceptable(
          'garbage',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects an empty header', () {
      expect(
        isResumeContentRangeAcceptable(
          '',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });

    test('rejects a self-inconsistent range whose end precedes its start', () {
      expect(
        isResumeContentRangeAcceptable(
          'bytes 400-399/1024',
          expectedStart: 400,
          expectedTotal: 1024,
        ),
        isFalse,
      );
    });
  });
}
