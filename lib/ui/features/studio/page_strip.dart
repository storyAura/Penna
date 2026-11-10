import 'dart:async';

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import 'series_manager.dart';

typedef _Tint = ({Color bg, Color border, Color text});

/// 系列外框的配色,按系列出现的先后轮着用。
List<_Tint> get _seriesTints =>
    PennaColors.isDark ? _darkSeriesTints : _lightSeriesTints;

const _lightSeriesTints = <_Tint>[
  (bg: Color(0xFFEEF2FF), border: Color(0xFFC7D2FE), text: Color(0xFF4338CA)),
  (bg: Color(0xFFF0FDFA), border: Color(0xFF99F6E4), text: Color(0xFF0F766E)),
  (bg: Color(0xFFFFF1F2), border: Color(0xFFFECDD3), text: Color(0xFFBE123C)),
  (bg: Color(0xFFF0F9FF), border: Color(0xFFBAE6FD), text: Color(0xFF0369A1)),
  (bg: Color(0xFFFAF5FF), border: Color(0xFFE9D5FF), text: Color(0xFF7E22CE)),
];

const _darkSeriesTints = <_Tint>[
  (bg: Color(0xFF1B1D3A), border: Color(0xFF363A78), text: Color(0xFFA5B4FC)),
  (bg: Color(0xFF0F2826), border: Color(0xFF1F5A54), text: Color(0xFF5EEAD4)),
  (bg: Color(0xFF2C171C), border: Color(0xFF64303A), text: Color(0xFFFDA4AF)),
  (bg: Color(0xFF10233A), border: Color(0xFF1F4A70), text: Color(0xFF7DD3FC)),
  (bg: Color(0xFF261835), border: Color(0xFF4F3370), text: Color(0xFFD8B4FE)),
];

/// 成稿正文上方的页签:每个系列一个彩色框,框里先是系列的名字,再是它的各页
/// (页码每个系列都从 1 数)。双击改名,右键更多操作,按住页签拖着调顺序、拖到别的系列;
/// 按住 Shift(或 Ctrl)点页签多选,右键批量改名、出图、建立系列、删除。
class PageStrip extends StatefulWidget {
  const PageStrip({
    super.key,
    required this.vm,
    this.label,
    this.tips = true,
    this.onArchive,
    this.generate = false,
  });

  final StudioViewModel vm;

  /// 右键菜单里有没有「出图」(工作台有;区域控制的页是布局,不在这出)。
  final bool generate;

  /// 归档几个系列(存进档案库再从工作区删掉);为 null 时菜单里没有「归档」(区域控制)。
  final void Function(Set<int> series)? onArchive;

  /// 页签前面的小标题;不给是「成稿正文」。
  final String? label;

  /// 小标题后面带不带问号(悬停列出成稿里藏着的操作)。
  final bool tips;

  @override
  State<PageStrip> createState() => _PageStripState();
}

class _PageStripState extends State<PageStrip> {
  StudioViewModel get vm => widget.vm;
  void Function(Set<int> series)? get onArchive => widget.onArchive;
  String? get label => widget.label;
  bool get tips => widget.tips;

  /// 多选中的页(`pages` 的下标)。做完一次批量操作、单击换页就清掉。
  // ponytail: 按下标记,选着的时候 Agent 加了页,选中的会错位;做完一件事就清掉,够用。
  Set<int> _picked = const {};

  void _do(BuildContext context, String? problem) {
    if (_picked.isNotEmpty) setState(() => _picked = const {});
    if (problem != null) showToast(context, problem, warn: true);
  }

  void _tap(int i) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed || keys.isControlPressed) {
      // 第一次多选时把眼前这页也算上。
      final base = _picked.isEmpty ? {vm.pageIndex} : _picked;
      setState(
        () => _picked = Set.unmodifiable(
          base.contains(i) ? ({...base}..remove(i)) : {...base, i},
        ),
      );
      return;
    }
    _do(context, vm.openPage(i));
  }

  /// 按页的先后排进出图队列。
  void _generate(BuildContext context, Iterable<int> which) {
    final prompts = [
      for (final i in which.toList()..sort()) vm.finalPromptOf(i),
    ].where((p) => p.trim().isNotEmpty).toList();
    _do(context, null);
    if (prompts.isEmpty) {
      return showToast(context, tr('这些页还是空的'), warn: true);
    }
    for (final p in prompts) {
      unawaited(vm.comfy.generate(p));
    }
    showToast(context, tr('已排进出图队列 {0} 张', [prompts.length]));
  }

  /// 多选时右键:对选中的几页一起做。
  Future<void> _batchMenu(BuildContext context, Offset at) async {
    final which = _picked;
    final generate = tr('出图({0} 张)', [which.length]);
    final picked = await popMenu(context, at, [
      tr('批量改名'),
      if (widget.generate) generate,
      tr('建立系列'),
      tr('删除选中的页'),
      tr('取消选择'),
    ]);
    if (!context.mounted || picked == null) return;
    if (picked == tr('批量改名')) {
      final name = await askName(context, tr('这几页的名字'), '');
      if (name != null) vm.renamePages(which, name);
      if (context.mounted) _do(context, null);
      return;
    }
    if (picked == tr('建立系列')) return _do(context, vm.groupPages(which));
    if (picked == tr('删除选中的页')) {
      if (!await confirmDelete(
        context,
        tr('删除选中的 {0} 页?', [which.length]),
        tr('这几页的成稿会一起删掉。'),
      )) {
        return;
      }
      if (context.mounted) _do(context, vm.removePages(which));
      return;
    }
    if (picked == generate) return _generate(context, which);
    _do(context, null);
  }

  Future<void> _pageMenu(BuildContext context, Offset at, int i) async {
    if (_picked.length > 1 && _picked.contains(i)) {
      return _batchMenu(context, at);
    }
    final picked = await popMenu(context, at, [
      tr('改名'),
      if (widget.generate) tr('出图'),
      tr('脱离系列'),
      tr('建立系列'),
      tr('删除这一页'),
      tr('删除整个系列'),
    ]);
    if (!context.mounted || picked == null) return;
    if (picked == tr('出图')) return _generate(context, [i]);
    final page = vm.pages[i];
    if (picked == tr('脱离系列')) return _do(context, vm.detachPage(i));
    if (picked == tr('建立系列')) return _do(context, vm.addPage(newSeries: true));
    if (picked == tr('删除整个系列')) return _removeSeries(context, page.series);
    if (picked == tr('改名')) return _renamePage(context, i);
    final empty =
        page.pending == null && page.blocks.every((b) => b.text.trim().isEmpty);
    if (!empty &&
        !await confirmDelete(
          context,
          tr('删除第 {0} 页?', [vm.pageNumber(i)]),
          tr('这一页的成稿会一起删掉。'),
        )) {
      return;
    }
    if (context.mounted) _do(context, vm.removePage(i));
  }

  Future<void> _seriesMenu(BuildContext context, Offset at, int series) async {
    final picked = await popMenu(context, at, [
      tr('改名'),
      if (onArchive != null) tr('归档'),
      tr('删除整个系列'),
      tr('批量管理…'),
    ]);
    if (!context.mounted || picked == null) return;
    if (picked == tr('改名')) return _renameSeries(context, series);
    if (picked == tr('归档')) return onArchive!({series});
    if (picked == tr('批量管理…')) {
      return showSeriesManager(context, vm, onArchive: onArchive);
    }
    await _removeSeries(context, series);
  }

  Future<void> _renamePage(BuildContext context, int i) async {
    final name = await askName(
      context,
      tr('第 {0} 页的名字', [vm.pageNumber(i)]),
      vm.pages[i].name,
    );
    if (name != null) vm.renamePage(i, name);
  }

  Future<void> _renameSeries(BuildContext context, int series) async {
    final next = await askName(context, tr('系列的名字'), vm.seriesName(series));
    if (next != null) vm.renameSeries(series, next);
  }

  /// 删掉整个系列,先问一句。
  Future<void> _removeSeries(BuildContext context, int series) async {
    final name = vm.seriesName(series);
    if (!await confirmDelete(
      context,
      tr('删除「{0}」?', [name]),
      tr('这个系列的每一页都会删掉,对话收进历史。'),
    )) {
      return;
    }
    if (context.mounted) _do(context, vm.removeSeries(series));
  }

  @override
  Widget build(BuildContext context) {
    final pages = vm.pages;
    if (_picked.any((i) => i >= pages.length)) _picked = const {};
    // 系列满了不能再另起;往已有的系列里加页不限。
    final full = vm.seriesFull;
    // 同系列的页挨在一起,所以顺着数就能分出组来。
    final groups = <List<int>>[];
    for (final (i, p) in pages.indexed) {
      if (i > 0 && pages[i - 1].series == p.series) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 7, right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label ?? tr('成稿正文'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: PennaColors.slate500,
                ),
              ),
              if (tips) ...[
                SizedBox(width: 3),
                Tooltip(
                  message: _bodyTips,
                  waitDuration: Duration.zero,
                  child: Icon(
                    Icons.help_outline,
                    size: 13,
                    color: PennaColors.slate400,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          // 一层最多放 perLayer 个系列,多的用左右箭头翻;一层里放不下时自己折行。
          // 系列满了而 Agent 还要另起时,下面亮出提醒叫用户清理。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SeriesPager(
                current: groups.indexWhere(
                  (g) => pages[g.first].series == vm.series,
                ),
                currentSeries: vm.series,
                trailing: Tooltip(
                  message: tr('另起一个系列,对话和别的系列分开'),
                  child: PennaButton(
                    label: tr('新系列'),
                    icon: Icons.add,
                    borderColor: PennaColors.border,
                    onPressed: full
                        ? null
                        : () => _do(context, vm.addPage(newSeries: true)),
                  ),
                ),
                children: [
                  for (final (g, group) in groups.indexed)
                    _SeriesFrame(
                      tint: _seriesTints[g % _seriesTints.length],
                      // 眼前这个系列的框描深一点。
                      current: pages[group.first].series == vm.series,
                      children: [
                        _SeriesLabel(
                          name: vm.seriesName(pages[group.first].series),
                          tint: _seriesTints[g % _seriesTints.length],
                          onMenu: (at) => _seriesMenu(
                            context,
                            at,
                            pages[group.first].series,
                          ),
                          onRename: () =>
                              _renameSeries(context, pages[group.first].series),
                        ),
                        for (final i in group)
                          _PageChip(
                            index: i,
                            number: vm.pageNumber(i),
                            name: pages[i].name,
                            tint: _seriesTints[g % _seriesTints.length],
                            selected: i == vm.pageIndex,
                            picked: _picked.contains(i),
                            // 拖着的是选中的一页时,选中的几页一起走。
                            dragCount: _picked.contains(i) ? _picked.length : 1,
                            waiting: pages[i].pending != null,
                            // 别的系列的页也收:挪过来归进这个系列。
                            accepts: (from) =>
                                from != i &&
                                !(_picked.contains(from) &&
                                    _picked.contains(i)),
                            onTap: () => _tap(i),
                            onMenu: (at) => _pageMenu(context, at, i),
                            onRename: () => _renamePage(context, i),
                            onDrop: (from) => _do(
                              context,
                              vm.movePages(
                                _picked.contains(from) ? _picked : [from],
                                i,
                              ),
                            ),
                          ),
                        _IconChip(
                          icon: Icons.add,
                          tip: tr('在这个系列里加一页'),
                          color: _seriesTints[g % _seriesTints.length].text,
                          onTap: () => _do(
                            context,
                            vm.addPage(toSeries: pages[group.first].series),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (vm.seriesAlert case final alert?)
                _SeriesAlert(text: alert, onClose: vm.dismissSeriesAlert),
            ],
          ),
        ),
      ],
    );
  }
}

/// 页签上一层放几个系列。
const _perLayer = StudioPages.perLayer;

/// 系列满了、Agent 放不下时的提醒:叫用户删掉一些系列。删到不满就自己消失。
class _SeriesAlert extends StatelessWidget {
  const _SeriesAlert({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: PennaColors.diffDel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: PennaColors.diffDelText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: PennaColors.diffDelText),
            ),
          ),
          IconButton(
            tooltip: tr('关闭'),
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: PennaColors.diffDelText),
            onPressed: onClose,
          ),
        ],
      ),
    ),
  );
}

/// 系列多了分层:一层 [_perLayer] 个,左右箭头翻层。默认停在眼前这个系列那一层;
/// 用户翻到别的层后,换了系列(新建、切过去)又跟回眼前这一层。
class _SeriesPager extends StatefulWidget {
  const _SeriesPager({
    required this.children,
    required this.current,
    required this.currentSeries,
    required this.trailing,
  });

  /// 每个系列一个框,按先后排。
  final List<Widget> children;

  /// 眼前这个系列是 [children] 里的第几个。
  final int current;
  final int currentSeries;

  /// 跟在每一层最后的「新系列」按钮。
  final Widget trailing;

  @override
  State<_SeriesPager> createState() => _SeriesPagerState();
}

class _SeriesPagerState extends State<_SeriesPager> {
  /// 用户翻到的层,和翻的时候眼前是哪个系列。
  int? _picked, _pickedFor;

  @override
  Widget build(BuildContext context) {
    final layers = (widget.children.length / _perLayer).ceil().clamp(
      1,
      1 << 20,
    );
    final home = widget.current < 0 ? 0 : widget.current ~/ _perLayer;
    final layer =
        ((_pickedFor == widget.currentSeries ? _picked : null) ?? home).clamp(
          0,
          layers - 1,
        );
    void go(int to) => setState(() {
      _picked = to;
      _pickedFor = widget.currentSeries;
    });
    Widget arrow(IconData icon, String tip, int? to) => IconButton(
      tooltip: tip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
      onPressed: to == null ? null : () => go(to),
    );
    final row = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...widget.children.skip(layer * _perLayer).take(_perLayer),
        widget.trailing,
      ],
    );
    if (layers == 1) return row;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        arrow(Icons.chevron_left, tr('上一层'), layer > 0 ? layer - 1 : null),
        Expanded(child: row),
        arrow(
          Icons.chevron_right,
          tr('下一层'),
          layer < layers - 1 ? layer + 1 : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 9, left: 2),
          child: Text(
            '${layer + 1}/$layers',
            style: TextStyle(fontSize: 11, color: PennaColors.slate500),
          ),
        ),
      ],
    );
  }
}

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

/// 框里最前面的系列名;双击改名,右键改名或删掉整个系列。
class _SeriesLabel extends StatelessWidget {
  const _SeriesLabel({
    required this.name,
    required this.tint,
    required this.onMenu,
    required this.onRename,
  });

  final String name;
  final _Tint tint;
  final ValueChanged<Offset> onMenu;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _gestureTip,
      waitDuration: _tipWait,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onRename,
        onSecondaryTapDown: (d) => onMenu(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: tint.text,
              ),
            ),
          ),
        ),
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

  Widget _face({required bool hovered}) {
    final label = name.isEmpty ? '$number' : '$number $name';
    return AnimatedContainer(
      duration: Motion.base,
      height: 22,
      constraints: const BoxConstraints(minWidth: 26, maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: selected ? tint.text : PennaColors.card,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: picked
              ? PennaColors.primary
              : hovered || selected
              ? tint.text
              : tint.border,
          width: hovered || picked ? 2 : 1,
        ),
      ),
      // 宽度跟着字走(不写 widthFactor 会把页签撑到最宽)。
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            // 选中的页签底色是 tint.text:浅色配色下它深,深色配色下它浅。
            color: selected
                ? (PennaColors.isDark ? PennaColors.bg : Colors.white)
                : tint.text,
          ),
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
  '页签:按住 Shift 点几个多选,右键批量操作\n'
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
