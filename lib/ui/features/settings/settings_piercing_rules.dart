import 'package:flutter/material.dart';

import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/widgets.dart';
import 'settings_agent_sections.dart' show hintStyle;
import 'settings_sections.dart';

/// 穿甲弹卡片最下面「按模型」:给某个模型单独定模式和段,盖过上面的设置
/// (2026-11-26 用户要求)。对话的穿甲弹开着时才生效,主聊天、副聊天都认。
class PiercingRules extends StatelessWidget {
  const PiercingRules({super.key, required this.service});

  final ConfigService service;

  List<String> get _modelNames => {
    for (final l in service.config.llms)
      if (l.enabled) ...l.models,
  }.toList();

  static Map<String, String> get _modeLabels => {
    piercingModePrompt: tr('提示词'),
    piercingModeDocument: tr('文档'),
    piercingModeTool: tr('工具调用'),
  };

  /// [mode] 能挑的段:提示词是存下的各段;工具调用多一个「不用预设」(空名字);文档没有。
  static List<(String, String)> _segments(AppConfig cfg, String mode) =>
      switch (mode) {
        piercingModePrompt => [
          for (final p in cfg.piercingSaved) (p.name, p.name),
        ],
        piercingModeTool => [
          ('', tr('不用预设')),
          for (final p in cfg.piercingToolSaved) (p.name, p.name),
        ],
        _ => const [],
      };

  /// 换模式时段也跟着换成那种模式的默认:提示词用第一段,工具调用不用预设。
  static String _defaultName(AppConfig cfg, String mode) =>
      mode == piercingModePrompt
      ? cfg.piercingSaved.firstOrNull?.name ?? ''
      : '';

  void _put(int index, PiercingRule? rule) {
    final cfg = service.config;
    service.update(
      cfg.copyWith(
        piercingRules: [
          for (final (i, r) in cfg.piercingRules.indexed)
            if (i != index) r else ?rule,
          if (index >= cfg.piercingRules.length) ?rule,
        ],
      ),
    );
  }

  void _add(String model) {
    final cfg = service.config;
    final mode = cfg.piercingMode;
    _put(cfg.piercingRules.length, (
      model: model,
      mode: mode,
      name: switch (mode) {
        piercingModePrompt => cfg.piercingName,
        piercingModeTool => cfg.piercingToolName,
        _ => '',
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    final ruled = {for (final r in cfg.piercingRules) r.model};
    final free = [
      for (final m in _modelNames)
        if (!ruled.contains(m)) m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('按模型'), style: titleStyle),
                  Text(tr('这些模型单独设,盖过上面的'), style: hintStyle),
                ],
              ),
            ),
            _Pick(
              tooltip: tr('添加模型'),
              items: [for (final m in free) (m, m)],
              onPicked: _add,
              child: PennaChip(
                label: tr('+ 添加模型'),
                selected: false,
                onTap: null,
              ),
            ),
          ],
        ),
        for (final (i, r) in cfg.piercingRules.indexed) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.model,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              _Pick(
                tooltip: tr('模式'),
                items: _modeLabels.entries
                    .map((e) => (e.key, e.value))
                    .toList(),
                onPicked: (mode) => _put(i, (
                  model: r.model,
                  mode: mode,
                  name: _defaultName(cfg, mode),
                )),
                child: PennaChip(
                  label: _modeLabels[r.mode] ?? r.mode,
                  selected: true,
                  onTap: null,
                ),
              ),
              if (r.mode != piercingModeDocument) ...[
                const SizedBox(width: 6),
                _Pick(
                  tooltip: tr('用哪一段'),
                  items: _segments(cfg, r.mode),
                  onPicked: (name) =>
                      _put(i, (model: r.model, mode: r.mode, name: name)),
                  child: PennaChip(
                    label: _segmentLabel(cfg, r),
                    selected: false,
                    onTap: null,
                  ),
                ),
              ],
              IconButton(
                tooltip: tr('删除'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _put(i, null),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 段的名字;挑的那段删了时照它实际用的说(提示词用第一段、工具调用不用预设)。
  static String _segmentLabel(AppConfig cfg, PiercingRule r) {
    final names = _segments(cfg, r.mode);
    final hit = names.where((n) => n.$1 == r.name).firstOrNull;
    if (hit != null && hit.$2.isNotEmpty) return hit.$2;
    return r.mode == piercingModePrompt
        ? cfg.piercingSaved.firstOrNull?.name ?? tr('没有存下的段')
        : tr('不用预设');
  }
}

/// 点了弹出一列 [items](值, 显示的字)挑一个。
class _Pick extends StatelessWidget {
  const _Pick({
    required this.tooltip,
    required this.items,
    required this.onPicked,
    required this.child,
  });

  final String tooltip;
  final List<(String, String)> items;
  final ValueChanged<String> onPicked;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    popUpAnimationStyle: Motion.menu(context),
    tooltip: tooltip,
    enabled: items.isNotEmpty,
    position: PopupMenuPosition.under,
    constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
    onSelected: onPicked,
    itemBuilder: (_) => [
      for (final (value, label) in items)
        PopupMenuItem(
          value: value,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
    ],
    child: child,
  );
}
