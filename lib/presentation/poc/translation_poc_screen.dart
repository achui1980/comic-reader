import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/translation/models/page_translation.dart';
import '../../data/translation/translation_model_manager.dart';
import '../../data/translation/translation_pipeline.dart';

class TranslationPocScreen extends StatefulWidget {
  const TranslationPocScreen({super.key});
  @override
  State<TranslationPocScreen> createState() => _TranslationPocScreenState();
}

class _TranslationPocScreenState extends State<TranslationPocScreen> {
  bool _busy = false;
  String _status = '点击"下载模型"（首次使用），然后选图并翻译';
  PageTranslation? _result;

  Future<void> _downloadModels() async {
    setState(() {
      _busy = true;
      _status = '下载模型中...';
    });
    try {
      final manager = GetIt.instance<TranslationModelManager>();
      await manager.downloadAll(onProgress: (file, received, total) {
        setState(() => _status = '下载 $file: $received / $total');
      });
      setState(() => _status = '模型已就绪');
    } catch (e) {
      setState(() => _status = '下载失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickAndTranslate() async {
    setState(() {
      _busy = true;
      _status = '选择图片...';
    });
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) {
        setState(() {
          _busy = false;
          _status = '已取消';
        });
        return;
      }
      setState(() => _status = '识别 + 翻译中...');
      final bytes = await picked.readAsBytes();
      final pipeline = GetIt.instance<TranslationPipeline>();
      final result = await pipeline.translatePage(
        'debug_source',
        'debug_manga',
        'debug_chapter',
        0,
        Uint8List.fromList(bytes),
      );
      setState(() {
        _result = result;
        _status = '完成，共 ${result.regions.length} 区域';
      });
    } catch (e) {
      setState(() => _status = '出错: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final regions = _result?.regions ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('翻译管道调试页')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _downloadModels,
                  child: const Text('下载模型'),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : _pickAndTranslate,
                  child: const Text('选图并翻译'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_status),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: regions.length,
              itemBuilder: (_, i) {
                final r = regions[i];
                return ListTile(
                  dense: true,
                  isThreeLine: true,
                  title: Text(r.translatedText ?? '(未翻译)'),
                  subtitle: Text('原文: ${r.originalText}\nbox=${r.box}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
