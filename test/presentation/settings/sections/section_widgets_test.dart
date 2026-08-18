import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader/presentation/settings/sections/section_widgets.dart';

void main() {
  const title = '清空翻译缓存';

  /// 搭一个最小宿主：MaterialApp 提供 ScaffoldMessenger（helper 用调用方
  /// context 弹 SnackBar），按钮提供一个 mounted 的 BuildContext。
  Widget host(Future<void> Function() onConfirm) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSettingsConfirmDialog(
              context,
              title: title,
              content: '正文',
              onConfirm: onConfirm,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  /// 打开对话框并点「确定」，落定后返回。
  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('确定'), findsOneWidget, reason: '对话框应已打开');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  }

  group('showSettingsConfirmDialog', () {
    testWidgets('shows a success SnackBar when onConfirm returns normally',
        (tester) async {
      var called = false;
      await tester.pumpWidget(host(() async {
        called = true;
      }));

      await confirm(tester);

      expect(called, isTrue);
      expect(find.text('$title 完成'), findsOneWidget);
      expect(find.textContaining('$title 失败'), findsNothing);
    });

    testWidgets('shows a failure SnackBar when onConfirm throws',
        (tester) async {
      await tester.pumpWidget(host(() async {
        throw StateError('boom');
      }));

      await confirm(tester);

      // helper 内部已 catch，异常不应逃逸成未捕获异步异常。
      expect(tester.takeException(), isNull);
      expect(find.textContaining('$title 失败'), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      expect(find.text('$title 完成'), findsNothing);
    });
  });
}
