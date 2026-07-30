import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/local/settings_store.dart';
import '../bloc/settings_cubit.dart';
import '../bloc/settings_state.dart';
import 'section_widgets.dart';

/// "阅读设置" section (was `_SettingsView._buildReadingSection`).
class ReadingSection extends StatelessWidget {
  const ReadingSection({super.key, required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionHeader('阅读设置'),
        ListTile(
          title: const Text('默认布局'),
          subtitle: Text(
            state.layoutMode == LayoutMode.horizontal ? '横向翻页' : '纵向滚动',
          ),
          trailing: SegmentedButton<LayoutMode>(
            segments: const [
              ButtonSegment(
                value: LayoutMode.horizontal,
                label: Text('横向'),
                icon: Icon(Icons.swap_horiz, size: 16),
              ),
              ButtonSegment(
                value: LayoutMode.vertical,
                label: Text('纵向'),
                icon: Icon(Icons.swap_vert, size: 16),
              ),
            ],
            selected: {state.layoutMode},
            onSelectionChanged: (set) => cubit.setLayoutMode(set.first),
          ),
        ),
        ListTile(
          title: const Text('阅读方向'),
          subtitle: Text(
            state.readingDirection == ReadingDirection.ltr ? '从左到右' : '从右到左',
          ),
          trailing: SegmentedButton<ReadingDirection>(
            segments: const [
              ButtonSegment(
                value: ReadingDirection.ltr,
                label: Text('LTR'),
              ),
              ButtonSegment(
                value: ReadingDirection.rtl,
                label: Text('RTL'),
              ),
            ],
            selected: {state.readingDirection},
            onSelectionChanged: (set) =>
                cubit.setReadingDirection(set.first),
          ),
        ),
        SwitchListTile(
          title: const Text('自动翻页'),
          subtitle: Text(
            state.autoPageTurn
                ? '每 ${state.autoPageTurnInterval} 秒翻一页'
                : '已关闭',
          ),
          value: state.autoPageTurn,
          onChanged: cubit.setAutoPageTurn,
        ),
        if (state.autoPageTurn)
          ListTile(
            title: const Text('翻页间隔'),
            subtitle: Slider(
              value: state.autoPageTurnInterval.toDouble(),
              min: 2,
              max: 15,
              divisions: 13,
              label: '${state.autoPageTurnInterval}s',
              onChanged: (v) => cubit.setAutoPageTurnInterval(v.round()),
            ),
          ),
        const Divider(),
      ],
    );
  }
}
