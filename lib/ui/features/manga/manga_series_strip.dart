part of 'manga_page.dart';

/// 画布上面一排:各个系列(一个系列是一部作品),眼前那个系列展开成页码,
/// 后面「+」加一页、「新系列」另起一部。右键系列名改名、删除;右键页码删这一页。
/// 一排放不下时左右滑。
class _SeriesStrip extends StatelessWidget {
  const _SeriesStrip({required this.board});

  final MangaBoard board;

  Future<void> _seriesMenu(BuildContext context, int i, Offset at) async {
    final picked = await popMenu(context, at, [tr('改名'), tr('删除整个系列')]);
    if (!context.mounted || picked == null) return;
    if (picked == tr('改名')) {
      board.showSeries(i);
      final name = await askName(context, tr('系列名'), board.project.title);
      if (name != null) board.setTitle(name.trim());
      return;
    }
    if (await confirmDelete(
      context,
      tr('删除「{0}」?', [board.seriesName(i)]),
      tr('这个系列的设定和每一页都会删掉,可以撤销。'),
    )) {
      board.removeSeries(i);
    }
  }

  Future<void> _pageMenu(BuildContext context, int i) async {
    if (board.project.pages.length <= 1) return;
    if (await confirmDelete(
      context,
      tr('删除第 {0} 页?', [i + 1]),
      tr('这一页的分格和内容都会删掉,可以撤销。'),
    )) {
      board.removePage(i);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: board,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: ScrollStrip(
        gap: 8,
        children: [
          for (var s = 0; s < board.shelf.length; s++)
            s == board.seriesIndex
                ? _current(context, s)
                : GestureDetector(
                    onSecondaryTapUp: (d) =>
                        _seriesMenu(context, s, d.globalPosition),
                    child: PennaChip(
                      label: board.seriesName(s),
                      selected: false,
                      onTap: () => board.showSeries(s),
                    ),
                  ),
          Tooltip(
            message: board.seriesFull
                ? tr('最多 {0} 个系列,先删掉不用的', [mangaMaxSeries])
                : tr('另起一部作品'),
            child: PennaButton(
              label: tr('新系列'),
              icon: Icons.add,
              borderColor: PennaColors.border,
              onPressed: board.seriesFull ? null : () => board.addSeries(),
            ),
          ),
        ],
      ),
    ),
  );

  /// 眼前的系列:名字后面跟着各页的页码和「+」。
  Widget _current(BuildContext context, int s) => Container(
    padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
    decoration: BoxDecoration(
      color: PennaColors.primaryBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: PennaColors.primaryBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onSecondaryTapUp: (d) => _seriesMenu(context, s, d.globalPosition),
          onDoubleTap: () => _seriesMenu(context, s, Offset.zero),
          child: Tooltip(
            message: tr('右键改名、删除'),
            waitDuration: const Duration(milliseconds: 600),
            child: Text(
              board.seriesName(s),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: PennaColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        for (var i = 0; i < board.project.pages.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: GestureDetector(
              onSecondaryTap: () => _pageMenu(context, i),
              child: _PageNumber(
                n: i + 1,
                selected: i == board.pageIndex,
                onTap: () => board.showPage(i),
              ),
            ),
          ),
        IconButton(
          tooltip: tr('加一页'),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          color: PennaColors.primary,
          icon: const Icon(Icons.add),
          onPressed: board.addPage,
        ),
      ],
    ),
  );
}

/// 一个页码:眼前这页实心。
class _PageNumber extends StatelessWidget {
  const _PageNumber({
    required this.n,
    required this.selected,
    required this.onTap,
  });

  final int n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr('右键删除'),
    waitDuration: const Duration(milliseconds: 600),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 26),
        height: 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? PennaColors.primary : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : PennaColors.primary,
          ),
        ),
      ),
    ),
  );
}
