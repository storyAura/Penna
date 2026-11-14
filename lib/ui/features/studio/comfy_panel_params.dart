part of 'comfy_panel.dart';

/// 画面大小的几个常用档(SDXL 一类按一百万像素左右排的)。
const _sizePresets = <ComfySize>[
  (width: 1024, height: 1024),
  (width: 896, height: 1152),
  (width: 832, height: 1216),
  (width: 768, height: 1344),
  (width: 1152, height: 896),
  (width: 1216, height: 832),
  (width: 1344, height: 768),
];

String _sizeLabel(ComfySize s) => '${s.width} × ${s.height}';

/// 采样器参数显示的名字。
String _paramName(String key) => switch (key) {
  'steps' => tr('步数'),
  'cfg' => 'CFG',
  'sampler_name' => tr('采样器'),
  'scheduler' => tr('调度器'),
  'denoise' => tr('降噪'),
  _ => key,
};

/// 侧栏里改工作流的几样:模型、画面大小、采样器参数。
List<Widget> _params(
  BuildContext context,
  ComfyRunner runner,
  ComfyWorkflow wf,
  void Function(String?) report,
) {
  final models = modelSlots(wf);
  final size = latentSize(wf);
  final samplers = samplerSlots(wf);
  return [
    if (models.isNotEmpty) _heading(tr('模型')),
    for (final m in models)
      _ParamRow(
        label: m.key == 'unet_name' ? 'UNet' : 'Checkpoint',
        value: _short(m.value),
        tooltip: '${m.value}\n${m.type}',
        onTap: () async {
          final names = await runner.optionsFor(m.type, m.key);
          if (!context.mounted) return;
          final picked = await _pickName(context, tr('换模型'), names);
          if (picked != null) {
            report(runner.edit((wf) => setInput(wf, m.node, m.key, picked)));
          }
        },
      ),
    if (size != null) ...[
      _heading(tr('画面大小')),
      _Menu<String>(
        leading: Icon(
          Icons.aspect_ratio,
          size: 14,
          color: PennaColors.slate500,
        ),
        label: _sizeLabel(size),
        items: [
          for (final s in _sizePresets)
            (value: _sizeLabel(s), label: _sizeLabel(s)),
          (value: '', label: tr('自定义')),
        ],
        selected: _sizeLabel(size),
        onSelected: (picked) async {
          var next = _sizePresets
              .where((s) => _sizeLabel(s) == picked)
              .firstOrNull;
          if (next == null) {
            final asked = await _askText(
              context,
              tr('画面大小(宽x高)'),
              initial: '${size.width}x${size.height}',
            );
            final m = RegExp(r'^\s*(\d+)\s*[x×*]\s*(\d+)\s*$')
                .firstMatch(asked ?? '');
            if (m == null) return;
            next = (width: int.parse(m[1]!), height: int.parse(m[2]!));
          }
          final s = next;
          report(runner.edit((wf) => setLatentSize(wf, s)));
        },
      ),
    ],
    for (final s in samplers) ...[
      _heading(samplers.length > 1 ? '${tr('采样')} · #${s.node}' : tr('采样')),
      for (final MapEntry(:key, :value) in s.values.entries)
        _ParamRow(
          label: _paramName(key),
          value: '$value',
          onTap: () async {
            final Object? next;
            if (value is String) {
              final names = await runner.optionsFor(s.type, key);
              if (!context.mounted) return;
              next = await _pickName(context, _paramName(key), names);
            } else {
              final asked = await _askText(
                context,
                _paramName(key),
                initial: '$value',
              );
              next = num.tryParse(asked?.trim() ?? '');
            }
            if (next != null) {
              report(runner.edit((wf) => setInput(wf, s.node, key, next!)));
            }
          },
        ),
    ],
  ];
}

/// 一行参数:左边名字,右边现在的值,点了改。
class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.tooltip,
  });

  final String label, value;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: tooltip ?? '',
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: monoStyle.copyWith(fontSize: 11.5),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.edit_outlined, size: 12, color: PennaColors.slate400),
        ],
      ),
    ),
  );
}
