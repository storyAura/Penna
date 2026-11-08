import 'package:flutter/material.dart';

import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_gacha.dart';
import '../../../core/harness/manga/manga_geometry.dart';
import '../../../l10n/l10n.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'manga_board.dart';

/// 分量的三档:小格、普通、重点。
const _weights = [30, 50, 80];

/// 左边一栏:「设定」(作品名、世界观与画风、角色)和「本格」(选中那一格的内容)。
class MangaInspector extends StatefulWidget {
  const MangaInspector({super.key, required this.board});

  final MangaBoard board;

  @override
  State<MangaInspector> createState() => _MangaInspectorState();
}

class _MangaInspectorState extends State<MangaInspector> {
  bool _setting = true;
  String? _last;

  MangaBoard get board => widget.board;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: board,
    builder: (context, _) {
      // 新点了一格就切到「本格」。
      if (board.selected != _last) {
        _last = board.selected;
        if (_last != null) _setting = false;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                PennaChip(
                  label: tr('设定'),
                  selected: _setting,
                  onTap: () => setState(() => _setting = true),
                ),
                const SizedBox(width: 6),
                PennaChip(
                  label: tr('本格'),
                  selected: !_setting,
                  onTap: () => setState(() => _setting = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: SmoothScroller(
              builder: (controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: _setting ? _settingFields() : _panelFields(context),
              ),
            ),
          ),
        ],
      );
    },
  );

  // 外面(撤销、Agent、抽卡)改了内容时换个 key,输入框读新的字。
  Key _key(String name) => ValueKey('$name@${board.revision}');

  List<Widget> _settingFields() {
    final p = board.project;
    return [
      PennaField(
        key: _key('title'),
        label: tr('作品名'),
        value: p.title,
        onChanged: board.setTitle,
      ),
      const SizedBox(height: 10),
      PennaField(
        key: _key('setting'),
        label: tr('世界观与画风'),
        value: p.setting,
        maxLines: 6,
        hint: tr('时代、地点、故事梗概、画风'),
        onChanged: board.setSetting,
      ),
      const SizedBox(height: 14),
      _Heading(tr('角色')),
      for (final (i, c) in p.characters.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PennaCard(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PennaField(
                        key: _key('name-$i'),
                        label: tr('名字'),
                        value: c.name,
                        onChanged: (v) => board.setCharacter(
                          i,
                          MangaCharacter(name: v, look: c.look),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('删除'),
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      onPressed: () => board.removeCharacter(i),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                PennaField(
                  key: _key('look-$i'),
                  label: tr('外貌'),
                  value: c.look,
                  maxLines: 3,
                  hint: tr('发型发色、瞳色、服装、标志物'),
                  onChanged: (v) => board.setCharacter(
                    i,
                    MangaCharacter(name: c.name, look: v),
                  ),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => board.setCharacter(
            p.characters.length,
            MangaCharacter(name: tr('角色 {0}', [p.characters.length + 1])),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: Text(tr('添加角色')),
        ),
      ),
    ];
  }

  List<Widget> _panelFields(BuildContext context) {
    final panel = board.selectedPanel;
    if (panel == null) {
      return [
        PennaField(
          key: _key('note-${board.page.id}'),
          label: tr('这一页'),
          value: board.page.note,
          maxLines: 3,
          hint: tr('这一页讲什么'),
          onChanged: (v) => board.setNote(v),
        ),
        const SizedBox(height: 16),
        Text(
          tr('在画布上点一格'),
          style: TextStyle(fontSize: 12, color: PennaColors.slate400),
        ),
      ];
    }
    final n = readingOrder(board.page).indexOf(panel.id) + 1;
    void set(MangaPanel p, [String? typing]) =>
        board.updatePanel(p, typing: typing);
    void report(String? problem) {
      if (problem != null) showToast(context, problem, warn: true);
    }

    final locked = panel.locked;
    return [
      Row(
        children: [
          Text(
            tr('第 {0} 格', [n]),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            tooltip: locked ? tr('解锁') : tr('锁定(抽镜头、Agent 不改它)'),
            iconSize: 17,
            color: locked ? PennaColors.primary : PennaColors.slate500,
            icon: Icon(locked ? Icons.lock : Icons.lock_open),
            onPressed: () => set(panel.copyWith(locked: !locked)),
          ),
        ],
      ),
      _Heading(tr('景别')),
      _Chips(
        label: tr,
        options: mangaFramings,
        selected: {panel.framing},
        onTap: locked
            ? null
            : (v) => set(panel.copyWith(framing: panel.framing == v ? '' : v)),
      ),
      _Heading(tr('角度')),
      _Chips(
        label: tr,
        options: mangaAngles,
        selected: {panel.angle},
        onTap: locked
            ? null
            : (v) => set(panel.copyWith(angle: panel.angle == v ? '' : v)),
      ),
      _Heading(tr('出场')),
      _Chips(
        options: [for (final c in board.project.characters) c.name],
        selected: panel.cast.toSet(),
        onTap: locked
            ? null
            : (v) => set(
                panel.copyWith(
                  cast: panel.cast.contains(v)
                      ? ([...panel.cast]..remove(v))
                      : [...panel.cast, v],
                ),
              ),
      ),
      const SizedBox(height: 10),
      PennaField(
        key: _key('action-${panel.id}'),
        label: tr('动作与画面'),
        value: panel.action,
        maxLines: 3,
        onChanged: (v) => set(panel.copyWith(action: v), 'action'),
      ),
      _Heading(tr('台词')),
      for (final (i, line) in panel.lines.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 84,
                child: PennaField(
                  key: _key('speaker-${panel.id}-$i'),
                  label: tr('谁说'),
                  value: line.speaker,
                  onChanged: (v) => set(
                    panel.copyWith(
                      lines: [...panel.lines]
                        ..[i] = (speaker: v, text: line.text),
                    ),
                    'speaker-$i',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PennaField(
                  key: _key('line-${panel.id}-$i'),
                  label: tr('台词'),
                  value: line.text,
                  maxLines: 2,
                  onChanged: (v) => set(
                    panel.copyWith(
                      lines: [...panel.lines]
                        ..[i] = (speaker: line.speaker, text: v),
                    ),
                    'line-$i',
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('删除'),
                iconSize: 15,
                icon: const Icon(Icons.close),
                onPressed: () =>
                    set(panel.copyWith(lines: [...panel.lines]..removeAt(i))),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => set(
            panel.copyWith(
              lines: [
                ...panel.lines,
                (speaker: panel.cast.firstOrNull ?? '', text: ''),
              ],
            ),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: Text(tr('添加台词')),
        ),
      ),
      _Heading(tr('分量')),
      _Chips(
        options: [tr('小格'), tr('普通'), tr('重点')],
        selected: {
          [tr('小格'), tr('普通'), tr('重点')][_nearest(panel.emphasis)],
        },
        onTap: (v) => set(
          panel.copyWith(
            emphasis: _weights[[tr('小格'), tr('普通'), tr('重点')].indexOf(v)],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _Action(
            Icons.horizontal_split_outlined,
            tr('上下拆开'),
            () => report(board.splitSelected(MangaAxis.y)),
          ),
          _Action(
            Icons.vertical_split_outlined,
            tr('左右拆开'),
            () => report(board.splitSelected(MangaAxis.x)),
          ),
          _Action(
            Icons.merge_outlined,
            tr('和相邻格合并'),
            () => report(board.mergeSelected()),
          ),
          _Action(
            Icons.cleaning_services_outlined,
            tr('清空'),
            locked ? null : board.clearSelected,
          ),
        ],
      ),
    ];
  }

  static int _nearest(int emphasis) {
    var best = 0;
    for (final (i, w) in _weights.indexed) {
      if ((w - emphasis).abs() < (_weights[best] - emphasis).abs()) best = i;
    }
    return best;
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: PennaColors.slate500,
      ),
    ),
  );
}

/// 一排可点的小药丸;[onTap] 为 null 时只看不点(格锁着)。
class _Chips extends StatelessWidget {
  const _Chips({
    required this.options,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final List<String> options;

  /// 显示时怎么翻译(景别、角度存的是中文原文)。
  final String Function(String)? label;
  final Set<String> selected;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) => options.isEmpty
      ? Text(
          tr('先在「设定」里加角色'),
          style: TextStyle(fontSize: 12, color: PennaColors.slate400),
        )
      : Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in options)
              PennaChip(
                label: label?.call(o) ?? o,
                selected: selected.contains(o),
                onTap: onTap == null ? null : () => onTap!(o),
              ),
          ],
        );
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onPressed);

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => PennaButton(
    label: label,
    icon: icon,
    borderColor: PennaColors.border,
    onPressed: onPressed,
  );
}
