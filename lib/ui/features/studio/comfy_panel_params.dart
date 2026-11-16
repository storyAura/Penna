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

/// 侧栏里工作流的几样:模型(只看,不能改:换模型就换工作流)、画面大小、
/// 采样器参数(默认收起)。
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
    for (final s in samplers)
      _Fold(
        key: ValueKey('sampler/${s.node}'),
        title: samplers.length > 1 ? '${tr('采样')} · #${s.node}' : tr('采样'),
        children: [
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
      ),
  ];
}

/// 一块参数:标题一行,点了展开 / 收起,默认收起。
class _Fold extends StatefulWidget {
  const _Fold({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  State<_Fold> createState() => _FoldState();
}

class _FoldState extends State<_Fold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => setState(() => _open = !_open),
        child: _heading(
          widget.title,
          AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: Motion.of(context, Motion.base),
            curve: Motion.expand,
            child: Icon(
              Icons.expand_more,
              size: 16,
              color: PennaColors.slate400,
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: Motion.of(context, Motion.base),
        curve: Motion.expand,
        alignment: Alignment.topCenter,
        child: _open
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              )
            : const SizedBox(width: double.infinity),
      ),
    ],
  );
}

/// 一行参数:左边名字,右边现在的值,点了改。
class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.label,
    required this.value,
    this.onTap,
    this.tooltip,
  });

  final String label, value;
  final String? tooltip;

  /// 点了改;null 是只看(没有笔的图标)。
  final VoidCallback? onTap;

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
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit_outlined, size: 12, color: PennaColors.slate400),
          ],
        ],
      ),
    ),
  );
}
