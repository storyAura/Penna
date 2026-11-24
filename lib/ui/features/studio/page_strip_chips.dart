part of 'page_strip.dart';

/// 把同一个系列的页框在一起的彩色框。
class _SeriesFrame extends StatelessWidget {
  const _SeriesFrame({
    required this.tint,
    required this.current,
    required this.children,
  });

  final _Tint tint;
  final bool current;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.base,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tint.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: current ? tint.text : tint.border),
      ),
      // 页多了在框里折行,不把框撑出页签条。
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

/// 框里最前面的系列切换器:左右箭头一个个翻(在它上面滚滚轮也行),中间是系列的名字和
/// 「第几个/共几个」,点一下打开全部系列的清单;双击改名,右键改名、固定、归档、删除。
/// 只有一个系列时没有箭头和数字。
class _SeriesSwitch extends StatelessWidget {
  const _SeriesSwitch({
    required this.name,
    required this.pinned,
    required this.tint,
    required this.index,
    required this.total,
    required this.onStep,
    required this.onOpen,
    required this.onMenu,
    required this.onRename,
  });

  final String name;

  /// 固定的系列(不自动归档),名字前面画个图钉。
  final bool pinned;
  final _Tint tint;

  /// 这是第几个系列(从 0 数)、一共几个。
  final int index;
  final int total;

  /// 往前(-1)或往后(+1)翻一个系列,到头了绕回去。
  final ValueChanged<int> onStep;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  final VoidCallback onRename;

  Widget _arrow(IconData icon, String tip, int by) => Tooltip(
    message: tip,
    waitDuration: _tipWait,
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => onStep(by),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
        child: Icon(icon, size: 16, color: tint.text),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final many = total > 1;
    return Listener(
      onPointerSignal: (signal) {
        if (!many || signal is! PointerScrollEvent) return;
        if (signal.scrollDelta.dy != 0) {
          onStep(signal.scrollDelta.dy > 0 ? 1 : -1);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 两个箭头都放在最前面:位置固定,名字长短不同也不会把它们挤来挤去。
          if (many) _arrow(Icons.chevron_left, tr('上一个系列'), total - 1),
          if (many) _arrow(Icons.chevron_right, tr('下一个系列'), 1),
          Tooltip(
            message: many ? '${tr('点一下看全部系列')} · $_gestureTip' : _gestureTip,
            waitDuration: _tipWait,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: many ? onOpen : null,
              onDoubleTap: onRename,
              onSecondaryTapDown: (d) => onMenu(d.globalPosition),
              child: MouseRegion(
                cursor: many
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pinned) ...[
                        Icon(Icons.push_pin, size: 11, color: tint.text),
                        const SizedBox(width: 3),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tint.text,
                          ),
                        ),
                      ),
                      if (many) ...[
                        Icon(Icons.arrow_drop_down, size: 16, color: tint.text),
                        Text(
                          '${index + 1}/$total',
                          style: TextStyle(
                            fontSize: 11,
                            color: tint.text.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

/// 一页的页签:点一下换页,双击改名,右键更多操作,按住拖到另一页上(别的系列也行)。
/// [waiting] 表示这页有待确认的改动,右上角亮一个小点;[picked] 是多选中的。
class _PageChip extends StatelessWidget {
  const _PageChip({
    required this.index,
    required this.number,
    required this.name,
    required this.tint,
    required this.selected,
    required this.picked,
    required this.dragCount,
    required this.waiting,
    required this.accepts,
    required this.onTap,
    required this.onMenu,
    required this.onRename,
    required this.onDrop,
  });

  /// 这页在全部页里排第几,拖动时带着它。
  final int index;

  /// 这页是它那个系列里的第几页。
  final int number;
  final String name;
  final _Tint tint;
  final bool selected;
  final bool picked;

  /// 拖它时一起走几页(多选时是选中的页数)。
  final int dragCount;
  final bool waiting;
  final bool Function(int from) accepts;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;
  final VoidCallback onRename;
  final ValueChanged<int> onDrop;

  /// 胶囊页签:小一号的灰页码(01、02)+ 名字;选中的白底描边(2026-11-23 用户从三张样稿里挑的)。
  Widget _face({required bool hovered}) {
    return AnimatedContainer(
      duration: Motion.base,
      height: 22,
      constraints: const BoxConstraints(minWidth: 26, maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: selected
            ? PennaColors.card
            : PennaColors.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: picked
              ? PennaColors.primary
              : hovered || selected
              ? tint.text
              : Colors.transparent,
          width: hovered || picked ? 2 : 1,
        ),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x1F0F172A),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      // 宽度跟着字走(不写 widthFactor 会把页签撑到最宽)。
      child: Center(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$number'.padLeft(2, '0'),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected ? tint.text : PennaColors.slate400,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? tint.text : PennaColors.slate700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, incoming, _) => LongPressDraggable<int>(
        data: index,
        delay: const Duration(milliseconds: 250),
        feedback: Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: BorderRadius.circular(5),
          child: Badge(
            isLabelVisible: dragCount > 1,
            label: Text('$dragCount'),
            child: _face(hovered: false),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: _face(hovered: false)),
        child: Tooltip(
          message: [
            tr('第 {0} 页', [number]),
            if (name.isNotEmpty) name,
            if (waiting) tr('有待确认的改动'),
            _gestureTip,
          ].join(' · '),
          waitDuration: _tipWait,
          child: _QuickTap(
            onTap: onTap,
            onDoubleTap: onRename,
            onMenu: onMenu,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _face(hovered: incoming.isNotEmpty),
                  if (waiting)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: CircleAvatar(
                        radius: 3.5,
                        backgroundColor: PennaColors.amber,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「成稿正文」旁边的问号:这一块藏着的操作。
String get _bodyTips => tr(
  '页签、系列名:双击改名 · 右键更多 · 按住拖动换顺序、拖到别的系列\n'
  '页签:按住 Ctrl 点几个多选、按住 Shift 点首尾连选,右键批量操作\n'
  '分段:右键标注改名 · 拖左上角把手换位置\n'
  '选中文字后右键:固定、润色、翻译、建立分段',
);

/// 页签和系列名上能做什么;悬停一会儿就显示。
String get _gestureTip => tr('双击改名 · 右键更多');
const _tipWait = Duration(milliseconds: 350);

/// 单击马上生效,紧接着再点一下算双击。
/// GestureDetector 的 onDoubleTap 会让单击等一会儿才生效,换页会觉得卡。
class _QuickTap extends StatefulWidget {
  const _QuickTap({
    required this.onTap,
    required this.onDoubleTap,
    required this.onMenu,
    required this.child,
  });

  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<Offset> onMenu;
  final Widget child;

  @override
  State<_QuickTap> createState() => _QuickTapState();
}

class _QuickTapState extends State<_QuickTap> {
  var _last = DateTime(0);

  void _tap() {
    final now = DateTime.now();
    final second = now.difference(_last) < kDoubleTapTimeout;
    _last = second ? DateTime(0) : now;
    second ? widget.onDoubleTap() : widget.onTap();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _tap,
    onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
    child: widget.child,
  );
}

/// 页签条上的小图标按钮;[onTap] 为 null 时是灰的。
class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.tip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            icon,
            size: 15,
            color: onTap == null ? PennaColors.slate400 : color,
          ),
        ),
      ),
    );
  }
}
