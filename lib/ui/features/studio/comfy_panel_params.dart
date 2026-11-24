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

/// 模型文件那一行的名字。
String _fileLabel(String key) => switch (key) {
  'unet_name' => 'UNet',
  'ckpt_name' => 'Checkpoint',
  'vae_name' => 'VAE',
  _ => tr('文本编码器'),
};

/// [name] 在 [known](这台 ComfyUI 的名单;还没读到是 null)里对不上(见 [serverName])。
bool _missing(String name, List<String>? known) =>
    known != null && known.isNotEmpty && serverName(name, known) == null;

/// 侧栏里工作流的几样:模型文件(UNet、文本编码器、VAE,名单读眼前这台 ComfyUI 的;
/// 2026-11-23 用户要求开放修改)、画面大小、时长、采样器参数(默认收起)。
List<Widget> _params(
  BuildContext context,
  ComfyRunner runner,
  ComfyWorkflow wf,
  void Function(String?) report,
) {
  final models = fileSlots(wf);
  final size = latentSize(wf);
  final duration = durationSlot(wf);
  final samplers = samplerSlots(wf);
  return [
    if (models.isNotEmpty) _heading(tr('模型')),
    for (final m in models)
      if (_missing(m.value, runner.knownOptions(m.type, m.key)) case final gone)
        _ParamRow(
          label: _fileLabel(m.key),
          value: _short(m.value),
          warn: gone,
          tooltip: [
            m.value,
            m.type,
            if (gone) tr('这台 ComfyUI 里没有这个文件'),
          ].join('\n'),
          onTap: () async {
            final names = await runner.optionsFor(m.type, m.key);
            if (!context.mounted) return;
            final picked = await _pickName(context, _fileLabel(m.key), names);
            if (picked != null) {
              report(runner.edit((wf) => setInput(wf, m.node, m.key, picked)));
            }
          },
        ),
    if (size != null) ...[
      _heading(tr('画面大小')),
      _SizeMenu(runner: runner, size: size, report: report),
    ],
    if (duration != null) ...[
      _heading(tr('时长')),
      _ParamRow(
        label: duration.frames ? tr('帧数') : tr('秒'),
        value: '${duration.value}',
        onTap: () async {
          final asked = await _askText(
            context,
            duration.frames ? tr('帧数') : tr('时长(秒)'),
            initial: '${duration.value}',
          );
          final n = num.tryParse(asked?.trim() ?? '');
          if (n == null || n <= 0) return;
          report(
            runner.edit(
              (wf) => setInput(
                wf,
                duration.node,
                duration.key,
                duration.frames ? n.round() : n,
              ),
            ),
          );
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
  const _Fold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.open = false,
  });

  final String title;
  final List<Widget> children;

  /// 标题右边的按钮(在折叠箭头前面)。
  final Widget? trailing;

  /// 一开始是不是展开的。
  final bool open;

  @override
  State<_Fold> createState() => _FoldState();
}

// 侧栏是按需建的列表,滚出去会拆掉:留着,折没折起来才不会被重置。
class _FoldState extends State<_Fold> with AutomaticKeepAliveClientMixin {
  late bool _open = widget.open;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _column(context);
  }

  Widget _column(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => setState(() => _open = !_open),
        child: _heading(
          widget.title,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?widget.trailing,
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
            ],
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
    this.warn = false,
  });

  final String label, value;
  final String? tooltip;

  /// 值标成红的(这台 ComfyUI 里没有)。
  final bool warn;

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
                style: monoStyle.copyWith(
                  fontSize: 11.5,
                  color: warn ? PennaColors.diffDelText : null,
                ),
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
