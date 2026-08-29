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
      sourceId: 's', mangaId: 'm', chapterId: 'c1',
      mangaTitle: 'M', chapterTitle: 'C1',
    )..status = DownloadTaskStatus.paused;
    final partial = DownloadTask(
      sourceId: 's', mangaId: 'm', chapterId: 'c2',
      mangaTitle: 'M', chapterTitle: 'C2',
    )
      ..status = DownloadTaskStatus.partiallyFailed
      ..failedImageIndexes = [2, 5];

    when(() => manager.tasks).thenReturn([paused, partial]);
    when(() => manager.activeCount).thenReturn(0);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => DownloadDrawer.show(context),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget); // 恢复按钮
    expect(find.textContaining('2张失败'), findsOneWidget);
  });

  testWidgets('header 显示全部暂停/全部恢复按钮', (tester) async {
    when(() => manager.tasks).thenReturn([]);
    when(() => manager.activeCount).thenReturn(1);
    when(() => manager.pendingCount).thenReturn(0);
    when(() => manager.addListener(any())).thenReturn(null);
    when(() => manager.removeListener(any())).thenReturn(null);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => DownloadDrawer.show(context),
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });
}
