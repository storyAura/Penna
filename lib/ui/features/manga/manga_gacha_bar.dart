part of 'manga_page.dart';

const _thumbWidth = 72.0, _thumbHeight = 100.0;

/// 画布下面的抽卡条:抽分格(几格到几格)、抽镜头;抽到的分格排成一排缩略图,
/// 点一张在画布上看(不改作品),「用这张」才换上去(能撤销)。
class _GachaBar extends StatelessWidget {
  const _GachaBar({required this.board});

  final MangaBoard board;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: board,
    builder: (context, _) {
      final draw = board.draw;
      return Container(
        decoration: BoxDecoration(
          color: PennaColors.slate50,
          border: Border(top: BorderSide(color: PennaColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                PennaButton(
                  label: tr('抽分格'),
                  icon: Icons.casino_outlined,
                  tooltip: tr('按格数随机切几种分格,挑一张用'),
                  background: PennaColors.primary,
                  foreground: Colors.white,
                  onPressed: board.drawLayout,
                ),
                const SizedBox(width: 10),
                Text(
                  tr('格数'),
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
                _Stepper(
                  value: board.minPanels,
                  onChanged: (v) {
                    board.minPanels = v.clamp(1, board.maxPanels);
                    board.closeDraw();
                  },
                ),
                Text('–', style: TextStyle(color: PennaColors.slate500)),
                _Stepper(
                  value: board.maxPanels,
                  onChanged: (v) {
                    board.maxPanels = v.clamp(board.minPanels, mangaMaxPanels);
                    board.closeDraw();
                  },
                ),
                const SizedBox(width: 10),
                PennaButton(
                  label: tr('抽镜头'),
                  icon: Icons.videocam_outlined,
                  tooltip: tr('给没锁的格随机定景别和角度'),
                  borderColor: PennaColors.border,
                  onPressed: board.drawShot,
                ),
                const Spacer(),
                SelectableText(
                  tr('种子 {0}', [board.seed]),
                  contextMenuBuilder: pennaTextMenu,
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
              ],
            ),
            if (draw != null) ...[
              const SizedBox(height: 8),
              if (draw.problem != null)
                Text(
                  draw.problem!,
                  style: TextStyle(
                    fontSize: 12,
                    color: PennaColors.diffDelText,
                  ),
                )
              else
                _Candidates(board: board, draw: draw),
            ],
          ],
        ),
      );
    },
  );
}

class _Candidates extends StatelessWidget {
  const _Candidates({required this.board, required this.draw});

  final MangaBoard board;
  final MangaDraw draw;

  @override
  Widget build(BuildContext context) {
    final at = board.previewing;
    final picked = at == null ? null : draw.found[at];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SizedBox(
            height: _thumbHeight + 18,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: draw.found.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _Thumb(
                page: board.page,
                root: draw.found[i].root,
                count: draw.found[i].count,
                selected: i == at,
                onTap: () => board.preview(i),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (draw.found.length < draw.wanted)
                Text(
                  tr('要 {0} 张,抽到 {1} 张', [draw.wanted, draw.found.length]),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                ),
              if (picked != null && picked.notes.isNotEmpty)
                Text(
                  picked.notes.join(tr('、')),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                ),
              const SizedBox(height: 6),
              PennaButton(
                label: tr('用这张'),
                icon: Icons.check,
                background: PennaColors.primary,
                foreground: Colors.white,
                onPressed: picked == null ? null : board.applyPreview,
              ),
              const SizedBox(height: 6),
              PennaButton(
                label: tr('不用了'),
                icon: Icons.close,
                borderColor: PennaColors.border,
                onPressed: board.closeDraw,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一张候选的缩略图:只画格框,下面写几格。
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.page,
    required this.root,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final MangaPage page;
  final MangaNode root;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: _thumbWidth,
            height: _thumbHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? PennaColors.primary : PennaColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: CustomPaint(
              painter: MangaPainter(
                page: page.copyWith(
                  root: root,
                  panels: {
                    for (final id in leafIds(root)) id: MangaPanel(id: id),
                  },
                ),
                overlays: false,
                text: false,
                pad: 4,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tr('{0} 格', [count]),
            style: TextStyle(
              fontSize: 11,
              color: selected ? PennaColors.primary : PennaColors.slate500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// − 数字 + 的小步进器。
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        iconSize: 14,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        onPressed: () => onChanged(value - 1),
      ),
      Text('$value', style: const TextStyle(fontSize: 12.5)),
      IconButton(
        iconSize: 14,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        onPressed: () => onChanged(value + 1),
      ),
    ],
  );
}
