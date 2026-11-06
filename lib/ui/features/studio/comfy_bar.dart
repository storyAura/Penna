import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/harness/comfy_workflow.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_runner.dart';

const _closedWidth = 30.0;
const _openWidth = 300.0;

/// 多久测一次连接。
const _pollEvery = Duration(seconds: 20);

/// 权重按这么多一格加减。
const _strengthStep = 0.05;

/// 窗口右边的 ComfyUI 侧栏(工作台和区域控制都有):连接情况、当前工作流、模型和 LoRA。
/// 平时收成一条窄边,点开时盖在对话栏上。
class ComfyBar extends StatefulWidget {
  const ComfyBar({super.key, required this.runner, required this.config});

  final ComfyRunner runner;
  final ConfigService config;

  /// 收起时占多宽;外面排版要给它留出这一条。
  static const closedWidth = _closedWidth;

  @override
  State<ComfyBar> createState() => _ComfyBarState();
}

class _ComfyBarState extends State<ComfyBar> {
  bool _open = false;
  Timer? _poll;

  ComfyRunner get runner => widget.runner;

  @override
  void initState() {
    super.initState();
    unawaited(runner.check());
    _poll = Timer.periodic(_pollEvery, (_) => runner.check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    // 打开时把名单也重读一遍:ComfyUI 那边可能刚放进新模型。
    if (_open) unawaited(runner.check(full: true));
  }

  void _report(String? problem) {
    if (problem != null) showToast(context, problem, warn: true);
  }

  @override
  Widget build(BuildContext context) {
    final width = _open ? _openWidth : _closedWidth;
    return ListenableBuilder(
      listenable: Listenable.merge([runner, widget.config]),
      builder: (context, _) => AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        curve: Motion.swift,
        width: width,
        decoration: BoxDecoration(
          color: PennaColors.slate50,
          border: Border(left: BorderSide(color: PennaColors.border)),
          boxShadow: _open
              ? const [BoxShadow(color: Color(0x22000000), blurRadius: 14)]
              : null,
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topRight,
            minWidth: width,
            maxWidth: width,
            child: _open ? _panel() : _strip(),
          ),
        ),
      ),
    );
  }

  Color get _dot => switch (runner.status) {
    null => PennaColors.slate400,
    (connected: true, ms: _, version: _, error: _) => PennaColors.accent,
    _ => PennaColors.diffDelText,
  };

  String get _statusText => switch (runner.status) {
    null => tr('正在连接'),
    (connected: true, :final ms, version: _, error: _) => tr('已连接 · {0} ms', [
      ms,
    ]),
    (connected: false, :final error, ms: _, version: _) => error ?? tr('未连接'),
  };

  Widget _strip() => Tooltip(
    message: 'ComfyUI · $_statusText',
    child: InkWell(
      onTap: _toggle,
      child: SizedBox(
        height: 54,
        child: Column(
          children: [
            const SizedBox(height: 11),
            Icon(Icons.brush_outlined, size: 16, color: PennaColors.slate500),
            const SizedBox(height: 6),
            CircleAvatar(radius: 3.5, backgroundColor: _dot),
          ],
        ),
      ),
    ),
  );

  Widget _panel() {
    final wf = runner.workflow;
    final status = runner.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.brush_outlined, size: 16, color: PennaColors.slate500),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'ComfyUI',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: tr('刷新'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate500,
                icon: const Icon(Icons.refresh),
                onPressed: runner.checking
                    ? null
                    : () => runner.check(full: true),
              ),
              IconButton(
                tooltip: tr('收起'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.chevron_right),
                onPressed: _toggle,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 4, backgroundColor: _dot),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                ],
              ),
              if (status?.version.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(
                    widget.config.config.comfy.url,
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                ),
              _heading(tr('工作流')),
              Text(runner.workflowName, style: const TextStyle(fontSize: 12)),
              if (wf != null) ...[
                for (final slot in modelSlots(wf)) ..._model(slot),
                ..._loras(wf),
              ],
            ],
          ),
        ),
      ],
    );
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

  List<Widget> _model(ModelSlot slot) => [
    _heading(slot.key == 'unet_name' ? tr('扩散模型') : tr('模型')),
    _Choice(
      label: slot.value,
      onTap: () async {
        final picked = await _pickName(
          context,
          tr('换模型'),
          runner.optionsFor(slot.type, slot.key),
          slot.value,
        );
        if (picked == null) return;
        _report(runner.edit((wf) => setModel(wf, slot.node, slot.key, picked)));
      },
    ),
  ];

  List<Widget> _loras(ComfyWorkflow wf) {
    final slots = loraSlots(wf);
    return [
      _heading(
        slots.isEmpty ? 'LoRA' : 'LoRA · ${slots.length}',
        TextButton.icon(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
          icon: const Icon(Icons.add, size: 14),
          label: Text(tr('添加')),
          onPressed: () async {
            final picked = await _pickName(
              context,
              tr('添加 LoRA'),
              runner.loraOptions,
              null,
            );
            if (picked != null) {
              _report(runner.edit((wf) => addLora(wf, picked, 1)));
            }
          },
        ),
      ),
      for (final slot in slots)
        _LoraRow(
          key: ValueKey('${slot.node}/${slot.key}'),
          slot: slot,
          onOn: (on) => _report(
            runner.edit((wf) => setLora(wf, slot.node, slot.key, on: on)),
          ),
          onStrength: (v) => _report(
            runner.edit((wf) => setLora(wf, slot.node, slot.key, strength: v)),
          ),
          onRemove: () =>
              _report(runner.edit((wf) => removeLora(wf, slot.node, slot.key))),
        ),
    ];
  }
}

/// 文件名去掉文件夹,显示用。
String _short(String name) => name.split(RegExp(r'[\\/]')).last;

/// 点开换一个的按钮(模型)。
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: PennaColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: PennaColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _short(label),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Icon(Icons.unfold_more, size: 14, color: PennaColors.slate400),
          ],
        ),
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
              final v = await _askStrength(context, slot.strength);
              if (v != null) onStrength(_round(v));
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

/// 直接输入权重。
Future<double?> _askStrength(BuildContext context, double now) {
  final input = TextEditingController(text: now.toStringAsFixed(2));
  void submit(BuildContext context) =>
      Navigator.pop(context, double.tryParse(input.text.trim()));
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('权重'), style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 160,
        child: TextField(
          controller: input,
          autofocus: true,
          contextMenuBuilder: pennaTextMenu,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onSubmitted: (_) => submit(context),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        TextButton(onPressed: () => submit(context), child: Text(tr('确定'))),
      ],
    ),
  ).whenComplete(input.dispose);
}

/// 从一长串文件名里挑一个,上面能搜。
Future<String?> _pickName(
  BuildContext context,
  String title,
  List<String> names,
  String? current,
) {
  if (names.isEmpty) {
    showToast(context, tr('还没读到 ComfyUI 里的名单,先点刷新'), warn: true);
    return Future.value();
  }
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _NamePicker(title: title, names: names, current: current),
  );
}

class _NamePicker extends StatefulWidget {
  const _NamePicker({
    required this.title,
    required this.names,
    required this.current,
  });

  final String title;
  final List<String> names;
  final String? current;

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
                    selected: n == widget.current,
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
