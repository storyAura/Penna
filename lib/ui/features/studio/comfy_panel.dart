import 'package:flutter/material.dart';

import '../../../core/harness/comfy_workflow.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_runner.dart';

/// 权重按这么多一格加减。
const _strengthStep = 0.05;

/// 状态圆点的颜色:连上绿、连不上红、还没测灰。
Color comfyDot(ComfyStatus? status) => switch (status) {
  null => PennaColors.slate400,
  (connected: true, ms: _, version: _, error: _) => PennaColors.accent,
  _ => PennaColors.diffDelText,
};

/// 状态一句话:已连接 · 13 ms / 原因。
String comfyStatusText(ComfyStatus? status) => switch (status) {
  null => tr('正在连接'),
  (connected: true, :final ms, version: _, error: _) => tr('已连接 · {0} ms', [
    ms,
  ]),
  (connected: false, :final error, ms: _, version: _) => error ?? tr('未连接'),
};

/// 侧栏里的 ComfyUI:换哪台、换工作流、LoRA 配置和每个 LoRA。
class ComfyPanel extends StatelessWidget {
  const ComfyPanel({super.key, required this.runner, required this.config});

  final ComfyRunner runner;
  final ConfigService config;

  @override
  Widget build(BuildContext context) {
    void report(String? problem) {
      if (problem != null) showToast(context, problem, warn: true);
    }

    final comfy = config.config.comfy;
    final wf = runner.workflow;
    final models = wf == null ? const <ModelSlot>[] : modelSlots(wf);
    return ListView(
      // 底下多留一截:窗口右下角盖着一行版本号。
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        _heading('ComfyUI'),
        _Menu<String>(
          leading: CircleAvatar(
            radius: 4,
            backgroundColor: comfyDot(runner.status),
          ),
          label: tr(comfy.server.name),
          items: [
            for (final s in comfy.servers) (value: s.id, label: tr(s.name)),
          ],
          selected: comfy.serverId,
          onSelected: runner.selectServer,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Text(
            '${comfyStatusText(runner.status)} · ${comfy.server.url}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: PennaColors.slate500),
          ),
        ),
        _heading(tr('工作流')),
        _Menu<String>(
          label: runner.workflowName,
          items: [
            for (final f in runner.flowChoices) (value: f.id, label: f.name),
          ],
          selected: runner.flowId,
          onSelected: runner.selectFlow,
        ),
        for (final m in models)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Tooltip(
              message: m.value,
              child: Text(
                m.value.split(RegExp(r'[\\/]')).last,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: PennaColors.slate500),
              ),
            ),
          ),
        if (wf != null) ..._loras(context, wf, comfy, report),
      ],
    );
  }

  List<Widget> _loras(
    BuildContext context,
    ComfyWorkflow wf,
    ComfySettings comfy,
    void Function(String?) report,
  ) {
    final slots = loraSlots(wf);
    return [
      _heading(
        slots.isEmpty ? 'LoRA' : 'LoRA · ${slots.length}',
        // 用 PennaButton:TextButton 自己给的字体样式会盖掉 Penna 的字体。
        PennaButton(
          icon: Icons.add,
          label: tr('添加'),
          foreground: PennaColors.primary,
          onPressed: () async {
            final picked = await _pickName(
              context,
              tr('添加 LoRA'),
              runner.loraOptions,
            );
            if (picked != null) {
              report(runner.edit((wf) => addLora(wf, picked, 1)));
            }
          },
        ),
      ),
      // 存好的几套 LoRA:点一套就换成它的名单;最后一项「新建」把眼前的存成一套。
      // 旁边的保存把改动存回眼前这一套。
      Row(
        children: [
          Expanded(
            child: _Menu<String>(
              leading: Icon(
                Icons.layers_outlined,
                size: 14,
                color: PennaColors.slate500,
              ),
              label: runner.loraPreset?.name ?? tr('LoRA 配置'),
              items: [
                for (final p in comfy.loraPresets)
                  (value: p.name, label: p.name),
                (value: '', label: tr('新建')),
              ],
              selected: runner.loraPreset?.name,
              onSelected: (name) async {
                if (name.isNotEmpty) {
                  final preset = comfy.loraPresets.firstWhere(
                    (p) => p.name == name,
                  );
                  report(runner.applyLoraPreset(preset));
                  return;
                }
                final asked = await _askText(context, tr('存成一套 LoRA 配置'));
                if (asked != null) report(runner.saveLoraPreset(asked));
              },
              onRemove: runner.removeLoraPreset,
            ),
          ),
          if (runner.loraPreset case final preset?)
            IconButton(
              tooltip: tr('保存'),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: PennaColors.primary,
              icon: const Icon(Icons.save_outlined),
              onPressed: runner.loraPresetChanged
                  ? () {
                      final problem = runner.saveLoraPreset(preset.name);
                      problem == null
                          ? showToast(context, tr('已保存'))
                          : report(problem);
                    }
                  : null,
            ),
        ],
      ),
      const SizedBox(height: 6),
      for (final slot in slots)
        _LoraRow(
          key: ValueKey('${slot.node}/${slot.key}'),
          slot: slot,
          onOn: (on) => report(
            runner.edit((wf) => setLora(wf, slot.node, slot.key, on: on)),
          ),
          onStrength: (v) => report(
            runner.edit((wf) => setLora(wf, slot.node, slot.key, strength: v)),
          ),
          onRemove: () =>
              report(runner.edit((wf) => removeLora(wf, slot.node, slot.key))),
        ),
    ];
  }
}

Widget _heading(String text, [Widget? trailing]) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PennaColors.slate500,
          ),
        ),
      ),
      ?trailing,
    ],
  ),
);

/// 文件名去掉文件夹,显示用。
String _short(String name) => name.split(RegExp(r'[\\/]')).last;

/// 下拉选择框:显示 [label],点开列出 [items],[selected] 那项打勾。
/// 给了 [onRemove] 时每项(值不为空的)后面有个叉。
class _Menu<T extends Object> extends StatelessWidget {
  const _Menu({
    required this.label,
    required this.items,
    required this.onSelected,
    this.selected,
    this.leading,
    this.onRemove,
  });

  final String label;
  final List<({T value, String label})> items;
  final T? selected;
  final ValueChanged<T> onSelected;
  final Widget? leading;
  final ValueChanged<T>? onRemove;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    popUpAnimationStyle: Motion.menu(context),
    tooltip: '',
    position: PopupMenuPosition.under,
    constraints: const BoxConstraints(
      minWidth: 220,
      maxWidth: 300,
      maxHeight: 420,
    ),
    onSelected: onSelected,
    itemBuilder: (menu) => [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          height: 34,
          child: Row(
            children: [
              Icon(
                Icons.check,
                size: 14,
                color: item.value == selected
                    ? PennaColors.primary
                    : Colors.transparent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (onRemove != null && item.value != '')
                IconButton(
                  tooltip: tr('删除'),
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  color: PennaColors.slate400,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    onRemove!(item.value);
                    Navigator.pop(menu);
                  },
                ),
            ],
          ),
        ),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: PennaColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PennaColors.border),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Icon(Icons.unfold_more, size: 14, color: PennaColors.slate400),
        ],
      ),
    ),
  );
}

/// 一个 LoRA:开关(加载器有开关时)、名字、权重(− 数字 +)、去掉。
class _LoraRow extends StatelessWidget {
  const _LoraRow({
    super.key,
    required this.slot,
    required this.onOn,
    required this.onStrength,
    required this.onRemove,
  });

  final LoraSlot slot;
  final ValueChanged<bool> onOn;
  final ValueChanged<double> onStrength;
  final VoidCallback onRemove;

  double _round(double v) => (v * 100).round() / 100;

  @override
  Widget build(BuildContext context) {
    final muted = !slot.on;
    final step = IconButton.styleFrom(
      minimumSize: const Size(22, 22),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (slot.canToggle)
            SizedBox.square(
              dimension: 22,
              child: Checkbox(
                value: slot.on,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => onOn(v ?? false),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Tooltip(
              message: '${slot.name}\n${slot.type}',
              child: Text(
                _short(slot.name),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: muted ? PennaColors.slate400 : PennaColors.text,
                ),
              ),
            ),
          ),
          IconButton(
            style: step,
            iconSize: 14,
            tooltip: '−$_strengthStep',
            icon: const Icon(Icons.remove),
            onPressed: () => onStrength(_round(slot.strength - _strengthStep)),
          ),
          InkWell(
            onTap: () async {
              final v = await _askText(
                context,
                tr('权重'),
                initial: slot.strength.toStringAsFixed(2),
              );
              final n = double.tryParse(v?.trim() ?? '');
              if (n != null) onStrength(_round(n));
            },
            child: SizedBox(
              width: 36,
              child: Text(
                slot.strength.toStringAsFixed(2),
                textAlign: TextAlign.center,
                style: monoStyle.copyWith(
                  fontSize: 11.5,
                  color: muted ? PennaColors.slate400 : PennaColors.text,
                ),
              ),
            ),
          ),
          IconButton(
            style: step,
            iconSize: 14,
            tooltip: '+$_strengthStep',
            icon: const Icon(Icons.add),
            onPressed: () => onStrength(_round(slot.strength + _strengthStep)),
          ),
          IconButton(
            style: step,
            iconSize: 14,
            tooltip: tr('去掉'),
            color: PennaColors.slate400,
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// 问一行字(权重、配置名);取消返回 null。
Future<String?> _askText(
  BuildContext context,
  String title, {
  String initial = '',
}) {
  final input = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 260,
        child: TextField(
          controller: input,
          autofocus: true,
          contextMenuBuilder: pennaTextMenu,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, input.text),
          child: Text(tr('确定')),
        ),
      ],
    ),
  ).whenComplete(input.dispose);
}

/// 从一长串文件名里挑一个,上面能搜。
Future<String?> _pickName(
  BuildContext context,
  String title,
  List<String> names,
) {
  if (names.isEmpty) {
    showToast(context, tr('还没读到 ComfyUI 里的名单,先点刷新'), warn: true);
    return Future.value();
  }
  return showDialog<String>(
    context: context,
    builder: (context) => _NamePicker(title: title, names: names),
  );
}

class _NamePicker extends StatefulWidget {
  const _NamePicker({required this.title, required this.names});

  final String title;
  final List<String> names;

  @override
  State<_NamePicker> createState() => _NamePickerState();
}

class _NamePickerState extends State<_NamePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final words = _query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    final shown = [
      for (final n in widget.names)
        if (words.every(n.toLowerCase().contains)) n,
    ];
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              contextMenuBuilder: pennaTextMenu,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: tr('搜索'),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final n = shown[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      _short(n),
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: n == _short(n)
                        ? null
                        : Text(n, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(context, n),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
      ],
    );
  }
}
