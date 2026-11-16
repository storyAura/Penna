part of 'comfy_panel.dart';

/// 各种素材显示的名字和图标。
(String, IconData) _kindLook(String kind) => switch (kind) {
  'video' => (tr('视频'), Icons.movie_outlined),
  'audio' => (tr('音频'), Icons.graphic_eq),
  _ => (tr('图像'), Icons.image_outlined),
};

/// 要上传的素材:工作流里有几个加载图片 / 视频 / 音频的节点就有几行。
List<Widget> _uploads(BuildContext context, ComfyRunner runner) {
  final slots = runner.uploads;
  if (slots.isEmpty) return const [];
  final files = runner.uploadFiles;
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
      ),
  ];
}

/// 一个要上传的素材:图标、名字(节点标题,没有时是「图片 1」)、选的文件;
/// 没选时灰字显示工作流里原来写的。点了选文件,叉掉回到原来的。
class _UploadRow extends StatelessWidget {
  const _UploadRow({
    super.key,
    required this.slot,
    required this.number,
    required this.file,
    required this.onPick,
    required this.onClear,
  });

  final UploadSlot slot;
  final int number;
  final String? file;
  final VoidCallback onPick, onClear;

  @override
  Widget build(BuildContext context) {
    final (kind, icon) = _kindLook(slot.kind);
    final title = slot.title.isEmpty || slot.title == slot.type
        ? '$kind $number'
        : slot.title;
    final chosen = file;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          children: [
            if (chosen != null && slot.kind == 'image')
              ClipRRect(
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
                      _short(chosen ?? slot.value),
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

/// LoRA 配置的下拉:点一套就用它,叉掉删除,按住把手拖着换顺序,最后一项「新建」。
class _PresetMenu extends StatelessWidget {
  const _PresetMenu({
    required this.label,
    required this.names,
    required this.selected,
    required this.onSelected,
    required this.onCreate,
    required this.onRemove,
    required this.onReorder,
  });

  final String label;
  final List<String> names;
  final String? selected;
  final ValueChanged<String> onSelected, onRemove;
  final VoidCallback onCreate;

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
          names: names,
          selected: selected,
          onRemove: onRemove,
          onReorder: onReorder,
        ),
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
    picked.isEmpty ? onCreate() : onSelected(picked);
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _open(context),
      child: _menuBox(
        label,
        Icon(Icons.layers_outlined, size: 14, color: PennaColors.slate500),
      ),
    ),
  );
}

/// 弹出菜单里能拖着排的那几项。顺序在这里先换(菜单不会跟着外面重建),同时交出去存。
class _ReorderEntry extends PopupMenuEntry<String> {
  const _ReorderEntry({
    required this.names,
    required this.selected,
    required this.onRemove,
    required this.onReorder,
  });

  final List<String> names;
  final String? selected;
  final ValueChanged<String> onRemove;
  final void Function(int from, int to) onReorder;

  @override
  double get height => 34.0 * names.length;

  @override
  bool represents(String? value) => names.contains(value);

  @override
  State<_ReorderEntry> createState() => _ReorderEntryState();
}

class _ReorderEntryState extends State<_ReorderEntry> {
  late List<String> _names = [...widget.names];

  // 定死宽高:弹出菜单要先量各项的固有宽度,可滚动的列表量不出来,
  // 定死了菜单就直接用这个尺寸,不往里量。
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    height: widget.height,
    child: ReorderableListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _names.length,
      onReorderItem: (from, to) {
        setState(() => _names = moved(_names, from, to));
        widget.onReorder(from, to);
      },
      itemBuilder: (context, i) {
        final name = _names[i];
        return SizedBox(
          key: ValueKey(name),
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
                  onTap: () => Navigator.pop(context, name),
                  child: SizedBox.expand(
                    child: Row(
                      children: [
                        Icon(
                          Icons.check,
                          size: 14,
                          color: name == widget.selected
                              ? PennaColors.primary
                              : Colors.transparent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('删除'),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.close),
                onPressed: () {
                  widget.onRemove(name);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}
