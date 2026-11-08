import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_poses.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'manga_board.dart';
import 'manga_figures.dart';

const _cardWidth = 62.0, _cardHeight = 84.0;

/// 「本格」里的人偶:点出场角色(或在画布上点人偶)选中一个,
/// 给它挑姿势(按分类排的小图)、朝向、正侧背、大小,或回到自动。
class MangaFigureEditor extends StatefulWidget {
  const MangaFigureEditor({
    super.key,
    required this.board,
    required this.panel,
  });

  final MangaBoard board;
  final MangaPanel panel;

  @override
  State<MangaFigureEditor> createState() => _MangaFigureEditorState();
}

class _MangaFigureEditorState extends State<MangaFigureEditor> {
  String _group = mangaPoseGroups.first;

  MangaBoard get board => widget.board;

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final picked = board.selectedFigure;
    final name = picked?.panel == panel.id ? picked!.name : null;
    final small = TextStyle(fontSize: 11.5, color: PennaColors.slate500);
    if (panel.cast.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final n in panel.cast)
            PennaChip(
              label: n,
              selected: n == name,
              onTap: () => board.selectFigure(panel.id, n),
            ),
        ],
      ),
    ];
    if (name == null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('点一个人偶调姿势;在画布上按住能拖'), style: small),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    final f = panel.figureOf(name);
    void set(MangaFigure next) => board.setFigure(panel.id, name, next);
    final current = poseNamed(f.pose);
    final color = figureColor(board.project.characters, name);
    children.addAll([
      const SizedBox(height: 10),
      Row(
        children: [
          Text(tr('姿势'), style: small),
          const SizedBox(width: 8),
          Text(
            current == null ? tr('照动作') : tr(current.name),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (current != null)
            TextButton(
              onPressed: () => set(f.copyWith(pose: '')),
              child: Text(tr('照动作'), style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final g in mangaPoseGroups)
            PennaChip(
              label: tr(g),
              selected: g == _group,
              onTap: () => setState(() => _group = g),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final pose in mangaPoses.where((p) => p.group == _group))
            _PoseCard(
              pose: pose,
              color: color,
              selected: pose.name == f.pose,
              onTap: () => set(f.copyWith(pose: pose.name)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(tr('朝向'), style: small),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (v, label) in [
            (0, tr('自动')),
            (-1, tr('朝左')),
            (1, tr('朝右')),
          ])
            PennaChip(
              label: label,
              selected: f.facing == v,
              onTap: () => set(f.copyWith(facing: v)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          PennaChip(
            label: tr('自动'),
            selected: f.view.isEmpty,
            onTap: () => set(f.copyWith(view: '')),
          ),
          for (final v in MangaFigure.views)
            PennaChip(
              label: tr(v),
              selected: f.view == v,
              onTap: () => set(f.copyWith(view: v)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text(tr('大小'), style: small),
          IconButton(
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove),
            onPressed: () => set(f.copyWith(scale: f.scale - 10)),
          ),
          Text('${f.scale}%', style: const TextStyle(fontSize: 12.5)),
          IconButton(
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: () => set(f.copyWith(scale: f.scale + 10)),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          PennaButton(
            label: tr('回到自动位置'),
            icon: Icons.center_focus_strong_outlined,
            borderColor: PennaColors.border,
            onPressed: f.x == null && f.y == null
                ? null
                : () => set(f.unplaced()),
          ),
          PennaButton(
            label: tr('全部重置'),
            icon: Icons.restart_alt,
            borderColor: PennaColors.border,
            onPressed: f.isAuto ? null : () => set(const MangaFigure()),
          ),
        ],
      ),
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// 一个姿势的小图:人偶摆好这个姿势,缩到正好放进卡片,下面写名字。
class _PoseCard extends StatelessWidget {
  const _PoseCard({
    required this.pose,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final MangaPoseDef pose;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tr(pose.name),
    waitDuration: const Duration(milliseconds: 500),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: _cardWidth,
        height: _cardHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? PennaColors.primary : PennaColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: PosePainter(pose: pose, color: color),
              ),
            ),
            Text(
              tr(pose.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    ),
  );
}

/// 一个姿势的人偶,缩放到正好放进画框(姿势卡片、测试都用)。
class PosePainter extends CustomPainter {
  PosePainter({required this.pose, required this.color});

  final MangaPoseDef pose;
  final Color color;

  FigurePose _at(Offset anchor, double height) => FigurePose(
    FigureSpec(
      anchor: anchor,
      fromFeet: true,
      height: height,
      facing: 1,
      yaw: 25,
      pose: pose,
      color: color,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    // 先按 100 高摆一次量出外框,再缩放、挪到正中。
    final probe = _at(Offset.zero, 100);
    final b = probe.bounds;
    final k =
        math.min((size.width - 6) / b.width, (size.height - 6) / b.height) *
        100;
    final f = _at(Offset.zero, k);
    final shift = Offset(size.width / 2, size.height / 2) - f.bounds.center;
    paintFigure(canvas, _at(shift, k));
  }

  @override
  bool shouldRepaint(PosePainter old) => old.pose != pose || old.color != color;
}
