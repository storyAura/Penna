import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

/// 多选里的一项:[label] 是发出去的字,[detail] 是排在它后面的一行预览(可以是空串)。
typedef PickItem = ({String label, String detail});

/// 单选的选项:竖着一行一项,点哪一行就把它当成回答发出去。样子和 [MultiPick] 一样;
/// 第一项是模型推荐的,底色标出来。[onPick] 为 null 时只是摆着看。
class SinglePick extends StatelessWidget {
  const SinglePick({super.key, required this.options, required this.onPick});

  final List<String> options;
  final ValueChanged<String>? onPick;

  Widget _row(int i, String option) {
    final first = i == 0;
    return InkWell(
      onTap: () => onPick?.call(option),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: first ? PennaColors.primaryBg : PennaColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: first ? PennaColors.primaryBorder : PennaColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.radio_button_unchecked,
              size: 16,
              color: first ? PennaColors.primary : PennaColors.slate400,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: first ? PennaColors.primary : PennaColors.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: PennaColors.slate400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final live = onPick != null;
    return IgnorePointer(
      ignoring: !live,
      child: Opacity(
        opacity: live ? 1 : 0.55,
        child: PennaCard(
          color: PennaColors.slate50,
          radius: 10,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, option) in options.indexed) ...[
                if (i > 0) const SizedBox(height: 4),
                _row(i, option),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 多选的选项:竖着一行一项,勾上几个(或点「全选」),再点「确定」一起当成回答发出去。
/// 挑成稿里的段时,每行后面是那段提示词的开头。
/// [headings] 是分类小标题:排在第几项前面 → 标题。
/// [onSubmit] 为 null 时只是摆着看(不是最新那条回复,或正在生成)。
class MultiPick extends StatefulWidget {
  const MultiPick({
    super.key,
    required this.items,
    this.headings = const {},
    required this.onSubmit,
  });

  final List<PickItem> items;
  final Map<int, String> headings;
  final ValueChanged<String>? onSubmit;

  @override
  State<MultiPick> createState() => _PickState();
}

class _PickState extends State<MultiPick> {
  var _picked = const <String>{};

  @override
  void didUpdateWidget(MultiPick old) {
    super.didUpdateWidget(old);
    // 成稿的段变了:已经不在的勾掉。
    _picked = _picked.intersection({for (final i in widget.items) i.label});
  }

  void _toggle(String label) => setState(
    () => _picked = _picked.contains(label)
        ? _picked.difference({label})
        : {..._picked, label},
  );

  Widget _row(PickItem item) {
    final on = _picked.contains(item.label);
    return InkWell(
      onTap: () => _toggle(item.label),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: Motion.snap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: on ? PennaColors.primaryBg : PennaColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: on ? PennaColors.primaryBorder : PennaColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: on ? PennaColors.primary : PennaColors.slate400,
            ),
            const SizedBox(width: 8),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? PennaColors.primary : PennaColors.text,
              ),
            ),
            if (item.detail.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(
                    fontSize: 11,
                    color: PennaColors.slate500,
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
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final live = widget.onSubmit != null;
    final all = _picked.length == items.length;
    return IgnorePointer(
      ignoring: !live,
      child: Opacity(
        opacity: live ? 1 : 0.55,
        child: PennaCard(
          color: PennaColors.slate50,
          radius: 10,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, item) in items.indexed) ...[
                if (widget.headings[i] case final heading?)
                  Padding(
                    padding: EdgeInsets.only(
                      top: i > 0 ? 10 : 0,
                      bottom: 4,
                      left: 2,
                    ),
                    child: Text(
                      heading,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: PennaColors.slate500,
                      ),
                    ),
                  )
                else if (i > 0)
                  const SizedBox(height: 4),
                _row(item),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  PennaButton(
                    label: all ? tr('全不选') : tr('全选'),
                    icon: all ? Icons.deselect : Icons.select_all,
                    borderColor: PennaColors.border,
                    onPressed: () => setState(
                      () => _picked = all
                          ? const {}
                          : {for (final item in items) item.label},
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('已选 {0} / {1}', [_picked.length, items.length]),
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                  PennaButton(
                    label: tr('确定'),
                    icon: Icons.check,
                    background: PennaColors.primary,
                    foreground: Colors.white,
                    // 按原来的先后发出去;全选了就说「全部」。
                    onPressed: _picked.isEmpty
                        ? null
                        : () => widget.onSubmit?.call(
                            all
                                ? '全部'
                                : items
                                      .map((item) => item.label)
                                      .where(_picked.contains)
                                      .join('、'),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一张问卷(`<options form>`):每个小标题是一项要定的事,下面几个选项单选。
/// 每项默认选中第一个(模型推荐的),点别的换过去,再点一下选中的就是「你定」;
/// 点「确定」一次把各项交出去,一行一项「项目:选的」。
/// [headings] 同 [MultiPick];第一个标题前面的选项归一个没名字的组。
class FormPick extends StatefulWidget {
  const FormPick({
    super.key,
    required this.options,
    this.headings = const {},
    required this.onSubmit,
  });

  final List<String> options;
  final Map<int, String> headings;
  final ValueChanged<String>? onSubmit;

  @override
  State<FormPick> createState() => _FormPickState();
}

typedef _Group = ({String title, List<String> options});

class _FormPickState extends State<FormPick> {
  /// 第几组选的第几个;不在表里的是「你定」。
  late Map<int, int> _picked = _recommended();

  List<_Group> get _groups {
    final groups = <_Group>[];
    for (final (i, option) in widget.options.indexed) {
      final title = widget.headings[i];
      if (title != null || groups.isEmpty) {
        groups.add((title: title ?? '', options: []));
      }
      groups.last.options.add(option);
    }
    return groups;
  }

  Map<int, int> _recommended() => {
    for (final (g, group) in _groups.indexed)
      if (group.options.isNotEmpty) g: 0,
  };

  @override
  void didUpdateWidget(FormPick old) {
    super.didUpdateWidget(old);
    if (old.options.length != widget.options.length) _picked = _recommended();
  }

  void _tap(int group, int option) => setState(
    () => _picked = _picked[group] == option
        ? ({..._picked}..remove(group))
        : {..._picked, group: option},
  );

  /// 交出去的字:发给模型看的,不翻译。
  String _answer(List<_Group> groups) => [
    for (final (g, group) in groups.indexed)
      [
        if (group.title.isNotEmpty) '${group.title}:',
        switch (_picked[g]) {
          final i? => group.options[i],
          null => '你定',
        },
      ].join(),
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups.isEmpty) return const SizedBox.shrink();
    final live = widget.onSubmit != null;
    final hint = TextStyle(fontSize: 11, color: PennaColors.slate500);
    return IgnorePointer(
      ignoring: !live,
      child: Opacity(
        opacity: live ? 1 : 0.55,
        child: PennaCard(
          color: PennaColors.slate50,
          radius: 10,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (g, group) in groups.indexed) ...[
                if (g > 0) const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 5),
                  child: Row(
                    children: [
                      if (group.title.isNotEmpty)
                        Text(
                          group.title,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: PennaColors.slate500,
                          ),
                        ),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: Motion.snap,
                        child: _picked.containsKey(g)
                            ? const SizedBox.shrink()
                            : Text(tr('你定'), style: hint),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (i, option) in group.options.indexed)
                      PennaChip(
                        label: option,
                        selected: _picked[g] == i,
                        onTap: () => _tap(g, i),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  PennaButton(
                    label: tr('确定'),
                    icon: Icons.check,
                    background: PennaColors.primary,
                    foreground: Colors.white,
                    onPressed: () => widget.onSubmit?.call(_answer(groups)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
