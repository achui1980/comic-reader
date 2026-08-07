import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/translation/poc/native_poc_extractor.dart';

class TranslationPocScreen extends StatefulWidget {
  const TranslationPocScreen({super.key});
  @override
  State<TranslationPocScreen> createState() => _TranslationPocScreenState();
}

class _TranslationPocScreenState extends State<TranslationPocScreen> {
  NativePocExtractor? _extractor;
  List<PocTextRegion> _regions = const [];
  bool _busy = false;
  String _status = '点击选图开始';

  Future<void> _ensureLoaded() async {
    if (_extractor != null) return;
    final ex = NativePocExtractor(runtime: OnnxRuntime());
    await ex.loadModels();
    _extractor = ex;
  }

  Future<void> _pickAndRun() async {
    setState(() { _busy = true; _status = '加载模型...'; });
    try {
      await _ensureLoaded();
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) { setState(() { _busy = false; _status = '已取消'; }); return; }
      setState(() => _status = '推理中...');
      final bytes = await picked.readAsBytes();
      final regions = await _extractor!.extract(Uint8List.fromList(bytes));
      setState(() { _regions = regions; _status = '完成，共 ${regions.length} 区域'; });
    } catch (e) {
      setState(() => _status = '出错: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('翻译 PoC（本地推理）')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _pickAndRun,
                  child: const Text('选图并识别'),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_status)),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _regions.length,
              itemBuilder: (_, i) {
                final r = _regions[i];
                return ListTile(
                  dense: true,
                  title: Text(r.text),
                  subtitle: Text('box=${r.box}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
