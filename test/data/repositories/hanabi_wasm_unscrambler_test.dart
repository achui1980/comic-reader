import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comic_reader/data/repositories/hanabi_wasm_unscrambler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('unscramble decrypts a real scrambled page using the real reader.wasm', () async {
    final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();
    final scrambledBytes =
        await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();

    final decoded = img.decodeImage(scrambledBytes)!;
    expect(decoded.width, 960);
    expect(decoded.height, 1372);
    final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

    // These hashes reflect package:image's own pure-Dart WebP decode, which
    // is NOT bit-exact with libwebp/Pillow for lossy WebP (a known
    // limitation of pure-Dart WebP decoders: ~1.5% of pixels differ from a
    // libwebp decode by small rounding amounts, e.g. chroma-upsampling/IDCT
    // differences). They are self-consistent end-to-end validation of the
    // real production decode+unscramble pipeline (img.decodeImage ->
    // HanabiWasmUnscrambler.unscramble), not an external ground truth
    // derived from a reference decoder.
    final scrambledHash = sha256.convert(rgba).toString();
    expect(
      scrambledHash,
      'caa1d38c4b13cf9e2bc11f4e2e8988de03b3ddada0b931c7ba6b12c82744c456',
    );

    final ticket = base64Decode('Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=');
    final nonce = base64Decode('ZkfsVQTteF2Ab4Ha');

    final unscrambler = HanabiWasmUnscrambler();
    await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);
    final result = await unscrambler.unscramble(
      rgba,
      decoded.width,
      decoded.height,
      ticket,
      nonce,
      4,
      4,
    );

    expect(result.length, 5268480);
    final resultHash = sha256.convert(result).toString();
    expect(
      resultHash,
      '410f8598a95efb975e3ce55f441b6fee551a6b9d049fedf8464e3eebb3cd29d3',
    );
  });

  test(
    'unscramble can be called repeatedly on the same instance without '
    'corrupting results (regression guard for input-buffer dealloc)',
    () async {
      final wasmBytes = await File('test/fixtures/hanabi/reader.wasm').readAsBytes();
      final scrambledBytes =
          await File('test/fixtures/hanabi/scrambled_page001.webp').readAsBytes();

      final decoded = img.decodeImage(scrambledBytes)!;
      final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);

      final ticket = base64Decode('Qi7trobdcZGeZuodLH1829AVM+00eSykQq83KThsKIM=');
      final nonce = base64Decode('ZkfsVQTteF2Ab4Ha');

      final unscrambler = HanabiWasmUnscrambler();
      await unscrambler.ensureLoaded(wasmBytesOverride: wasmBytes);

      const expectedHash =
          '410f8598a95efb975e3ce55f441b6fee551a6b9d049fedf8464e3eebb3cd29d3';

      // Call unscramble() 3 times sequentially against the SAME loaded
      // instance, re-using the same source bytes each time. Before the
      // dealloc fix, each call leaked its three input buffers (ticket,
      // nonce, image RGBA) in WASM linear memory; this proves repeated
      // calls still produce the correct result and don't crash/corrupt
      // due to the added dealloc calls freeing memory that's still in use.
      for (var i = 0; i < 3; i++) {
        final result = await unscrambler.unscramble(
          Uint8List.fromList(rgba), // fresh copy each call, like real usage
          decoded.width,
          decoded.height,
          Uint8List.fromList(ticket),
          Uint8List.fromList(nonce),
          4,
          4,
        );
        expect(result.length, 5268480, reason: 'call #$i result length');
        final hash = sha256.convert(result).toString();
        expect(hash, expectedHash, reason: 'call #$i result hash');
      }
    },
  );
}
