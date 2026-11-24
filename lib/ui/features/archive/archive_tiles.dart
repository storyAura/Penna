part of 'archive_page.dart';

/// 一条存档上的几个操作。
typedef _Actions = ({
  String Function(Layout) export,
  VoidCallback onRestore,
  VoidCallback onDelete,
  VoidCallback onUpload,
});

/// 一条存档复制出去的文字和卡片上的预览文字。
/// 提示词用干净的(放回成稿时才带分段标注);布局复制的是交出去的 MOSS JSON,
/// 预览是尺寸、框数和整体描述。
({String clean, String preview}) _texts(ArchiveEntry entry, _Actions actions) {
  if (entry.kind == archiveManga) {
    final p = _mangaOf(entry);
    if (p == null) return (clean: '', preview: '');
    final outline = mangaOutline(p);
    return (
      clean: outline,
      preview: [
        tr('{0} 页 · {1} 个角色', [p.pages.length, p.characters.length]),
        if (p.setting.trim().isNotEmpty) p.setting.trim(),
      ].join('\n'),
    );
  }
  final layout = entry.kind == archiveLayout ? _layoutOf(entry) : null;
  final clean = entry.kind == archiveLayout
      ? layout == null
            ? ''
            : actions.export(layout)
      : stripSectionLabels(entry.text);
  final preview = layout == null
      ? clean
      : [
          tr('{0}×{1} · {2} 个框', [
            layout.width,
            layout.height,
            layout.boxes.length,
          ]),
          if (layout.caption.trim().isNotEmpty) layout.caption.trim(),
        ].join('\n');
  return (clean: clean, preview: preview);
}

/// 「放回成稿」「放到区域控制工作台」或「放到漫画分镜工作台」。
String _restoreLabel(ArchiveEntry entry) => switch (entry.kind) {
  archiveLayout => tr('放到区域控制工作台'),
  archiveManga => tr('放到漫画分镜工作台'),
  _ => tr('放回成稿'),
};

/// 漫画存档里的作品;读不了是 null。
MangaProject? _mangaOf(ArchiveEntry entry) {
  try {
    return MangaProject.fromJson(jsonDecode(entry.text));
  } on FormatException {
    return null;
  }
}

/// 分类的小药丸。
class _CategoryPill extends StatelessWidget {
  const _CategoryPill(this.category);

  final String category;

  @override
  Widget build(BuildContext context) => PennaCard(
    color: PennaColors.primaryBg,
    borderColor: PennaColors.primaryBorder,
    radius: 99,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
    child: Text(
      tr(category),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: PennaColors.primary,
      ),
    ),
  );
}

/// 一个只有图标的小按钮。
Widget _iconButton(IconData icon, String tip, VoidCallback onPressed) =>
    IconButton(
      tooltip: tip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      color: PennaColors.slate500,
      icon: Icon(icon),
      onPressed: onPressed,
    );

/// 左边清单里的一个系列:颜色、名字、条数、最近存的时间。选中的那个底色深一点。
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
    this.time,
    this.tint,
  });

  final String name;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final DateTime? time;

  /// 系列的颜色;「全部」那一行没有。
  final SeriesTint? tint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Material(
      color: selected
          ? (tint?.bg ?? PennaColors.primaryBg)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 5,
                backgroundColor: tint?.text ?? PennaColors.slate400,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? tint?.text : null,
                      ),
                    ),
                    if (time case final t?)
                      Text(
                        shortTime(t),
                        style: TextStyle(
                          fontSize: 11,
                          color: PennaColors.slate400,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: 12, color: PennaColors.slate500),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 右边列表里的一条:有预览图时图在左边;名字一行,正文三行,右上角是几个操作。
/// [text] 是要显示的正文(同系列里一样的开头已经省掉);[tint] 给了就在名字前面
/// 标出它属于哪个系列(看「全部」时)。
class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.entry,
    required this.actions,
    required this.text,
    this.tint,
  });

  final ArchiveEntry entry;
  final _Actions actions;
  final String text;
  final SeriesTint? tint;

  @override
  Widget build(BuildContext context) => PennaCard(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.image.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PreviewImage(
              path: entry.image,
              width: 60,
              height: 80,
              veil: true,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (tint case final t?) ...[
                    Flexible(
                      flex: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: t.bg,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: t.border),
                        ),
                        child: Text(
                          tr(entry.category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: _EntryTitle(entry)),
                  Text(
                    shortTime(entry.time),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                  const SizedBox(width: 6),
                  // 最常用的一个留着字,别的几个只画图标(悬停看名字)。
                  PennaButton(
                    label: _restoreLabel(entry),
                    icon: Icons.keyboard_double_arrow_up,
                    onPressed: actions.onRestore,
                  ),
                  _iconButton(
                    Icons.content_copy,
                    entry.kind == archiveLayout ? tr('复制 JSON') : tr('复制'),
                    () => copyWithToast(
                      context,
                      _texts(entry, actions).clean,
                      tr('已复制'),
                    ),
                  ),
                  _iconButton(
                    Icons.add_photo_alternate_outlined,
                    tr('上传预览图'),
                    actions.onUpload,
                  ),
                  _iconButton(Icons.delete_outline, tr('删除'), actions.onDelete),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: monoStyle.copyWith(
                  fontSize: 11.5,
                  color: PennaColors.slate500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 一条存档的名字;没起名的写「未命名」。
class _EntryTitle extends StatelessWidget {
  const _EntryTitle(this.entry);

  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context) => Text(
    entry.title.isEmpty ? tr('未命名') : entry.title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: entry.title.isEmpty ? PennaColors.slate400 : PennaColors.text,
    ),
  );
}

/// 几段文字开头一样的那一截有多长:只有一段、或一样的不到 [least] 个字时是 0
/// (不值得省)。停在空格或标点上,不把一个词从中间切开。
int commonLead(List<String> texts, {int least = 16}) {
  if (texts.length < 2) return 0;
  var n = texts.map((t) => t.length).reduce((a, b) => a < b ? a : b);
  for (final t in texts.skip(1)) {
    var i = 0;
    while (i < n && t.codeUnitAt(i) == texts.first.codeUnitAt(i)) {
      i++;
    }
    n = i;
  }
  final lead = texts.first.substring(0, n);
  final cut = lead.lastIndexOf(RegExp(r'[\s,,。.;;、]'));
  final at = cut < 0 ? 0 : cut + 1;
  return at < least ? 0 : at;
}

/// 大缩略图里的一格:上面是预览图(没有就是几行文字),下面是名字和几个小按钮。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.actions});

  final ArchiveEntry entry;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final (:clean, :preview) = _texts(entry, actions);
    return PennaCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => PreviewImage(
              path: entry.image,
              width: box.maxWidth,
              height: box.maxWidth * 4 / 3,
              veil: true,
              blank: ColoredBox(
                color: PennaColors.slate50,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    preview,
                    overflow: TextOverflow.fade,
                    style: monoStyle.copyWith(
                      fontSize: 10.5,
                      color: PennaColors.slate500,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.title.isEmpty ? tr('未命名') : entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: entry.title.isEmpty
                  ? PennaColors.slate400
                  : PennaColors.text,
            ),
          ),
          // 分类单独一行:和四个按钮挤在一行时格子窄了药丸会被压成空的。
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: _CategoryPill(entry.category),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _iconButton(
                Icons.add_photo_alternate_outlined,
                tr('上传预览图'),
                actions.onUpload,
              ),
              _iconButton(
                Icons.keyboard_double_arrow_up,
                _restoreLabel(entry),
                actions.onRestore,
              ),
              _iconButton(
                Icons.content_copy,
                tr('复制'),
                () => copyWithToast(context, clean, tr('已复制')),
              ),
              _iconButton(Icons.delete_outline, tr('删除'), actions.onDelete),
            ],
          ),
        ],
      ),
    );
  }
}

/// 档案库里存的布局;读不了时为 null。
Layout? _layoutOf(ArchiveEntry entry) {
  try {
    return Layout.fromJson(jsonDecode(entry.text) as Map<String, dynamic>);
  } on Object {
    return null;
  }
}
