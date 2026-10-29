part of 'local_page.dart';

// 「Tag 反推」:按系列挑一个打标模型(WD14、PixAI、CL、OppaiOracle),下载后给左边的图打标。

class _TagTab extends StatelessWidget {
  const _TagTab({
    required this.model,
    required this.onToDraft,
    required this.onSend,
  });

  final LocalModel model;
  final ValueChanged<String> onToDraft;
  final ValueChanged<String> onSend;

  /// 一个打标模型:自己下载过的可以删;文件夹里找到的标「本机」,直接用。
  Widget _taggerRow(TaggerModel m, {required bool selected}) {
    final files = model.taggerFiles(m);
    final own = files.isNotEmpty && model.ready(files);
    return _DownloadRow(
      model: model,
      keyName: m.id,
      name: m.name,
      note: [
        if (m.size > 0) tr('约 {0}', [_size(m.size)]),
        if (m.note.isNotEmpty) tr(m.note),
      ].join(' · '),
      files: files,
      onDownload: () => model.downloadTagger(m),
      foundAt: own ? null : model.foundTagger(m),
      selected: selected,
      onSelect: () => model.pickTagger(m.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = model.tagger;
    final ready = model.taggerPaths(current) != null;
    final tags = model.tags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: tr('模型'),
          trailing: _AddFolder(model: model),
          child: _GroupedModelList(
            current: current.series,
            groups: [
              for (final g in model.taggerGroups)
                (
                  series: g.series,
                  ids: [for (final m in g.items) m.id],
                  rows: [
                    for (final m in g.items)
                      _taggerRow(m, selected: m.id == current.id),
                  ],
                ),
            ],
            onMove: model.moveTagger,
          ),
        ),
        _Block(
          title: tr('阈值'),
          child: Column(
            children: [
              _Threshold(
                label: tr('通用'),
                value: model.general,
                onChanged: (v) => model.setThresholds(general: v),
              ),
              // OppaiOracle 只有一个阈值。
              if (current.kind != TaggerKind.oppai)
                _Threshold(
                  label: tr('角色'),
                  value: model.character,
                  onChanged: (v) => model.setThresholds(character: v),
                ),
            ],
          ),
        ),
        _Block(
          title: tr('结果'),
          trailing: PennaButton(
            label: model.tagging ? tr('推理中…') : tr('推理'),
            icon: Icons.sell_outlined,
            background: PennaColors.primary,
            foreground: Colors.white,
            onPressed: model.image == null || !ready || model.tagging
                ? null
                : () => _run(context, model.runTagger),
          ),
          child: tags == null
              ? Text(
                  model.tagging
                      ? tr('推理中…')
                      : !ready
                      ? tr('先下载选中的模型')
                      : model.image == null
                      ? tr('先在左边放一张图')
                      : tr('暂无结果'),
                  style: TextStyle(fontSize: 12, color: PennaColors.slate400),
                )
              : _TagResultView(
                  // 换了图就从全选开始;只调阈值时取消勾选的照旧不要。
                  key: ObjectKey(model.image),
                  result: tags,
                  onToDraft: onToDraft,
                  onSend: onSend,
                ),
        ),
      ],
    );
  }
}

/// 一个阈值滑条:低于它的标签不要。
class _Threshold extends StatelessWidget {
  const _Threshold({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.05, 1),
            min: 0.05,
            max: 1,
            divisions: 95,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.end,
            style: monoStyle.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 打出来的标签:分级、角色(琥珀色)、通用标签,鼠标停上去看把握。
/// 默认全选,点一个标签取消或选回它;「全选」在全选时变成全不选。
class _TagResultView extends StatefulWidget {
  const _TagResultView({
    super.key,
    required this.result,
    required this.onToDraft,
    required this.onSend,
  });

  final TagResult result;
  final ValueChanged<String> onToDraft;
  final ValueChanged<String> onSend;

  @override
  State<_TagResultView> createState() => _TagResultViewState();
}

class _TagResultViewState extends State<_TagResultView> {
  /// 取消勾选的标签名。
  Set<String> _off = const {};

  List<TagScore> get _all => [
    ...widget.result.characters,
    ...widget.result.general,
  ];

  void _toggle(String tag) => setState(
    () => _off = _off.contains(tag) ? ({..._off}..remove(tag)) : {..._off, tag},
  );

  Widget _chip(TagScore t, {bool character = false}) {
    final on = !_off.contains(t.tag);
    return Tooltip(
      message: '${(t.prob * 100).toStringAsFixed(1)}%',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _toggle(t.tag),
          child: AnimatedContainer(
            duration: Motion.snap,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: !on
                  ? PennaColors.card
                  : character
                  ? PennaColors.lock
                  : PennaColors.slate50,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: on && character
                    ? PennaColors.lockBorder
                    : PennaColors.border,
              ),
            ),
            child: Text(
              tagText(t.tag),
              style: monoStyle.copyWith(
                fontSize: 11.5,
                color: !on
                    ? PennaColors.slate400
                    : character
                    ? PennaColors.lockText
                    : PennaColors.text,
                decoration: on ? null : TextDecoration.lineThrough,
                decorationColor: PennaColors.slate400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final all = _all;
    final picked = all.where((t) => !_off.contains(t.tag)).length;
    final everything = picked == all.length;
    final prompt = tagPrompt(result, without: _off);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (all.isNotEmpty || result.rating != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    result.rating == null ? '' : tr('分级:{0}', [result.rating]),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                  ),
                ),
                if (all.isNotEmpty)
                  PennaButton(
                    label: tr('全选 {0}/{1}', [picked, all.length]),
                    icon: everything
                        ? Icons.check_box_outlined
                        : picked == 0
                        ? Icons.check_box_outline_blank
                        : Icons.indeterminate_check_box_outlined,
                    borderColor: PennaColors.border,
                    onPressed: () => setState(
                      () => _off = everything
                          ? {for (final t in all) t.tag}
                          : const {},
                    ),
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final t in result.characters) _chip(t, character: true),
            for (final t in result.general) _chip(t),
          ],
        ),
        if (all.isEmpty)
          Text(
            tr('没有超过阈值的标签'),
            style: TextStyle(fontSize: 12, color: PennaColors.slate400),
          )
        else if (prompt.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              tr('没有选中的标签'),
              style: TextStyle(fontSize: 12, color: PennaColors.slate400),
            ),
          )
        else ...[
          const SizedBox(height: 10),
          _ResultActions(
            text: prompt,
            onToDraft: widget.onToDraft,
            onSend: widget.onSend,
          ),
        ],
      ],
    );
  }
}
