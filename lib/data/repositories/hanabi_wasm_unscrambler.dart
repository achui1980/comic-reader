import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:wasm_run/wasm_run.dart';

/// Loads hanabimanga.com's official `/reader.wasm` module and invokes its
/// `unscramble` export to reverse the site's page-shuffling obfuscation.
///
/// This deliberately does NOT run the site's own reader page/React
/// component (which would trigger its canvas export DRM). Instead it loads
/// the same publicly-served WASM binary directly and drives it with our own
/// wasm-bindgen-compatible glue code.
class HanabiWasmUnscrambler {
  static const String _wasmUrl = 'https://web.hanabimanga.com/reader.wasm';

  WasmInstance? _instance;
  WasmMemory? _memory;
  WasmFunction? _unscrambleFn;
  WasmFunction? _allocFn;
  WasmFunction? _deallocFn;
  WasmFunction? _addStackFn;
  static bool _libSetUp = false;

  /// Loads and instantiates the WASM module if not already loaded.
  /// Pass [wasmBytesOverride] (e.g. in tests) to skip the network download
  /// and use pre-fetched bytes instead.
  Future<void> ensureLoaded({Uint8List? wasmBytesOverride}) async {
    if (_instance != null) return;

    if (!_libSetUp) {
      await WasmRunLibrary.setUp(isFlutter: true, loadAsset: rootBundle.load);
      _libSetUp = true;
    }

    final bytes = wasmBytesOverride ?? await _downloadWasm();

    final module = await compileWasmModule(
      bytes,
      config: const ModuleConfig(
        wasmi: ModuleConfigWasmi(),
        wasmtime: ModuleConfigWasmtime(),
      ),
    );

    final builder = module.builder(wasiConfig: null);
    builder.addImport(
      './xfmanga_wasm_bg.js',
      '__wbg_Error_2e59b1b37a9a34c3',
      WasmFunction(
        (int msgPtr, int msgLen) => 0,
        params: [ValueTy.i32, ValueTy.i32],
        results: [ValueTy.i32],
      ),
    );
    builder.addImport(
      './xfmanga_wasm_bg.js',
      '__wbg___wbindgen_throw_81fc77679af83bc6',
      WasmFunction.voidReturn(
        (int msgPtr, int msgLen) {
          throw Exception('hanabi wasm unscramble threw an internal error');
        },
        params: [ValueTy.i32, ValueTy.i32],
      ),
    );

    final instance = await builder.build();

    final memory = instance.getMemory('memory');
    final unscrambleFn = instance.getFunction('unscramble');
    final allocFn = instance.getFunction('__wbindgen_export');
    final deallocFn = instance.getFunction('__wbindgen_export2');
    final addStackFn = instance.getFunction('__wbindgen_add_to_stack_pointer');

    if (memory == null ||
        unscrambleFn == null ||
        allocFn == null ||
        deallocFn == null ||
        addStackFn == null) {
      throw Exception('hanabi reader.wasm is missing expected exports');
    }

    _instance = instance;
    _memory = memory;
    _unscrambleFn = unscrambleFn;
    _allocFn = allocFn;
    _deallocFn = deallocFn;
    _addStackFn = addStackFn;
  }

  Future<Uint8List> _downloadWasm() async {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      _wasmUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  int _writeBytes(Uint8List bytes) {
    final ptr = _allocFn!.inner(bytes.length, 1) as int;
    _memory!.view.setRange(ptr, ptr + bytes.length, bytes);
    return ptr;
  }

  /// Unscrambles a decoded RGBA image buffer using the given ticket/nonce
  /// and grid dimensions (all sourced from the reader API's
  /// `metadata.scrambleInfo`). Returns a new RGBA buffer of the same length.
  Future<Uint8List> unscramble(
    Uint8List rgba,
    int width,
    int height,
    Uint8List ticket,
    Uint8List nonce,
    int cols,
    int rows,
  ) async {
    await ensureLoaded();

    final ticketPtr = _writeBytes(ticket);
    final noncePtr = _writeBytes(nonce);
    final imagePtr = _writeBytes(rgba);

    final retPtr = _addStackFn!.inner(-16) as int;

    _unscrambleFn!.inner(
      retPtr,
      ticketPtr,
      ticket.length,
      noncePtr,
      nonce.length,
      imagePtr,
      rgba.length,
      width,
      height,
      cols,
      rows,
    );

    final retView = ByteData.sublistView(_memory!.view, retPtr, retPtr + 16);
    final resultPtr = retView.getInt32(0, Endian.little);
    final resultLen = retView.getInt32(4, Endian.little);
    final hasError = retView.getInt32(12, Endian.little);

    _addStackFn!.inner(16);

    if (hasError != 0) {
      throw Exception('hanabi wasm unscramble reported an error');
    }

    final decrypted = Uint8List.fromList(
      _memory!.view.sublist(resultPtr, resultPtr + resultLen),
    );

    _deallocFn!.inner(resultPtr, resultLen, 1);

    return decrypted;
  }
}
