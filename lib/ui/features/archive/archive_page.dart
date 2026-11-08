import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/harness/draft_block.dart';
import '../../../core/harness/layout.dart';
import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_script.dart';
import '../../../data/services/archive_store.dart';
import '../../core/gallery.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../layout/layout_board.dart';
import '../settings/settings_sections.dart';
import '../studio/studio_view_model.dart';
import 'comfy_gallery.dart';
import '../../../l10n/l10n.dart';

/// 大缩略图的格子至少这么宽;格子之间隔这么远。
/// 「图片」分区:不在档案库的存档里,直接读 ComfyUI(`comfy_gallery.dart`)。
const _imagesKind = 'images';

const _tileWidth = 200.0;
const _gap = 10.0;

/// 问用户这份成稿叫什么、归到哪一类;取消返回 null。[title] 是先填好的名称(页名)。
Future<({String title, String category})?> showSaveDialog(
  BuildContext context,
  List<String> categories, {
  String title = '',
}) {
  var category = categories.firstOrNull ?? '';
  // 点了已有分类后,分类输入框靠它重建来显示选中的名字。
  var picks = 0;
  return showDialog<({String title, String category})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('保存到档案库'), style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PennaField(
                label: tr('名称'),
                hint: tr('可留空'),
                value: title,
                onChanged: (v) => title = v,
              ),
              const SizedBox(height: 12),
              PennaField(
                key: ValueKey(picks),
                label: tr('分类'),
                hint: tr(uncategorized),
                value: category,
                onChanged: (v) => setState(() => category = v),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in categories)
                      PennaChip(
                        label: tr(c), // 「未分类」要翻译,自己起的分类原样
                        selected: c == category.trim(),
                        onTap: () => setState(() {
                          category = c;
                          picks++;
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (title: title, category: category)),
            child: Text(tr('保存')),
          ),
        ],
      ),
    ),
  );
}

/// 档案库:用户存下来的成稿和区域控制的布局,分两个分区,按分类筛选。
/// 能拖着换顺序,能给每条配一张预览图,按列表或大缩略图看。
class ArchivePage extends StatefulWidget {
  const ArchivePage({
    super.key,
    required this.archive,
    required this.vm,
    required this.board,
    required this.onOpenStudio,
    required this.onOpenLayout,
    this.onOpenManga,
  });

  final ArchiveStore archive;
  final StudioViewModel vm;

  /// 区域控制工作台的画板:布局放回这里,不进主工作区的成稿。
  final LayoutBoard board;

  /// 放回成稿之后回到工作台。
  final VoidCallback onOpenStudio;

  /// 布局放回之后去区域控制工作台。
  final VoidCallback onOpenLayout;

  /// 漫画作品放回漫画分镜工作台(另起一个系列);放不了返回原因。
  final String? Function(MangaProject project)? onOpenManga;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  /// 看的是哪个分区。
  String _kind = archivePrompt;

  /// 只看这个分类;null 是全部。
  String? _category;

  /// 大缩略图(看预览图)还是列表。
  var _grid = false;

  void _restore(ArchiveEntry entry) {
    if (entry.kind == archiveManga) {
      final project = _mangaOf(entry);
      if (project == null) return showToast(context, tr('分镜读不了'), warn: true);
      final problem = widget.onOpenManga?.call(project);
      if (problem != null) showToast(context, problem, warn: true);
      return;
    }
    if (entry.kind == archiveLayout) {
      final layout = _layoutOf(entry);
      if (layout == null) return showToast(context, tr('布局读不了'), warn: true);
      widget.board.replace(layout);
      return widget.onOpenLayout();
    }
    final problem = widget.vm.restorePrompt((
      time: entry.time,
      text: entry.text,
    ), title: tr('档案库'));
    if (problem != null) return showToast(context, problem, warn: true);
    widget.onOpenStudio();
  }

  Future<void> _delete(ArchiveEntry entry) async {
    final name = entry.title.isEmpty ? tr('这条记录') : tr('「{0}」', [entry.title]);
    if (await confirmDelete(context, tr('删除{0}?', [name]), tr('删掉后找不回来。'))) {
      widget.archive.remove(entry.id);
    }
  }

  /// 换预览图:[source] 是选的或拖上来的图转成的 WebP。
  Future<void> _setImage(ArchiveEntry entry, Future<Uint8List?> source) async {
    final webp = await source;
    if (webp == null || !mounted) return;
    if (!widget.archive.setImage(entry.id, webp)) {
      showToast(context, tr('预览图没存上'), warn: true);
    }
  }

  Widget _item(ArchiveEntry entry) {
    final actions = (
      export: widget.board.exportJson,
      onRestore: () => _restore(entry),
      onDelete: () => _delete(entry),
      onUpload: () => _setImage(entry, pickPreview(context)),
    );
    return GalleryItem(
      key: ValueKey(entry.id),
      id: entry.id,
      onMove: (dragged) => widget.archive.move(dragged, entry.id),
      onImage: (path) => _setImage(entry, readPreview(context, path)),
      child: _grid
          ? _EntryTile(entry: entry, actions: actions)
          : _EntryCard(entry: entry, actions: actions),
    );
  }

  /// 大缩略图:一样大的格子排成几列。
  Widget _gridOf(List<ArchiveEntry> shown) => LayoutBuilder(
    builder: (context, box) {
      final columns = (box.maxWidth / _tileWidth).floor().clamp(2, 8);
      final width = ((box.maxWidth - _gap * (columns - 1)) / columns)
          .floorToDouble();
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final e in shown) SizedBox(width: width, child: _item(e)),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.archive,
      builder: (context, _) {
        final all = [
          for (final e in widget.archive.entries)
            if (e.kind == _kind) e,
        ];
        final categories = widget.archive.categoriesOf(_kind);
        // 筛着的分类被删空了就回到全部。
        final category = categories.contains(_category) ? _category : null;
        final shown = [
          for (final e in all)
            if (category == null || e.category == category) e,
        ];
        return ColoredBox(
          color: PennaColors.editorBg,
          child: Column(
            children: [
              PennaBar(
                color: PennaColors.card,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 15,
                    color: PennaColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('档案库'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 24),
                  for (final (kind, label) in [
                    (archivePrompt, tr('提示词')),
                    (archiveLayout, tr('区域控制')),
                    (archiveManga, tr('漫画')),
                    (_imagesKind, tr('图片')),
                  ]) ...[
                    PennaChip(
                      label: label,
                      selected: _kind == kind,
                      onTap: () => setState(() {
                        _kind = kind;
                        _category = null;
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_kind != _imagesKind) ...[
                    const SizedBox(width: 4),
                    Text(
                      tr('{0} 条', [all.length]),
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                    const Spacer(),
                    ViewSwitch(
                      grid: _grid,
                      onChanged: (g) => setState(() => _grid = g),
                    ),
                  ],
                ],
              ),
              if (_kind == _imagesKind)
                Expanded(
                  child: ComfyGallery(
                    vm: widget.vm,
                    onOpenStudio: widget.onOpenStudio,
                  ),
                )
              else if (all.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      switch (_kind) {
                        archiveLayout => tr('还没有存档 · 在区域控制工作台点「保存」'),
                        archiveManga => tr('还没有存档 · 在漫画分镜工作台点「保存」'),
                        _ => tr('还没有存档 · 在工作区点「保存」'),
                      },
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate400,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: SmoothScroller(
                    builder: (controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            PennaChip(
                              label: tr('全部'),
                              selected: category == null,
                              onTap: () => setState(() => _category = null),
                            ),
                            for (final c in categories)
                              PennaChip(
                                label: tr(c),
                                selected: c == category,
                                onTap: () => setState(() => _category = c),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_grid)
                          _gridOf(shown)
                        else
                          for (final entry in shown) ...[
                            _item(entry),
                            const SizedBox(height: 10),
                          ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

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

/// 列表里的一条:有预览图时图在左边,没有就不占地方。
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.actions});

  final ArchiveEntry entry;
  final _Actions actions;

  @override
  Widget build(BuildContext context) {
    final (:clean, :preview) = _texts(entry, actions);
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.image.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: PreviewImage(path: entry.image, width: 96, height: 128),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Flexible(flex: 0, child: _CategoryPill(entry.category)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.title.isEmpty ? tr('未命名') : entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: entry.title.isEmpty
                              ? PennaColors.slate400
                              : PennaColors.text,
                        ),
                      ),
                    ),
                    Text(
                      shortTime(entry.time),
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate400,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _iconButton(
                      Icons.add_photo_alternate_outlined,
                      tr('上传预览图'),
                      actions.onUpload,
                    ),
                    PennaButton(
                      label: _restoreLabel(entry),
                      icon: Icons.keyboard_double_arrow_up,
                      onPressed: actions.onRestore,
                    ),
                    PennaButton(
                      label: entry.kind == archiveLayout
                          ? tr('复制 JSON')
                          : tr('复制'),
                      icon: Icons.content_copy,
                      onPressed: () => copyWithToast(context, clean, tr('已复制')),
                    ),
                    IconButton(
                      tooltip: tr('删除'),
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      color: PennaColors.slate400,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: actions.onDelete,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  preview,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(child: _CategoryPill(entry.category)),
              const Spacer(),
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
