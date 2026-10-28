part of 'layout_page.dart';

/// 左边一栏:顶上一直是交出去的 JSON(不跟着滚),下面是整体描述和各块。
/// 各块像 PS 的图层面板:从上到下就是从前到后(序号 1 在最前),默认折叠成一行,
/// 按住把手上下拖换前后,点箭头展开改内容。
class _Properties extends StatelessWidget {
  const _Properties({
    required this.board,
    required this.config,
    required this.onDiscuss,
    required this.onToDraft,
    required this.cardKey,
    required this.fieldFocus,
    required this.isOpen,
    required this.onToggle,
    required this.onMove,
    required this.onDelete,
  });

  final LayoutBoard board;

  /// 质量词存在设置里(所有布局共用)。
  final ConfigService config;

  /// 带着第几块去右边的对话里改。
  final ValueChanged<int> onDiscuss;
  final VoidCallback onToDraft;

  /// 第几块的卡片和它正文输入框的焦点:画布上点框、双击框时用。
  final GlobalKey Function(int) cardKey;
  final FocusNode Function(int) fieldFocus;

  /// 第几块展开着;点箭头切换。
  final bool Function(int) isOpen;
  final ValueChanged<int> onToggle;

  /// 拖着换前后:从第几个挪到第几个(按挪走之后的列表数)。
  final void Function(int from, int to) onMove;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final count = board.layout.boxes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          // 质量词改了 JSON 也跟着变。
          child: ListenableBuilder(
            listenable: config,
            builder: (context, _) =>
                _JsonCard(board: board, onToDraft: onToDraft),
          ),
        ),
        Expanded(
          // 外层不用 ListView:它不建看不见的卡片,画布上点了框就滚不过去。
          child: SmoothScroller(
            builder: (controller) => SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryCard(board: board, config: config),
                  if (count > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
                      child: Text(
                        tr('图层'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: PennaColors.slate500,
                        ),
                      ),
                    ),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: count,
                    // 给的落点已经按挪走之后的列表算好。
                    onReorderItem: onMove,
                    itemBuilder: (context, i) => Padding(
                      key: cardKey(i),
                      padding: const EdgeInsets.only(top: 8),
                      child: _BoxCard(
                        board: board,
                        index: i,
                        open: isOpen(i),
                        focus: fieldFocus(i),
                        onToggle: () => onToggle(i),
                        onDiscuss: () => onDiscuss(i),
                        onDelete: () => onDelete(i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.board, required this.config});

  final LayoutBoard board;
  final ConfigService config;

  @override
  Widget build(BuildContext context) {
    final l = board.layout;
    final r = board.revision;
    return PennaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PennaField(
            label: tr('质量词'),
            value: config.config.layoutQuality,
            maxLines: 2,
            onChanged: (v) =>
                config.update(config.config.copyWith(layoutQuality: v)),
          ),
          const SizedBox(height: 10),
          PennaField(
            key: ValueKey('style-$r'),
            label: tr('画风'),
            value: l.style,
            maxLines: 3,
            hint: tr('画法、线条、上色、配色'),
            onChanged: (v) => board.setSummary(style: v),
          ),
          const SizedBox(height: 10),
          PennaField(
            key: ValueKey('cast-$r'),
            label: tr('角色卡'),
            value: castText(l.cast),
            maxLines: 4,
            hint: tr('一行一个 · 名字: 英文外貌和服装'),
            onChanged: (v) => board.setCast(parseCastText(v)),
          ),
          const SizedBox(height: 10),
          PennaField(
            key: ValueKey('caption-$r'),
            label: tr('整体描述'),
            value: l.caption,
            maxLines: 4,
            hint: tr('画面整体的场景'),
            onChanged: (v) => board.setSummary(caption: v),
          ),
          const SizedBox(height: 10),
          PennaField(
            key: ValueKey('meta-$r'),
            label: tr('类型'),
            value: l.meta,
            hint: 'poster, illustration',
            onChanged: (v) => board.setSummary(meta: v),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in layoutCanvases)
                PennaChip(
                  label: c,
                  selected: l.canvas == c,
                  onTap: () => board.setSummary(canvas: c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 图层面板里的一块:折叠时是一行(把手、序号、名字、前中后景、操作),
/// 展开后才是类别、前中后景、名字和描述这些输入。
class _BoxCard extends StatelessWidget {
  const _BoxCard({
    required this.board,
    required this.index,
    required this.open,
    required this.focus,
    required this.onToggle,
    required this.onDiscuss,
    required this.onDelete,
  });

  final LayoutBoard board;
  final int index;
  final bool open;

  /// 正文输入框的焦点:文字块是「文字内容」,别的是「这一块的描述」。
  final FocusNode focus;
  final VoidCallback onToggle;
  final VoidCallback onDiscuss;
  final VoidCallback onDelete;

  /// 输入框里改的是这一块最新的样子,不是画这张卡片时的。
  void _edit(LayoutBox Function(LayoutBox) change) =>
      board.updateBox(index, change(board.layout.boxes[index]));

  Widget _icon(IconData icon, String tip, VoidCallback onPressed) => IconButton(
    tooltip: tip,
    iconSize: 16,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon),
    onPressed: onPressed,
  );

  /// 折叠时那一行。[shown] 为假时这一块在画布上屏蔽着:名字变淡,眼睛是闭着的。
  Widget _header(LayoutBox b, Color color, bool shown) => Row(
    children: [
      ReorderableDragStartListener(
        index: index,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Tooltip(
            message: tr('拖动换前后'),
            child: Icon(
              Icons.drag_indicator,
              size: 18,
              color: PennaColors.slate400,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        color: color,
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          b.name.trim().isEmpty ? layoutLabelName(b.label) : b.name.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: shown ? null : PennaColors.slate400,
          ),
        ),
      ),
      Text(
        layoutLayerName(b.layer),
        style: TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
      // 转到镜头外的块在画布上本来就看不见,眼睛闭着、点不动。
      IconButton(
        tooltip: b.offscreen
            ? tr('在镜头外')
            : shown
            ? tr('在画布上屏蔽')
            : tr('在画布上显示'),
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          shown ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: b.offscreen ? null : () => board.setHidden(index, shown),
      ),
      IconButton(
        tooltip: b.locked ? tr('解锁') : tr('锁定(画布上拖不动)'),
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        color: b.locked ? PennaColors.primary : null,
        icon: Icon(b.locked ? Icons.lock : Icons.lock_open_outlined),
        onPressed: () => board.setLocked(index, !b.locked),
      ),
      _icon(
        open ? Icons.expand_less : Icons.expand_more,
        open ? tr('收起') : tr('展开'),
        onToggle,
      ),
      _icon(Icons.chat_bubble_outline, tr('讨论'), onDiscuss),
      _icon(Icons.close, tr('删除'), onDelete),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final b = board.layout.boxes[index];
    final r = board.revision;
    final selected = board.selected == index;
    final color = layoutBoxColor(index);
    return GestureDetector(
      onTap: () => board.select(index),
      child: PennaCard(
        padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
        borderColor: selected ? color : null,
        child: AnimatedSize(
          duration: Motion.base,
          curve: Motion.swift,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(b, color, board.shown(index)),
              if (open)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  child: _details(b, r),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 换形状(记一笔操作);框不动,交出去的还是这个方框。
  void _setShape(LayoutBox b, LayoutShape? shape) {
    board.mark(tr('调整「{0}」的形状', [boxName(b, index)]));
    _edit((b) => b.copyWith(shape: () => shape));
  }

  /// 方框 / 椭圆 / 多边形;多边形再调顶点数(换成那么多边的正多边形)。
  Widget _shapeRow(LayoutBox b) {
    final s = b.shape;
    final n = s?.points.length ?? 0;
    return Row(
      children: [
        PennaChip(
          label: tr('方框'),
          selected: s == null,
          onTap: () => _setShape(b, null),
        ),
        const SizedBox(width: 4),
        PennaChip(
          label: tr('椭圆'),
          selected: s?.isEllipse ?? false,
          onTap: () => _setShape(b, const LayoutShape.ellipse()),
        ),
        const SizedBox(width: 4),
        PennaChip(
          label: tr('多边形'),
          selected: n > 0,
          onTap: n > 0 ? () {} : () => _setShape(b, LayoutShape.regular(5)),
        ),
        if (n > 0) ...[
          _icon(Icons.remove, tr('少一个顶点'), () {
            if (n > minShapePoints) _setShape(b, LayoutShape.regular(n - 1));
          }),
          Text('$n', style: const TextStyle(fontSize: 12)),
          _icon(Icons.add, tr('多一个顶点'), () {
            if (n < maxShapePoints) _setShape(b, LayoutShape.regular(n + 1));
          }),
        ],
      ],
    );
  }

  /// 展开后的那些输入。
  Widget _details(LayoutBox b, int r) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          for (final label in layoutLabels) ...[
            PennaChip(
              label: layoutLabelName(label),
              selected: b.label == label,
              onTap: () => _edit((b) => b.copyWith(label: label)),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          for (final layer in layoutLayers.reversed) ...[
            PennaChip(
              label: layoutLayerName(layer),
              selected: b.layer == layer,
              onTap: () => _edit((b) => b.copyWith(layer: layer)),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
      const SizedBox(height: 6),
      _shapeRow(b),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'x ${b.left}  y ${b.top}  ·  ${b.width}×${b.height}',
          style: TextStyle(fontSize: 11, color: PennaColors.slate500),
        ),
      ),
      PennaField(
        key: ValueKey('name-$r-$index'),
        label: tr('名字'),
        value: b.name,
        hint: tr('例如 主角、标题、背景山'),
        onChanged: (v) => _edit((b) => b.copyWith(name: v)),
      ),
      const SizedBox(height: 8),
      if (b.label == 'text') ...[
        PennaField(
          key: ValueKey('text-$r-$index'),
          label: tr('文字内容'),
          value: b.text,
          focusNode: focus,
          onChanged: (v) => _edit((b) => b.copyWith(text: v)),
        ),
        const SizedBox(height: 8),
      ],
      PennaField(
        key: ValueKey('box-$r-$index'),
        label: tr('这一块的描述'),
        value: b.caption,
        maxLines: 3,
        focusNode: b.label == 'text' ? null : focus,
        onChanged: (v) => _edit((b) => b.copyWith(caption: v)),
      ),
    ],
  );
}

/// 顶上 JSON 卡片里那段 JSON 最多这么高。
const _jsonMaxHeight = 240.0;

class _JsonCard extends StatelessWidget {
  const _JsonCard({required this.board, required this.onToDraft});

  final LayoutBoard board;
  final VoidCallback onToDraft;

  /// 把剪贴板里的一份布局 JSON 换到画板上(别处写好的、带名字的都行)。
  Future<void> _paste(BuildContext context) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!context.mounted) return;
    final ok = text.trim().isNotEmpty && board.apply(text);
    showToast(context, ok ? tr('已导入') : tr('剪贴板里没有布局 JSON'), warn: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final json = board.json;
    return PennaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PennaButton(
                label: tr('复制'),
                icon: Icons.copy,
                onPressed: () => copyWithToast(context, json, tr('已复制')),
              ),
              PennaButton(
                label: tr('导入'),
                icon: Icons.content_paste,
                tooltip: tr('从剪贴板导入布局 JSON'),
                onPressed: () => _paste(context),
              ),
              PennaButton(
                label: tr('放到成稿'),
                icon: Icons.south_west,
                onPressed: onToDraft,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 一直在顶上:JSON 长了在自己的框里滚,不把下面各块挤没。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _jsonMaxHeight),
            child: SingleChildScrollView(
              // 自己出的 JSON 一定读得出功能区。
              child: LayoutJsonView(
                text: json,
                regions: layoutJsonRegions(json)!,
                names: [for (final b in board.layout.boxes) b.name],
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 11.5,
                  height: 1.45,
                  color: PennaColors.slate700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
