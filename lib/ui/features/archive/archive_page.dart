import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../../../core/harness/draft_block.dart';
import '../../../core/harness/layout.dart';
import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_script.dart';
import '../../../data/services/archive_store.dart';
import '../../core/gallery.dart';
import '../../core/series_tint.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../layout/layout_board.dart';
import '../settings/settings_sections.dart';
import '../studio/studio_view_model.dart';
import 'comfy_gallery.dart';
import '../../../l10n/l10n.dart';

part 'archive_tiles.dart';

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

  /// 左边选中的系列(存档的分类);null 是还没挑,看最近存过东西的那个。
  String? _category;

  /// 大缩略图(看预览图)还是列表。
  var _grid = false;

  /// 看的是「全部」(点了左边最上面那一行),不是某一个系列。
  var _all = false;

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

  /// 左边找系列时打的字。
  var _query = '';

  /// 左边按住 Ctrl / Shift 多选中的系列;[_anchor] 是 Shift 连选的起点。
  Set<String> _picked = const {};
  String? _anchor;

  /// 点左边一行:Ctrl 加减、Shift 连选(同页签),不按就是换过去看。
  void _tapSeries(String c, List<String> shown, String? selected) {
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed) {
      final base = _picked.isEmpty && selected != null ? {selected} : _picked;
      setState(() {
        _anchor = c;
        _picked = base.contains(c) ? ({...base}..remove(c)) : {...base, c};
      });
      return;
    }
    if (keys.isShiftPressed) {
      final from = shown.indexOf(_anchor ?? selected ?? c);
      final to = shown.indexOf(c);
      final (lo, hi) = from < 0
          ? (to, to)
          : from < to
          ? (from, to)
          : (to, from);
      setState(() => _picked = shown.sublist(lo, hi + 1).toSet());
      return;
    }
    setState(() {
      _category = c;
      _all = false;
      _picked = const {};
      _anchor = null;
    });
  }

  /// 右键左边一行:选中了几个就是批量菜单(合并、批量改名、删除),否则只对这一个。
  /// 2026-11-25 用户要求。
  Future<void> _seriesMenu(String c, Offset at, List<String> shown) async {
    final many = _picked.length > 1 && _picked.contains(c);
    // 按左边列的先后,批量改名时编号才对得上眼睛看到的顺序。
    final which = many
        ? [
            for (final s in shown)
              if (_picked.contains(s)) s,
          ]
        : [c];
    final merge = tr('合并成一个系列…'),
        rename = many ? tr('批量改名…') : tr('改名…'),
        delete = tr('删除');
    final picked = await popMenu(context, at, [
      if (many) merge,
      rename,
      delete,
    ]);
    if (picked == null || !mounted) return;
    final archive = widget.archive;
    if (picked == delete) {
      final total = [
        for (final e in archive.entries)
          if (e.kind == _kind && which.contains(e.category)) e,
      ].length;
      if (!await confirmDelete(
        context,
        which.length == 1
            ? tr('删除「{0}」的 {1} 条存档?', [tr(which.single), total])
            : tr('删除 {0} 个系列的 {1} 条存档?', [which.length, total]),
        tr('删掉后找不回来。'),
      )) {
        return;
      }
      archive.removeCategories(_kind, which.toSet());
    } else {
      final name = await askName(
        context,
        picked,
        tr(which.first),
        hint: picked == rename && many ? tr('按顺序接上 1、2、3…') : '',
      );
      final base = name?.trim() ?? '';
      if (base.isEmpty || !mounted) return;
      if (picked == merge || !many) {
        archive.recategorize(_kind, which.toSet(), base);
        _category = base;
      } else {
        // 新名字不和没选中的系列撞上(撞了会并进去)。
        final taken = {
          for (final s in archive.categoriesOf(_kind))
            if (!which.contains(s)) s,
        };
        var n = 1;
        for (final s in which) {
          while (taken.contains('$base $n')) {
            n++;
          }
          archive.recategorize(_kind, {s}, '$base ${n++}');
        }
      }
    }
    setState(() {
      _picked = const {};
      _anchor = null;
    });
  }

  /// 整个系列放回工作台:另起一个同名的系列,一条存档一页。存档留在档案库里不动。
  void _restoreSeries(String category, List<ArchiveEntry> entries) {
    final problem = widget.vm.restoreSeries(tr(category), [
      for (final e in entries) (title: e.title, text: e.text, time: e.time),
    ]);
    if (problem != null) return showToast(context, problem, warn: true);
    showToast(
      context,
      tr('「{0}」的 {1} 页已放回工作台', [tr(category), entries.length]),
    );
    widget.onOpenStudio();
  }

  /// 把一个系列的存档全删掉,先问一句。
  Future<void> _deleteSeries(
    String category,
    List<ArchiveEntry> entries,
  ) async {
    if (!await confirmDelete(
      context,
      tr('删除「{0}」的 {1} 条存档?', [tr(category), entries.length]),
      tr('删掉后找不回来。'),
    )) {
      return;
    }
    for (final e in entries) {
      widget.archive.remove(e.id);
    }
  }

  SeriesTint _tintOf(String category) =>
      seriesTintOf(tr(category), widget.vm.config.config.seriesColors);

  /// 左边:这个分区里的各个系列,一行一个(颜色、名字、条数、最近存的时间),能打字找。
  Widget _seriesList(
    List<ArchiveEntry> all,
    List<String> categories,
    Map<String, int> counts,
    String? selected,
  ) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in categories)
        if (q.isEmpty || tr(c).toLowerCase().contains(q)) c,
    ];
    DateTime latest(String c) => all
        .where((e) => e.category == c)
        .map((e) => e.time)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            style: const TextStyle(fontSize: 13),
            contextMenuBuilder: pennaTextMenu,
            decoration: InputDecoration(
              isDense: true,
              // 图标框和输入框一样高,图标和字才在一条线上(2026-11-25 用户反馈没对齐)。
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 34,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
              hintText: tr('搜索系列'),
              hintStyle: TextStyle(fontSize: 13, color: PennaColors.slate400),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: [
              _SeriesRow(
                name: tr('全部'),
                count: all.length,
                selected: selected == null,
                onTap: () => setState(() {
                  _category = null;
                  _all = true;
                }),
              ),
              for (final c in shown)
                _SeriesRow(
                  name: tr(c),
                  count: counts[c] ?? 0,
                  time: latest(c),
                  tint: _tintOf(c),
                  selected: c == selected,
                  picked: _picked.contains(c),
                  onTap: () => _tapSeries(c, shown, selected),
                  onMenu: (at) => _seriesMenu(c, at, shown),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 右边:选中的那个系列(或全部)。上面是名字和对整个系列的操作,下面是它的各条。
  Widget _detailPane(List<ArchiveEntry> shown, String? selected) {
    final tint = selected == null ? null : _tintOf(selected);
    final previews = [
      for (final e in shown)
        _texts(e, (
          export: widget.board.exportJson,
          onRestore: () {},
          onDelete: () {},
          onUpload: () {},
        )).preview.replaceAll(RegExp(r'\s+'), ' '),
    ];
    // 同一个系列的提示词常常开头一样:每条从不一样的地方写起。
    final skip = selected == null ? 0 : commonLead(previews);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              if (tint != null) ...[
                Container(
                  width: 6,
                  height: 26,
                  decoration: BoxDecoration(
                    color: tint.text,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // 名字和条数占满左边,操作按钮靠右(2026-11-25 用户反馈:以前名字和 Spacer
              // 对半分剩下的宽度,按钮挤在中间)。
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        selected == null ? tr('全部') : tr(selected),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: tint?.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      tr('{0} 条', [shown.length]),
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected != null && _kind == archivePrompt) ...[
                PennaButton(
                  label: tr('整个系列放回工作台'),
                  icon: Icons.keyboard_double_arrow_up,
                  background: PennaColors.primary,
                  foreground: Colors.white,
                  onPressed: () => _restoreSeries(selected, shown),
                ),
                const SizedBox(width: 6),
              ],
              if (selected != null) ...[
                IconButton(
                  tooltip: tr('删除这个系列的存档'),
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  color: PennaColors.slate400,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteSeries(selected, shown),
                ),
                const SizedBox(width: 6),
              ],
              ViewSwitch(
                grid: _grid,
                onChanged: (g) => setState(() => _grid = g),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: PennaColors.border),
        Expanded(
          child: SmoothScroller(
            builder: (controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                if (_grid)
                  _gridOf(shown)
                else
                  for (final (i, entry) in shown.indexed) ...[
                    _item(
                      entry,
                      text: skip == 0
                          ? previews[i]
                          : '…${previews[i].substring(skip)}',
                      showCategory: selected == null,
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(ArchiveEntry entry, {String? text, bool showCategory = false}) {
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
          : _PageCard(
              entry: entry,
              actions: actions,
              text: text ?? '',
              tint: showCategory ? _tintOf(entry.category) : null,
            ),
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
      // 系列的颜色记在设置里:那边改了这边跟着变。
      listenable: Listenable.merge([widget.archive, widget.vm.config]),
      builder: (context, _) {
        final all = [
          for (final e in widget.archive.entries)
            if (e.kind == _kind) e,
        ];
        final categories = widget.archive.categoriesOf(_kind);
        final counts = widget.archive.countsOf(_kind);
        // 没挑过(或挑的那个被删空了)就看最近存过东西的那个系列;点了「全部」才看全部。
        final selected = _all
            ? null
            : categories.contains(_category)
            ? _category
            : categories.firstOrNull;
        final shown = [
          for (final e in all)
            if (selected == null || e.category == selected) e,
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
                        _picked = const {};
                        _all = false;
                        _query = '';
                      }),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_kind != _imagesKind) ...[
                    const SizedBox(width: 4),
                    Text(
                      tr('{0} 个系列 · {1} 条', [categories.length, all.length]),
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
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
                // 左边挑系列,右边看它的各条:来档案库多半是找某个系列,不是一条条翻。
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 270,
                        child: ColoredBox(
                          color: PennaColors.card,
                          child: _seriesList(all, categories, counts, selected),
                        ),
                      ),
                      VerticalDivider(width: 1, color: PennaColors.border),
                      Expanded(child: _detailPane(shown, selected)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
