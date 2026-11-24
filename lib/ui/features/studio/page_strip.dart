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

typedef _Tint = SeriesTint;

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
    final pin = vm.seriesPinned(series) ? tr('取消固定') : tr('固定(不自动归档)');
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
    if (_picked.any((i) => i >= pages.length)) _picked = const {};
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

/// 全部系列的清单:上面搜索框和排序,下面一行一个系列(颜色、名字、页数、上次用的时间)。
/// 点一行(或搜到只剩一个时按回车)返回那个系列第一页的下标。每行能换颜色、固定
/// (固定的不自动归档);改了马上看得到。[others] 为真时不列眼前这个系列(给页挑个去处)。
class _SeriesFinder extends StatefulWidget {
  const _SeriesFinder({
    required this.vm,
    required this.title,
    required this.groups,
    this.others = false,
  });

  final StudioViewModel vm;
  final String title;
  final bool others;

  /// 眼下的分组(每组是一个系列的各页下标);每次重画都重新要一遍。
  final List<List<int>> Function() groups;

  @override
  State<_SeriesFinder> createState() => _SeriesFinderState();
}

class _SeriesFinderState extends State<_SeriesFinder> {
  var _query = '';

  StudioViewModel get vm => widget.vm;

  void _sortBy(String sort) =>
      vm.config.update(vm.config.config.copyWith(seriesSort: sort));

  void _setColor(String name, int index) => vm.config.update(
    vm.config.config.copyWith(
      seriesColors: {...vm.config.config.seriesColors, name: index},
    ),
  );

  /// 点颜色圆点:弹出几种颜色挑一个。
  Future<void> _pickColor(BuildContext context, Offset at, String name) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<int>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, tint) in seriesTints.indexed)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context, i),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: CircleAvatar(radius: 9, backgroundColor: tint.text),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (picked != null) _setColor(name, picked);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([vm, vm.config]),
    builder: (context, _) {
      final cfg = vm.config.config;
      final pages = vm.pages;
      final q = _query.trim().toLowerCase();
      final shown = [
        for (final (g, group) in widget.groups().indexed)
          if (!widget.others || pages[group.first].series != vm.series)
            if (q.isEmpty ||
                vm
                    .seriesName(pages[group.first].series)
                    .toLowerCase()
                    .contains(q))
              (
                order: g,
                first: group.first,
                series: pages[group.first].series,
                name: vm.seriesName(pages[group.first].series),
                count: group.length,
              ),
      ];
      // 固定的排最前,剩下的照选的排法。
      int rank(
        ({int count, int first, String name, int order, int series}) a,
      ) => vm.seriesPinned(a.series) ? 0 : 1;
      shown.sort((a, b) {
        final pinned = rank(a).compareTo(rank(b));
        if (pinned != 0) return pinned;
        return switch (cfg.seriesSort) {
          seriesSortName => a.name.compareTo(b.name),
          seriesSortPages => b.count.compareTo(a.count),
          seriesSortCreated => a.order.compareTo(b.order),
          _ => vm.seriesUsedAt(b.series).compareTo(vm.seriesUsedAt(a.series)),
        };
      });
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
        title: Row(
          children: [
            Expanded(
              child: Text(widget.title, style: const TextStyle(fontSize: 16)),
            ),
            IconButton(
              tooltip: tr('关闭'),
              iconSize: 18,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: tr('找系列的名字'),
                ),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) {
                  if (shown.length == 1) {
                    Navigator.pop(context, shown.single.first);
                  }
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (sort, label) in [
                    (seriesSortRecent, tr('最近用过')),
                    (seriesSortName, tr('按名字')),
                    (seriesSortPages, tr('页数多的')),
                    (seriesSortCreated, tr('建立先后')),
                  ])
                    PennaChip(
                      label: label,
                      selected: cfg.seriesSort == sort,
                      onTap: () => _sortBy(sort),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          tr('没有这个名字的系列'),
                          style: TextStyle(color: PennaColors.slate500),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final item = shown[i];
                          final current = item.series == vm.series;
                          final pinned = vm.seriesPinned(item.series);
                          final tint = seriesTintOf(
                            item.name,
                            cfg.seriesColors,
                          );
                          return InkWell(
                            onTap: () => Navigator.pop(context, item.first),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                children: [
                                  Tooltip(
                                    message: tr('换颜色'),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (d) => _pickColor(
                                        context,
                                        d.globalPosition,
                                        item.name,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: CircleAvatar(
                                          radius: 6,
                                          backgroundColor: tint.text,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: current
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: current ? tint.text : null,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    [
                                      tr('{0} 页', [item.count]),
                                      current
                                          ? tr('眼前这个')
                                          : shortTime(
                                              DateTime.fromMillisecondsSinceEpoch(
                                                vm.seriesUsedAt(item.series),
                                              ),
                                            ),
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: PennaColors.slate500,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: pinned
                                        ? tr('取消固定')
                                        : tr('固定(不自动归档)'),
                                    iconSize: 15,
                                    visualDensity: VisualDensity.compact,
                                    color: pinned
                                        ? tint.text
                                        : PennaColors.slate400,
                                    icon: Icon(
                                      pinned
                                          ? Icons.push_pin
                                          : Icons.push_pin_outlined,
                                    ),
                                    onPressed: () =>
                                        vm.pinSeries(item.series, on: !pinned),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
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
