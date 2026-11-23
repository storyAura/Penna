part of 'comfy_panel.dart';

/// 各种素材显示的名字和图标。
(String, IconData) _kindLook(String kind) => switch (kind) {
  'video' => (tr('视频'), Icons.movie_outlined),
  'audio' => (tr('音频'), Icons.graphic_eq),
  _ => (tr('图像'), Icons.image_outlined),
};

/// 图片文件的宽高(只读文件头);读不了是 null。
Future<ComfySize?> _imageSize(String path) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await File(path).readAsBytes(),
    );
    final image = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: image.width, height: image.height);
    image.dispose();
    buffer.dispose();
    return size;
  } on Object {
    return null;
  }
}

/// 要上传的素材:工作流里有几个加载图片 / 视频 / 音频的节点就有几行。
/// 工作流能改画面大小时,选好的图旁边有「用这张图的尺寸」。
List<Widget> _uploads(
  BuildContext context,
  ComfyRunner runner,
  ComfyWorkflow wf,
  void Function(String?) report,
) {
  final slots = runner.uploads;
  if (slots.isEmpty) return const [];
  final files = runner.uploadFiles;
  final sized = latentSize(wf) != null;
  return [
    _heading('${tr('上传素材')} · ${slots.length}'),
    for (final (i, slot) in slots.indexed)
      _UploadRow(
        key: ValueKey(slot.node),
        slot: slot,
        number: i + 1,
        file: files[slot.node],
        onPick: () async {
          final picked = await openFile(
            acceptedTypeGroups: [
              XTypeGroup(
                label: _kindLook(slot.kind).$1,
                extensions: uploadExtensions[slot.kind],
              ),
            ],
          );
          if (picked != null) runner.setUpload(slot.node, picked.path);
        },
        onClear: () => runner.setUpload(slot.node, null),
        onPreview: (path) =>
            showImageViewer(context, comfyImageAttachment(path), shown: true),
        // ponytail: 照图片原尺寸(取 8 的倍数),大图出图也大;要按面积缩时再加。
        onUseSize: !sized
            ? null
            : (path) async {
                final size = await _imageSize(path);
                report(
                  size == null
                      ? tr('读不了这张图的尺寸')
                      : runner.edit((wf) => setLatentSize(wf, size)),
                );
              },
      ),
  ];
}

/// 一个要上传的素材:图标、名字(节点标题,没有时是「图片 1」)、选的文件;
/// 没选时灰字显示工作流里原来写的。点了选文件,叉掉回到原来的;
/// 选好的图点缩略图看大图,[onUseSize] 把画面大小改成这张图的。
class _UploadRow extends StatelessWidget {
  const _UploadRow({
    super.key,
    required this.slot,
    required this.number,
    required this.file,
    required this.onPick,
    required this.onClear,
    required this.onPreview,
    required this.onUseSize,
  });

  final UploadSlot slot;
  final int number;
  final String? file;
  final VoidCallback onPick, onClear;
  final ValueChanged<String> onPreview;
  final ValueChanged<String>? onUseSize;

  @override
  Widget build(BuildContext context) {
    final (kind, icon) = _kindLook(slot.kind);
    final title = slot.title.isEmpty || slot.title == slot.type
        ? '$kind $number'
        : slot.title;
    final chosen = file;
    final picture = chosen != null && slot.kind == 'image';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          children: [
            if (picture)
              Tooltip(
                message: tr('查看大图'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(3),
                  onTap: () => onPreview(chosen),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.file(
                      File(chosen),
                      width: 24,
                      height: 24,
                      cacheWidth: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(icon, size: 16, color: PennaColors.slate500),
                    ),
                  ),
                ),
              )
            else
              SizedBox.square(
                dimension: 24,
                child: Icon(icon, size: 16, color: PennaColors.slate500),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: '${chosen ?? slot.value}\n${slot.type} #${slot.node}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      chosen == null && slot.value.trim().isEmpty
                          ? tr('可选')
                          : _short(chosen ?? slot.value),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: chosen == null
                            ? PennaColors.slate400
                            : PennaColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (picture && onUseSize != null)
              IconButton(
                tooltip: tr('用这张图的尺寸'),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.aspect_ratio),
                onPressed: () => onUseSize!(chosen),
              ),
            if (chosen != null)
              IconButton(
                tooltip: tr('不传,用工作流里的'),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.close),
                onPressed: onClear,
              )
            else
              Icon(Icons.upload_file, size: 14, color: PennaColors.slate400),
          ],
        ),
      ),
    );
  }
}

/// 能拖着排的下拉(LoRA 配置、工作流):点一项就用它,按住把手拖着换顺序;
/// 给了 [onRemove] 每项后面有叉,给了 [onCreate] 最后一项是「新建」。
class _PresetMenu extends StatelessWidget {
  const _PresetMenu({
    required this.label,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.onReorder,
    this.onCreate,
    this.onRemove,
    this.icon,
    this.warnings = const {},
  });

  final String label;
  final List<({String value, String label})> items;

  /// 有问题的项(值 → 悬停时看的原因),后面画一个红色的感叹号。
  final Map<String, String> warnings;
  final String? selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<String>? onRemove;
  final VoidCallback? onCreate;
  final IconData? icon;

  /// 第 from 个挪到第 to 个(挪完之后的位置)。
  final void Function(int from, int to) onReorder;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final picked = await showMenu<String>(
      context: context,
      popUpAnimationStyle: Motion.menu(context),
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      items: [
        _ReorderEntry(
          items: items,
          warnings: warnings,
          selected: selected,
          onRemove: onRemove,
          onReorder: onReorder,
        ),
        if (onCreate != null)
          PopupMenuItem<String>(
            value: '',
            height: 34,
            child: Row(
              children: [
                Icon(Icons.add, size: 14, color: PennaColors.primary),
                const SizedBox(width: 6),
                Text(tr('新建'), style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );
    if (picked == null) return;
    picked.isEmpty ? onCreate?.call() : onSelected(picked);
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _open(context),
      child: _menuBox(
        label,
        icon == null ? null : Icon(icon, size: 14, color: PennaColors.slate500),
      ),
    ),
  );
}

/// 弹出菜单里能拖着排的那几项。顺序在这里先换(菜单不会跟着外面重建),同时交出去存。
class _ReorderEntry extends PopupMenuEntry<String> {
  const _ReorderEntry({
    required this.items,
    required this.selected,
    required this.onRemove,
    required this.onReorder,
    this.warnings = const {},
  });

  final List<({String value, String label})> items;
  final Map<String, String> warnings;
  final String? selected;
  final ValueChanged<String>? onRemove;
  final void Function(int from, int to) onReorder;

  @override
  double get height => 34.0 * items.length;

  @override
  bool represents(String? value) => items.any((i) => i.value == value);

  @override
  State<_ReorderEntry> createState() => _ReorderEntryState();
}

class _ReorderEntryState extends State<_ReorderEntry> {
  late var _items = [...widget.items];

  // 定死宽高:弹出菜单要先量各项的固有宽度,可滚动的列表量不出来,
  // 定死了菜单就直接用这个尺寸,不往里量。
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    height: widget.height,
    child: ReorderableListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _items.length,
      onReorderItem: (from, to) {
        setState(() => _items = moved(_items, from, to));
        widget.onReorder(from, to);
      },
      itemBuilder: (context, i) {
        final (:value, :label) = _items[i];
        return SizedBox(
          key: ValueKey(value),
          height: 34,
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: i,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 14,
                      color: PennaColors.slate400,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.pop(context, value),
                  child: SizedBox.expand(
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          size: 14,
                          color: value == widget.selected
                              ? PennaColors.primary
                              : Colors.transparent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        if (widget.warnings[value] case final why?)
                          Tooltip(
                            message: why,
                            child: Icon(
                              Icons.error_outline,
                              size: 14,
                              color: PennaColors.diffDelText,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.onRemove case final remove?)
                IconButton(
                  tooltip: tr('删除'),
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  color: PennaColors.slate400,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    remove(value);
                    Navigator.pop(context);
                  },
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        );
      },
    ),
  );
}
