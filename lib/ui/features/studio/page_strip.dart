import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../../../data/models/app_config.dart';
import '../../core/series_tint.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import 'series_manager.dart';

part 'page_strip_finder.dart';
part 'page_strip_chips.dart';

typedef _Tint = SeriesTint;

/// 成稿正文上方的页签:每个系列一个彩色框,框里先是系列的名字,再是它的各页
/// (页码每个系列都从 1 数)。双击改名,右键更多操作,按住页签拖着调顺序、拖到别的系列;
/// 按住 Ctrl 点页签多选、按住 Shift 点首尾连选,右键批量改名、出图、建立系列、删除。
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
  // 记在 vm 上:下半区的「出选中的图」也要看(2026-11-25)。
  Set<int> get _picked => vm.pickedPages.value;
  set _picked(Set<int> v) => vm.pickedPages.value = v;

  @override
  void initState() {
    super.initState();
    vm.pickedPages.addListener(_onPicked);
  }

  @override
  void dispose() {
    vm.pickedPages.removeListener(_onPicked);
    super.dispose();
  }

  /// 别处(「出选中的图」)清掉了选择,页签跟着变。
  void _onPicked() {
    if (mounted) setState(() {});
  }

  /// Shift 连选的起点:上一次 Ctrl 点的那页;没有就是眼前这页。
  int? _anchor;

  void _do(BuildContext context, String? problem) {
    if (_picked.isNotEmpty || _anchor != null) {
      setState(() {
        _picked = const {};
        _anchor = null;
      });
    }
    if (problem != null) showToast(context, problem, warn: true);
  }

  void _tap(int i) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      // 2026-11-23 用户要求:按住 Shift 点首尾,中间的页一起选上(同资源管理器)。
      final from = _anchor ?? vm.pageIndex;
      final (lo, hi) = from < i ? (from, i) : (i, from);
      setState(
        () => _picked = Set.unmodifiable({for (var k = lo; k <= hi; k++) k}),
      );
      return;
    }
    if (keys.isControlPressed) {
      // 第一次多选时把眼前这页也算上。
      final base = _picked.isEmpty ? {vm.pageIndex} : _picked;
      setState(() {
        _anchor = i;
        _picked = Set.unmodifiable(
          base.contains(i) ? ({...base}..remove(i)) : {...base, i},
        );
      });
      return;
    }
    _do(context, vm.openPage(i));
  }

  /// 按页的先后排进出图队列。
  void _generate(BuildContext context, Iterable<int> which) {
    final count = vm.generatePages(which);
    _do(context, null);
    if (count == 0) {
      return showToast(context, tr('这些页还是空的'), warn: true);
    }
    showToast(context, tr('已排进出图队列 {0} 张', [count]));
  }

  /// 多选时右键:对选中的几页一起做。
  Future<void> _batchMenu(BuildContext context, Offset at) async {
    final which = _picked;
    final generate = tr('出图({0} 张)', [which.length]);
    final picked = await popMenu(context, at, [
      tr('批量改名'),
      if (widget.generate) generate,
      tr('建立系列'),
      if (vm.seriesCount > 1) tr('移到别的系列…'),
      tr('删除选中的页'),
      tr('取消选择'),
    ]);
    if (!context.mounted || picked == null) return;
    if (picked == tr('移到别的系列…')) return _moveTo(context, which);
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
      if (vm.seriesCount > 1) tr('移到别的系列…'),
      tr('删除这一页'),
      tr('删除整个系列'),
    ]);
    if (!context.mounted || picked == null) return;
    if (picked == tr('出图')) return _generate(context, [i]);
    if (picked == tr('移到别的系列…')) return _moveTo(context, [i]);
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
    final pin = vm.seriesPinned(series) ? tr('取消固定') : tr('固定');
    final picked = await popMenu(context, at, [
      tr('改名'),
      if (onArchive != null) pin,
      if (onArchive != null) tr('归档'),
      tr('删除整个系列'),
      tr('批量管理…'),
    ]);
    if (!context.mounted || picked == null) return;
    if (picked == pin) {
      return vm.pinSeries(series, on: !vm.seriesPinned(series));
    }
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

  /// 这个系列的颜色:用户挑过就用挑的,没挑过按名字算一个固定的。
  _Tint _tintOf(int series) =>
      seriesTintOf(vm.seriesName(series), vm.config.config.seriesColors);

  /// 同系列的页挨在一起,顺着数就能分出组来。
  List<List<int>> get _groups {
    final pages = vm.pages;
    final groups = <List<int>>[];
    for (final (i, p) in pages.indexed) {
      if (i > 0 && pages[i - 1].series == p.series) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }
    return groups;
  }

  /// 全部系列的清单,能打字找;返回挑中的那一组页。[title] 是窗口上写的字,
  /// [others] 为真时不列眼前这个系列(给页挑个去处)。
  Future<List<int>?> _pickSeries(
    BuildContext context,
    List<List<int>> groups, {
    required String title,
    bool others = false,
  }) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _SeriesFinder(
        vm: vm,
        title: title,
        others: others,
        groups: () => _groups,
      ),
    );
    return picked == null
        ? null
        : groups.firstWhere((group) => group.first == picked);
  }

  /// 点系列的名字:打开全部系列的清单,点一个换过去。
  Future<void> _findSeries(BuildContext context, List<List<int>> groups) async {
    final group = await _pickSeries(
      context,
      groups,
      title: tr('全部系列 {0}', [groups.length]),
    );
    if (group != null && context.mounted) {
      _do(context, vm.openPage(group.first));
    }
  }

  /// 把几页移到别的系列:挑一个系列,排到它的最后。
  Future<void> _moveTo(BuildContext context, Iterable<int> which) async {
    final group = await _pickSeries(
      context,
      _groups,
      title: tr('移到哪个系列'),
      others: true,
    );
    if (group != null && context.mounted) {
      _do(context, vm.movePages(which, group.last));
    }
  }

  /// 上次看有没有该归档的系列时,眼前是哪个系列。
  int? _checkedFor;

  /// 很久没用的系列收进档案库(设置里定多久,固定的不收)。进来时、换了系列时看一眼。
  void _autoArchive() {
    final archive = onArchive;
    final days = vm.config.config.autoArchiveDays;
    if (archive == null || days <= 0 || _checkedFor == vm.series) return;
    _checkedFor = vm.series;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || vm.isStreaming) return;
      final stale = vm.staleSeries(Duration(days: days));
      if (stale.isNotEmpty) archive(stale);
    });
  }

  @override
  Widget build(BuildContext context) {
    _autoArchive();
    final pages = vm.pages;
    // 选中的页被删掉了:等这一帧画完再清(画的时候通知别人会报错)。
    if (_picked.any((i) => i >= pages.length)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _picked = const {};
      });
    }
    if ((_anchor ?? 0) >= pages.length) _anchor = null;
    final groups = _groups;
    Widget frameOf(int g, List<int> group) => _SeriesFrame(
      tint: _tintOf(pages[group.first].series),
      current: true,
      children: [
        _SeriesSwitch(
          name: vm.seriesName(pages[group.first].series),
          pinned: vm.seriesPinned(pages[group.first].series),
          tint: _tintOf(pages[group.first].series),
          index: g,
          total: groups.length,
          onStep: (by) =>
              _do(context, vm.openPage(groups[(g + by) % groups.length].first)),
          onOpen: () => _findSeries(context, groups),
          onRename: () => _renameSeries(context, pages[group.first].series),
          onMenu: (at) => _seriesMenu(context, at, pages[group.first].series),
        ),
        for (final i in group)
          _PageChip(
            index: i,
            number: vm.pageNumber(i),
            name: pages[i].name,
            tint: _tintOf(pages[group.first].series),
            selected: i == vm.pageIndex,
            picked: _picked.contains(i),
            // 拖着的是选中的一页时,选中的几页一起走。
            dragCount: _picked.contains(i) ? _picked.length : 1,
            waiting: pages[i].pending != null,
            accepts: (from) =>
                from != i && !(_picked.contains(from) && _picked.contains(i)),
            onTap: () => _tap(i),
            onMenu: (at) => _pageMenu(context, at, i),
            onRename: () => _renamePage(context, i),
            onDrop: (from) => _do(
              context,
              vm.movePages(_picked.contains(from) ? _picked : [from], i),
            ),
          ),
        _IconChip(
          icon: Icons.add,
          tip: tr('在这个系列里加一页'),
          color: _tintOf(pages[group.first].series).text,
          onTap: () =>
              _do(context, vm.addPage(toSeries: pages[group.first].series)),
        ),
      ],
    );
    final newSeries = Tooltip(
      message: tr('另起一个系列,对话和别的系列分开'),
      child: PennaButton(
        label: tr('新系列'),
        icon: Icons.add,
        borderColor: PennaColors.border,
        onPressed: () => _do(context, vm.addPage(newSeries: true)),
      ),
    );
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
          // 眼前这个系列展开成一个框(各页都在里面);别的系列收成小标签(名字和页数),
          // 点一下换过去,页也能拖到标签上归进那个系列。系列再多也只是多几个标签。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 只画眼前这个系列:最前面是系列切换器(名字、第几个、左右箭头),后面是它的各页。
              // 换系列:点箭头或在切换器上滚滚轮一个个翻,点名字打开全部系列的清单(能打字找)。
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (g, group) in groups.indexed)
                    if (pages[group.first].series == vm.series)
                      frameOf(g, group),
                  newSeries,
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
