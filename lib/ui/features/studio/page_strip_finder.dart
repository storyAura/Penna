part of 'page_strip.dart';

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
                style: const TextStyle(fontSize: 13),
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: tr('搜索系列'),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: PennaColors.slate400,
                  ),
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
                                          ? tr('当前')
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
                                    tooltip: pinned ? tr('取消固定') : tr('固定'),
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
