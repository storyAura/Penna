import 'package:flutter/material.dart';

import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_piercing.dart';
import 'settings_sections.dart';
import '../../../l10n/l10n.dart';

/// 一排 Preset 药丸;选中的就是当前使用的 Preset。
class PresetPicker extends StatelessWidget {
  const PresetPicker({super.key, required this.service});

  final ConfigService service;

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in cfg.presets)
          PennaChip(
            label: p.displayName,
            selected: p.id == cfg.activePreset.id,
            onTap: () => service.update(cfg.copyWith(activePresetId: p.id)),
          ),
      ],
    );
  }
}

/// Preset:管理人设(名称 + 系统提示),可以自己新建。
class PresetSection extends StatefulWidget {
  const PresetSection({super.key, required this.service});

  final ConfigService service;

  @override
  State<PresetSection> createState() => _PresetSectionState();
}

class _PresetSectionState extends State<PresetSection> {
  /// 恢复出厂后加一,用来重建输入框显示新文字。
  int _resets = 0;

  ConfigService get _service => widget.service;

  void _put(AgentPreset next) =>
      _service.update(_service.config.putPreset(next));

  /// 以当前 Preset 为底稿复制一份,用户再改。
  void _addFrom(AgentPreset source) {
    _service.update(
      _service.config.addPreset(
        source.copyWith(
          id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
          name: tr('{0} 副本', [source.name]),
        ),
      ),
    );
  }

  Future<void> _delete(AgentPreset preset) async {
    final ok = await confirmDelete(
      context,
      tr('删除 Preset「{0}」?', [preset.name]),
      tr('此操作不可撤销。'),
    );
    if (ok) _service.update(_service.config.removePreset(preset.id));
  }

  void _restore(AgentPreset preset) {
    setState(() => _resets++);
    _put(factoryPresets.firstWhere((p) => p.id == preset.id));
  }

  @override
  Widget build(BuildContext context) {
    final preset = _service.config.activePreset;
    final builtin = isFactoryPreset(preset.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Preset', tr('选中的即当前使用')),
        PresetPicker(service: _service),
        gap,
        Align(
          alignment: Alignment.centerLeft,
          child: PennaButton(
            label: tr('新建 Preset(复制当前)'),
            icon: Icons.add,
            background: PennaColors.primary,
            foreground: Colors.white,
            onPressed: () => _addFrom(preset),
          ),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!builtin) ...[
                PennaField(
                  key: ValueKey('name-${preset.id}'),
                  label: tr('名称'),
                  value: preset.name,
                  onChanged: (v) => _put(preset.copyWith(name: v)),
                ),
                gap,
              ],
              PennaField(
                // 换 Preset 或恢复出厂时重建输入框,否则会留着旧文字。
                key: ValueKey('prompt-${preset.id}-$_resets'),
                label: tr('系统提示'),
                maxLines: 10,
                value: preset.systemPrompt,
                onChanged: (v) => _put(preset.copyWith(systemPrompt: v)),
              ),
              gap,
              Align(
                alignment: Alignment.centerLeft,
                child: builtin
                    ? PennaButton(
                        label: tr('恢复出厂设置'),
                        icon: Icons.restart_alt,
                        background: PennaColors.slate100,
                        onPressed: () => _restore(preset),
                      )
                    : PennaButton(
                        label: tr('删除这个 Preset'),
                        icon: Icons.delete_outline,
                        background: PennaColors.diffDel,
                        foreground: PennaColors.diffDelText,
                        onPressed: () => _delete(preset),
                      ),
              ),
            ],
          ),
        ),
        gap,
        PiercingCard(service: _service),
      ],
    );
  }
}

/// 参数与工具:按 Preset 分别设置温度、工具白名单。
class AbilitySection extends StatelessWidget {
  const AbilitySection({super.key, required this.service});

  final ConfigService service;

  /// 一个能拖的参数:名字、它管什么、现在的值、滑条。
  List<Widget> _knob(String name, String hint, String value, Widget slider) => [
    Row(
      children: [
        Expanded(child: Text(name, style: titleStyle)),
        Text(value, style: titleStyle.copyWith(color: PennaColors.primary)),
      ],
    ),
    Text(hint, style: hintStyle),
    slider,
  ];

  @override
  Widget build(BuildContext context) {
    final preset = service.config.activePreset;
    void put(AgentPreset next) =>
        service.update(service.config.putPreset(next));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('技能与工具'), tr('按 Preset 分别设置')),
        PresetPicker(service: service),
        gap,
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._knob(
                tr('温度'),
                tr('选词有多大胆:低了每次都差不多,高了更有变化也更容易跑偏'),
                preset.temperature.toStringAsFixed(1),
                Slider(
                  value: preset.temperature,
                  max: 2,
                  divisions: 20,
                  onChanged: (v) => put(preset.copyWith(temperature: v)),
                ),
              ),
              const SizedBox(height: 6),
              ..._knob(
                'Top P',
                tr('候选词留多少:1 不限制,调低就只在最有把握的那些词里选'),
                preset.topP.toStringAsFixed(2),
                Slider(
                  value: preset.topP,
                  min: 0.1,
                  max: 1,
                  divisions: 18,
                  onChanged: (v) => put(preset.copyWith(topP: v)),
                ),
              ),
              Text(tr('两个都管随机,一般只调一个'), style: hintStyle),
            ],
          ),
        ),
        gap,
        OptionCard(
          title: tr('工具'),
          options: builtinTools,
          selected: preset.tools,
          onChanged: (s) => put(preset.copyWith(tools: s)),
        ),
      ],
    );
  }
}

/// 快捷操作:聊天框上方那排按钮,每个是一个名字加一句要发的话。
class QuickActionSection extends StatefulWidget {
  const QuickActionSection({super.key, required this.service});

  final ConfigService service;

  @override
  State<QuickActionSection> createState() => _QuickActionSectionState();
}

class _QuickActionSectionState extends State<QuickActionSection> {
  /// 增删后加一,用来重建输入框:行的位置变了,旧输入框里留着别的行的字。
  int _edits = 0;

  void _save(List<QuickAction> next, {bool rebuild = false}) {
    if (rebuild) setState(() => _edits++);
    final service = widget.service;
    service.update(
      service.config.copyWith(quickActions: List.unmodifiable(next)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.service.config.quickActions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('快捷操作'), tr('点一下接在聊天框末尾')),
        for (final (i, action) in actions.indexed) ...[
          PennaCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PennaField(
                  key: ValueKey('label-$_edits-$i'),
                  label: tr('名称'),
                  value: action.label,
                  onChanged: (v) => _save([
                    ...actions.take(i),
                    (label: v, prompt: action.prompt),
                    ...actions.skip(i + 1),
                  ]),
                ),
                gap,
                PennaField(
                  key: ValueKey('prompt-$_edits-$i'),
                  label: tr('提示词'),
                  maxLines: 3,
                  value: action.prompt,
                  onChanged: (v) => _save([
                    ...actions.take(i),
                    (label: action.label, prompt: v),
                    ...actions.skip(i + 1),
                  ]),
                ),
                gap,
                Align(
                  alignment: Alignment.centerLeft,
                  child: PennaButton(
                    label: tr('删除'),
                    icon: Icons.delete_outline,
                    background: PennaColors.diffDel,
                    foreground: PennaColors.diffDelText,
                    onPressed: () => _save([
                      ...actions.take(i),
                      ...actions.skip(i + 1),
                    ], rebuild: true),
                  ),
                ),
              ],
            ),
          ),
          gap,
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: PennaButton(
            label: tr('添加快捷操作'),
            icon: Icons.add,
            background: PennaColors.primary,
            foreground: Colors.white,
            onPressed: () => _save([
              ...actions,
              (label: tr('新操作'), prompt: ''),
            ], rebuild: true),
          ),
        ),
      ],
    );
  }
}

TextStyle get hintStyle => TextStyle(fontSize: 12, color: PennaColors.slate500);

/// 一组带说明的开关。
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title, style: titleStyle),
              const SizedBox(width: 8),
              Text(
                tr('已开 {0} / {1}', [selected.length, options.length]),
                style: hintStyle,
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final o in options)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(o.label), style: const TextStyle(fontSize: 13)),
                      Text(tr(o.hint), style: hintStyle),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: selected.contains(o.id),
                    onChanged: (on) => onChanged(
                      on ? {...selected, o.id} : ({...selected}..remove(o.id)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
