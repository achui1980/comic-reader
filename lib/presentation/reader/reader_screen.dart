import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:comic_reader/domain/entities/entities.dart';
import 'package:comic_reader/domain/repositories/manga_repository.dart';
import 'package:comic_reader/data/local/reading_history_store.dart';
import 'package:comic_reader/data/local/settings_store.dart' show SettingsStore;
import 'package:comic_reader/data/sources/source_registry.dart';
import 'package:comic_reader/presentation/common/cloudflare_dialog.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_bloc.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_event.dart';
import 'package:comic_reader/presentation/reader/bloc/reader_state.dart';
import 'widgets/horizontal_reader.dart';
import 'widgets/vertical_reader.dart';
import 'widgets/reader_controls.dart';

/// Full-screen immersive manga reader.
/// Hides system UI, provides gesture-based navigation,
/// and supports horizontal (page-flip) and vertical (webtoon scroll) modes.
class ReaderScreen extends StatefulWidget {
  final String sourceId;
  final String mangaId;
  final String chapterId;
  final List<dynamic> chapterList;
  final int initialPage;
  final String mangaTitle;
  final String coverUrl;

  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.mangaId,
    required this.chapterId,
    this.chapterList = const [],
    this.initialPage = 0,
    this.mangaTitle = '',
    this.coverUrl = '',
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ReaderBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = ReaderBloc(
      repository: GetIt.instance<MangaRepository>(),
      readingHistoryStore: GetIt.instance<ReadingHistoryStore>(),
      settingsStore: GetIt.instance<SettingsStore>(),
    );
    // Cast chapter list items to ChapterItem
    final chapters = widget.chapterList
        .whereType<ChapterItem>()
        .toList();
    _bloc.add(LoadChapter(
      sourceId: widget.sourceId,
      mangaId: widget.mangaId,
      chapterId: widget.chapterId,
      chapterList: chapters,
      initialPage: widget.initialPage,
      mangaTitle: widget.mangaTitle,
      coverUrl: widget.coverUrl,
    ));
    _enterImmersiveMode();
    _applyWakelock();
  }

  /// Keep the screen awake while reading when enabled (mobile only).
  Future<void> _applyWakelock() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final settings = await GetIt.instance<SettingsStore>().load();
      if (settings.keepScreenOn) {
        await WakelockPlus.enable();
      }
    } catch (_) {
      // Wakelock is best-effort; ignore failures.
    }
  }

  Future<void> _releaseWakelock() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await WakelockPlus.disable();
    } catch (_) {
      // ignore
    }
  }

  @override
  void dispose() {
    _releaseWakelock();
    _exitImmersiveMode();
    _bloc.close();
    super.dispose();
  }

  void _enterImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }

  void _exitImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: BlocBuilder<ReaderBloc, ReaderState>(
          builder: (context, state) {
            return Stack(
              children: [
                // Main reader content
                _buildReaderContent(state),
                // Persistent page indicator (always visible)
                if (state.status == ReaderStatus.loaded && state.showPageNumber)
                  _buildPageIndicator(state),
                // Controls overlay (animated)
                _buildControlsOverlay(state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReaderContent(ReaderState state) {
    switch (state.status) {
      case ReaderStatus.initial:
      case ReaderStatus.loading:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      case ReaderStatus.error:
        final isCfError = state.errorMessage?.contains('CloudflareException') == true ||
            state.errorMessage?.contains('Cloudflare') == true;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCfError ? Icons.shield_outlined : Icons.error_outline,
                color: isCfError ? Colors.orange : Colors.white54,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                isCfError ? '需要完成 Cloudflare 验证' : (state.errorMessage ?? '加载失败'),
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (isCfError)
                FilledButton.icon(
                  onPressed: () async {
                    final sourceName = GetIt.instance<SourceRegistry>().get(widget.sourceId)?.name;
                    final verified = await showCloudflareDialog(
                      context,
                      sourceId: widget.sourceId,
                      sourceName: sourceName,
                    );
                    if (verified && context.mounted) {
                      _bloc.add(LoadChapter(
                        sourceId: widget.sourceId,
                        mangaId: widget.mangaId,
                        chapterId: state.chapterId.isNotEmpty
                            ? state.chapterId
                            : widget.chapterId,
                      ));
                    }
                  },
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('去验证'),
                )
              else
                ElevatedButton(
                  onPressed: () => _bloc.add(LoadChapter(
                    sourceId: widget.sourceId,
                    mangaId: widget.mangaId,
                    chapterId: state.chapterId.isNotEmpty
                        ? state.chapterId
                        : widget.chapterId,
                  )),
                  child: const Text('重试'),
                ),
            ],
          ),
        );
      case ReaderStatus.loaded:
        if (state.images.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.image_not_supported, color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '未能解析图片\n请检查浏览器控制台日志',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _bloc.add(LoadChapter(
                    sourceId: widget.sourceId,
                    mangaId: widget.mangaId,
                    chapterId: state.chapterId.isNotEmpty
                        ? state.chapterId
                        : widget.chapterId,
                  )),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }
        if (state.layoutMode == LayoutMode.vertical) {
          return VerticalReader(
            images: state.images,
            initialPage: state.currentPage,
          );
        }
        return HorizontalReader(
          images: state.images,
          initialPage: state.currentPage,
          direction: state.direction,
        );
    }
  }

  Widget _buildControlsOverlay(ReaderState state) {
    return AnimatedOpacity(
      opacity: state.showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !state.showControls,
        child: const ReaderControls(),
      ),
    );
  }

  Widget _buildPageIndicator(ReaderState state) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 12,
      right: 16,
      child: AnimatedOpacity(
        opacity: state.showControls ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${state.currentPage + 1} / ${state.totalPages}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
