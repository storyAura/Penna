part of 'comfy_panel.dart';

/// 侧栏分辨率面板里宽高取它的倍数(视频模型多要 32 的倍数,图像模型也都认)。
const _comfySnap = 32;

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
      _SizeMenu(runner: runner, size: size, report: report),
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

/// 画面大小:点开是分辨率面板(拖动板定宽高,下面是存下的常用尺寸,能存能删)。
class _SizeMenu extends StatelessWidget {
  const _SizeMenu({
    required this.runner,
    required this.size,
    required this.report,
  });

  final ComfyRunner runner;
  final ComfySize size;
  final void Function(String?) report;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: MenuStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStatePropertyAll(PennaColors.card),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PennaColors.border),
        ),
      ),
      // 面板很高,往下弹会被挪上来盖住这个框,再点就收不回去:弹到侧栏左边,和框顶对齐。
      alignment: AlignmentDirectional.topStart,
    ),
    alignmentOffset: const Offset(-sizePanelWidth - 12, 0),
    menuChildren: [
      // MenuAnchor 自己不带动画:打开时从右往左轻轻浮出。
      PopIn.popover(
        from: Alignment.centerRight,
        child: ListenableBuilder(
          listenable: Listenable.merge([runner, runner.config]),
          builder: (context, _) {
            final wf = runner.workflow;
            final now = (wf == null ? null : latentSize(wf)) ?? size;
            return SizePanel(
              size: now,
              onSize: (s) => report(runner.edit((wf) => setLatentSize(wf, s))),
              sizes: runner.sizes,
              onSave: () => runner.saveSize(now),
              onRemove: runner.removeSize,
              maxSizes: ComfySettings.maxSizes,
              snap: () => _comfySnap,
            );
          },
        ),
      ),
    ],
    builder: (context, menu, _) => InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => menu.isOpen ? menu.close() : menu.open(),
      child: _menuBox(
        _sizeLabel(size),
        Icon(Icons.aspect_ratio, size: 14, color: PennaColors.slate500),
      ),
    ),
  );
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
