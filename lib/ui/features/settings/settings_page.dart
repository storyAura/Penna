import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../data/services/skill_store.dart';
import '../local/local_model.dart';
import '../studio/comfy_runner.dart';
import 'settings_agent_sections.dart';
import 'settings_app_section.dart';
import 'settings_comfy_section.dart';
import 'settings_extension_sections.dart';
import 'settings_llm_section.dart';
import 'settings_local_section.dart';
import 'settings_translate_section.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

typedef _Tab = ({IconData icon, String label});

List<_Tab> get _tabs => [
  (icon: Icons.hub_outlined, label: tr('API 管理')),
  (icon: Icons.translate, label: tr('翻译')),
  (icon: Icons.theater_comedy_outlined, label: 'Preset'),
  (icon: Icons.school_outlined, label: 'Skills'),
  (icon: Icons.tune, label: tr('参数与工具')),
  (icon: Icons.electrical_services, label: 'MCP'),
  (icon: Icons.brush_outlined, label: 'ComfyUI'),
  (icon: Icons.bolt_outlined, label: tr('快捷操作')),
  (icon: Icons.memory_outlined, label: tr('本地反推')),
  (icon: Icons.settings_applications_outlined, label: tr('软件设置')),
];

/// 设置页:左边分区导航,右边对应的表单。改动即时保存。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.service,
    required this.skills,
    required this.local,
    required this.comfy,
  });

  final ConfigService service;
  final SkillStore skills;
  final LocalModel local;
  final ComfyRunner comfy;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _tab = 0;
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return Row(
      // 内容不满一屏时也贴着顶部,而不是被竖直居中。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PennaColors.card,
            border: Border(right: BorderSide(color: PennaColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  tr('设置'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (var i = 0; i < _tabs.length; i++)
                _TabItem(
                  tab: _tabs[i],
                  selected: i == _tab,
                  onTap: () => setState(() => _tab = i),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                // 软件设置在右边另有一栏,放宽一些。
                constraints: BoxConstraints(
                  maxWidth: _tab == _tabs.length - 1 ? appSectionMaxWidth : 760,
                ),
                // 换分区时新内容弹入;key 不变时(同一分区内的改动)不重播。
                child: PopIn(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    0 => LlmSection(service: service),
                    1 => TranslateSection(service: service),
                    2 => PresetSection(service: service),
                    3 => SkillsSection(service: service, skills: widget.skills),
                    4 => AbilitySection(service: service),
                    5 => McpSection(service: service),
                    6 => ComfySection(service: service, runner: widget.comfy),
                    7 => QuickActionSection(service: service),
                    8 => LocalSection(service: service, local: widget.local),
                    _ => AppSection(service: service),
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PennaColors.primary : PennaColors.slate700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Bouncy(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.base),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? PennaColors.primaryBg : PennaColors.card,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(tab.icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
