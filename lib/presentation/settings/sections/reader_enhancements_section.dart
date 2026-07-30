import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/local/settings_store.dart';
import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';
import 'section_widgets.dart';

/// "阅读器增强" section (was `_SettingsView._buildReaderEnhancementsSection`).
class ReaderEnhancementsSection extends StatelessWidget {
  const ReaderEnhancementsSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    final s = state.settings;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    const scaleLabels = {
      ScaleType.fitScreen: '适应屏幕',
      ScaleType.fitWidth: '适应宽度',
      ScaleType.fitHeight: '适应高度',
      ScaleType.original: '原始大小',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('阅读器增强'),
        ListTile(
          title: const Text('缩放模式'),
          subtitle: Text('${scaleLabels[s.scaleType]}（横向翻页时生效）'),
          trailing: DropdownButton<ScaleType>(
            value: s.scaleType,
            underline: const SizedBox.shrink(),
            items: ScaleType.values
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(scaleLabels[t]!),
                    ))
                .toList(),
            onChanged: (t) {
              if (t != null) cubit.setScaleType(t);
            },
          ),
        ),
        SwitchListTile(
          title: const Text('显示页码'),
          subtitle: const Text('在阅读器角落显示当前页码'),
          value: s.showPageNumber,
          onChanged: cubit.setShowPageNumber,
        ),
        SwitchListTile(
          title: const Text('屏幕常亮'),
          subtitle: Text(
            (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                ? '阅读时保持屏幕点亮'
                : '阅读时保持屏幕点亮（仅移动端生效）',
          ),
          value: s.keepScreenOn,
          onChanged: cubit.setKeepScreenOn,
        ),
        SwitchListTile(
          title: const Text('显示点击区域'),
          subtitle: const Text('横向翻页时叠加显示上一页/菜单/下一页区域'),
          value: s.showTapZones,
          onChanged: cubit.setShowTapZones,
        ),
        SwitchListTile(
          title: const Text('反转点击区域'),
          subtitle: const Text('交换左右点击翻页方向'),
          value: s.tapZonesInvert,
          onChanged: cubit.setTapZonesInvert,
        ),
        SwitchListTile(
          title: const Text('裁剪白边'),
          subtitle: const Text('自动裁掉图片周围的空白边缘'),
          value: s.cropBorders,
          onChanged: cubit.setCropBorders,
        ),
        SwitchListTile(
          title: const Text('拆分宽图'),
          subtitle: const Text('将横向宽图拆分为两页显示'),
          value: s.splitWidePages,
          onChanged: cubit.setSplitWidePages,
        ),
        if (isAndroid)
          SwitchListTile(
            title: const Text('音量键翻页'),
            subtitle: const Text('使用音量键上下翻页（仅 Android）'),
            value: s.volumeKeyTurn,
            onChanged: cubit.setVolumeKeyTurn,
          ),
        const Divider(),
      ],
    );
  }
}
