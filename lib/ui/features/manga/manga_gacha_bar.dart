part of 'manga_page.dart';

const _thumbWidth = 84.0, _thumbHeight = 118.0;

/// 画布下面的抽卡条:选版式(对话、标准、动作、扉页)或自己调参数,抽分格、抽镜头;
/// 抽到的分格排成一排缩略图(能左右滑),点一张在画布上看(不改作品),
/// 「用这张」才换上去(能撤销)。
class _GachaBar extends StatefulWidget {
  const _GachaBar({required this.board});

  final MangaBoard board;

  @override
  State<_GachaBar> createState() => _GachaBarState();
}

class _GachaBarState extends State<_GachaBar> {
  bool _tuning = false;

  MangaBoard get board => widget.board;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: board,
    builder: (context, _) {
      final draw = board.draw;
      final small = TextStyle(fontSize: 12, color: PennaColors.slate500);
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
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PennaButton(
                  label: tr('抽分格'),
                  icon: Icons.casino_outlined,
                  tooltip: tr('按版式随机切几种分格,挑一张用'),
                  background: PennaColors.primary,
                  foreground: Colors.white,
                  onPressed: board.drawLayout,
                ),
                for (final name in mangaStyles.keys)
                  PennaChip(
                    label: tr(name),
                    selected: board.styleName == name,
                    onTap: () => board.useStyle(name),
                  ),
                PennaChip(
                  label: tr('调参数'),
                  selected: _tuning,
                  onTap: () => setState(() => _tuning = !_tuning),
                ),
                const SizedBox(width: 4),
                PennaButton(
                  label: tr('抽镜头'),
                  icon: Icons.videocam_outlined,
                  tooltip: tr('给没锁的格随机定景别和角度'),
                  borderColor: PennaColors.border,
                  onPressed: board.drawShot,
                ),
                Text(tr('种子 {0}', [board.seed]), style: small),
              ],
            ),
            if (_tuning) ...[const SizedBox(height: 6), _Tuning(board: board)],
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

/// 版式参数:层数、横线和竖线的斜度、出血、格里再分、大格,格框粗细,
/// 指定格数和一次抽几张。
class _Tuning extends StatelessWidget {
  const _Tuning({required this.board});

  final MangaBoard board;

  @override
  Widget build(BuildContext context) {
    final st = board.style;
    final small = TextStyle(fontSize: 12, color: PennaColors.slate500);
    Widget slider(String label, int value, ValueChanged<int> set) => SizedBox(
      width: 190,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: small)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.toDouble(),
                max: 100,
                divisions: 20,
                activeColor: PennaColors.primary,
                onChanged: (v) => set(v.round()),
              ),
            ),
          ),
          SizedBox(
            width: 26,
            child: Text('$value', style: small, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('层数'), style: small),
            _Stepper(
              value: st.tiersMin,
              onChanged: (v) => board.tuneStyle(st.copyWith(tiersMin: v)),
            ),
            Text('–', style: small),
            _Stepper(
              value: st.tiersMax,
              onChanged: (v) => board.tuneStyle(st.copyWith(tiersMax: v)),
            ),
          ],
        ),
        slider(
          tr('横线斜'),
          st.slantH,
          (v) => board.tuneStyle(st.copyWith(slantH: v)),
        ),
        slider(
          tr('竖线斜'),
          st.slantV,
          (v) => board.tuneStyle(st.copyWith(slantV: v)),
        ),
        slider(
          tr('出血'),
          st.bleed,
          (v) => board.tuneStyle(st.copyWith(bleed: v)),
        ),
        slider(
          tr('格里再分'),
          st.subdivide,
          (v) => board.tuneStyle(st.copyWith(subdivide: v)),
        ),
        slider(tr('大格'), st.big, (v) => board.tuneStyle(st.copyWith(big: v))),
        slider(
          tr('框线粗细'),
          (board.page.border - 100) * 100 ~/ 1400,
          (v) => board.setBorder(100 + v * 1400 ~/ 100),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: board.fixedCount,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => board.setDrawOptions(fixed: v ?? false),
            ),
            Text(tr('指定格数'), style: small),
            _Stepper(
              value: board.minPanels,
              onChanged: board.fixedCount
                  ? (v) => board.setDrawOptions(min: v)
                  : null,
            ),
            Text('–', style: small),
            _Stepper(
              value: board.maxPanels,
              onChanged: board.fixedCount
                  ? (v) => board.setDrawOptions(max: v)
                  : null,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('一次抽'), style: small),
            const SizedBox(width: 6),
            for (final n in const [8, 16, 24]) ...[
              PennaChip(
                label: '$n',
                selected: board.drawCount == n,
                onTap: () => board.setDrawOptions(count: n),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ],
    );
  }
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
        // 一排放不下时左右滑(滚轮也能滚)。
        Expanded(
          child: ScrollStrip(
            gap: 8,
            children: [
              for (var i = 0; i < draw.found.length; i++)
                _Thumb(
                  page: board.candidatePage(i),
                  characters: board.project.characters,
                  label: tr('{0} 格', [draw.found[i].count]),
                  score: draw.found[i].score,
                  selected: i == at,
                  onTap: () => board.preview(i),
                ),
            ],
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

/// 一张候选的缩略图:套上眼前这页的内容(人偶),下面写几格、几分。
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.page,
    required this.characters,
    required this.label,
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final MangaPage page;
  final List<MangaCharacter> characters;
  final String label;

  /// 得分(0–100),标在缩略图右上角。
  final int score;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: MangaPainter(
                      page: page,
                      characters: characters,
                      overlays: false,
                      pad: 4,
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Tooltip(
                    message: tr('得分'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: selected
                            ? PennaColors.primary
                            : const Color(0xCC374151),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$score',
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // 字比缩略图宽时缩小,不挤到旁边那张。
          SizedBox(
            width: _thumbWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? PennaColors.primary : PennaColors.slate500,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// − 数字 + 的小步进器;[onChanged] 为 null 时变灰。
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        iconSize: 14,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        onPressed: onChanged == null ? null : () => onChanged!(value - 1),
      ),
      Text(
        '$value',
        style: TextStyle(
          fontSize: 12.5,
          color: onChanged == null ? PennaColors.slate400 : null,
        ),
      ),
      IconButton(
        iconSize: 14,
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        onPressed: onChanged == null ? null : () => onChanged!(value + 1),
      ),
    ],
  );
}
