import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:comic_reader/data/local/download_manager.dart';
import 'package:comic_reader/presentation/downloads/download_drawer.dart';

class MockDownloadManager extends Mock implements DownloadManager {}

void main() {
  late MockDownloadManager manager;

  setUp(() async {
    manager = MockDownloadManager();
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<DownloadManager>(manager);
  });

  testWidgets('paused 任务显示恢复按钮，partiallyFailed 显示重试文案', (tester) async {
    final paused = DownloadTask(
      sourceId: 's',
      mangaId: 'm',
      chapterId: 'c1',
      mangaTitle: 'M',
      chapterTitle: 'C1',
    )..status = DownloadTaskStatus.paused;
    final partial =
        DownloadTask(
            sourceId: 's',
            mangaId: 'm',
            chapterId: 'c2',
            mangaTitle: 'M',
            chapterTitle: 'C2',
          )
          ..status = DownloadTaskStatus.partiallyFailed
          ..failedImageIndexes = [2, 5];

    when(() => manager.tasks).thenReturn([paused, partial]);
    when(() => manager.activeCount).thenReturn(0);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);
    when(() => manager.resumeTask(any())).thenReturn(null);
    when(() => manager.retryTask(any())).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => DownloadDrawer.show(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget); // 恢复按钮
    expect(find.textContaining('2张失败'), findsOneWidget);

    // 点击"恢复"按钮应调用 resumeTask，并传入 paused 任务的 key。
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();
    verify(() => manager.resumeTask(paused.key)).called(1);

    // 点击"重试"文案按钮应调用 retryTask，并传入 partiallyFailed 任务的 key。
    await tester.tap(find.textContaining('2张失败'));
    await tester.pump();
    verify(() => manager.retryTask(partial.key)).called(1);

    // 存在 paused 任务时"全部恢复"按钮应可用，点击后调用 resumeAll。
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    verify(() => manager.resumeAll()).called(1);
  });

  testWidgets('header 显示全部暂停/全部恢复按钮', (tester) async {
    when(() => manager.tasks).thenReturn([]);
    when(() => manager.activeCount).thenReturn(1);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);
    when(() => manager.pauseAll()).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => DownloadDrawer.show(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // activeCount > 0 时"全部暂停"按钮应可用，点击后调用 pauseAll。
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    verify(() => manager.pauseAll()).called(1);
  });

  testWidgets('无进行中/等待中任务时"全部暂停"按钮禁用', (tester) async {
    when(() => manager.tasks).thenReturn([]);
    when(() => manager.activeCount).thenReturn(0);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => DownloadDrawer.show(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final pauseAllButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.pause),
    );
    expect(pauseAllButton.onPressed, isNull);
  });

  testWidgets('无 paused 任务时"全部恢复"按钮禁用', (tester) async {
    final downloading = DownloadTask(
      sourceId: 's',
      mangaId: 'm',
      chapterId: 'c3',
      mangaTitle: 'M',
      chapterTitle: 'C3',
    )..status = DownloadTaskStatus.downloading;

    when(() => manager.tasks).thenReturn([downloading]);
    when(() => manager.activeCount).thenReturn(1);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => DownloadDrawer.show(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final resumeAllButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.play_arrow),
    );
    expect(resumeAllButton.onPressed, isNull);
  });
}
