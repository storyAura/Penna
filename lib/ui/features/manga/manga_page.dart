import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/layout.dart';
import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_gacha.dart';
import '../../../core/harness/manga/manga_script.dart';
import '../../../core/harness/manga/manga_styles.dart';
import '../../../data/services/archive_store.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/scroll_strip.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../archive/archive_page.dart';
import '../settings/settings_sections.dart';
import '../studio/chat_pane.dart';
import '../studio/right_bar.dart';
import '../studio/studio_view_model.dart';
import 'manga_board.dart';
import 'manga_canvas.dart';
import 'manga_inspector.dart';

part 'manga_gacha_bar.dart';
part 'manga_series_strip.dart';

const _inspectorWidth = 320.0;
const _chatWidth = 420.0;

/// 交给区域控制:一页换成的布局、页名、请那边 Agent 润色的话、人偶参考图。
/// 放不上或发不出返回原因。
typedef MangaToLayout = String? Function(
  Layout layout,
  String name,
  String request,
  Attachment? image,
);

/// 交给工作台:请工作台 Agent 逐格写提示词的话、人偶参考图。发不出返回原因。
typedef MangaToStudio = String? Function(String brief, Attachment? image);

/// 漫画分镜工作台:左边设定和本格,中间一个个系列、一页页的分格(抽卡在下面),
/// 右边和分镜 Agent 对话。定好的一页交给区域控制工作台(带格子的布局)或主工作台
/// (逐格写提示词)出图,交过去就请那边的 Agent 接着写。
class MangaWorkbench extends StatefulWidget {
  const MangaWorkbench({
    super.key,
    required this.board,
    required this.chat,
    required this.config,
    required this.archive,
    required this.onToLayout,
    required this.onToStudio,
    required this.onOpenSettings,
  });

  final MangaBoard board;

  /// 分镜 Agent 那场对话(`chat.manga` 就是 [board])。
  final StudioViewModel chat;
  final ConfigService config;

  /// 「保存」存进它的「漫画」分区。
  final ArchiveStore archive;
  final MangaToLayout onToLayout;
  final MangaToStudio onToStudio;
  final VoidCallback onOpenSettings;

  @override
  State<MangaWorkbench> createState() => _MangaWorkbenchState();
}

class _MangaWorkbenchState extends State<MangaWorkbench> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  MangaBoard get board => widget.board;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _appendInput(String text) {
    final had = _input.text.trimRight();
    final next = had.isEmpty ? text : '$had $text';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
  }

  String get _pageName => mangaPageName(board.project, board.pageIndex);

  /// 这一页的人偶参考图(给 Agent 看站位和镜头);画不出来是 null。
  Future<Attachment?> _reference() async {
    final bytes = await mangaPng(
      board.page,
      characters: board.project.characters,
      dpi: 150,
    );
    return bytes == null
        ? null
        : Attachment.image(
            name: '$_pageName.png',
            mime: 'image/png',
            bytes: bytes,
          );
  }

  void _report(String? problem) {
    if (problem != null && mounted) showToast(context, problem, warn: true);
  }

  Future<void> _toLayout() async {
    final p = board.project, at = board.pageIndex;
    final layout = mangaToLayout(p, at, step: widget.config.config.layoutSnap);
    final image = await _reference();
    if (!mounted) return;
    _report(
      widget.onToLayout(
        layout,
        _pageName,
        mangaLayoutRequest(p, at, image: image != null),
        image,
      ),
    );
  }

  Future<void> _toStudio() async {
    final p = board.project, at = board.pageIndex;
    final image = await _reference();
    if (!mounted) return;
    _report(widget.onToStudio(mangaBrief(p, at, image: image != null), image));
  }

  Future<void> _export() async {
    final at = await getSaveLocation(
      suggestedName: '$_pageName.png',
      acceptedTypeGroups: [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (at == null) return;
    final bytes = await mangaPng(
      board.page,
      characters: board.project.characters,
      figures: board.showFigures,
    );
    if (!mounted) return;
    if (bytes == null) return showToast(context, tr('导出失败'), warn: true);
    try {
      await File(at.path).writeAsBytes(bytes, flush: true);
      if (mounted) showToast(context, tr('已导出'));
    } on FileSystemException catch (e) {
      if (mounted) {
        showToast(context, tr('导出失败:{0}', [e.message]), warn: true);
      }
    }
  }

  /// 把眼前这个系列(整部作品)存进档案库的「漫画」分区,第一页的人偶图做预览图。
  Future<void> _save() async {
    final p = board.project;
    final picked = await showSaveDialog(
      context,
      widget.archive.categoriesOf(archiveManga),
      title: p.title,
    );
    if (picked == null) return;
    final id = widget.archive.add(
      text: jsonEncode(p.toJson()),
      title: picked.title,
      category: picked.category,
      kind: archiveManga,
    );
    if (mounted) showToast(context, tr('已存进档案库'));
    final png = await mangaPng(
      p.pages.first,
      characters: p.characters,
      dpi: 100,
    );
    if (png == null || id == null) return;
    final webp = await toPreviewWebP(png);
    if (webp != null) widget.archive.setImage(id, webp);
  }

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: PennaColors.border);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            board.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            board.redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): board.redo,
      },
      child: Column(
        children: [
          ListenableBuilder(
            listenable: board,
            builder: (context, _) => _TopBar(
              board: board,
              onSave: _save,
              onExport: _export,
              onToLayout: _toLayout,
              onToStudio: _toStudio,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: _inspectorWidth,
                        decoration: BoxDecoration(
                          color: PennaColors.bg,
                          border: Border(right: side),
                        ),
                        child: MangaInspector(board: board),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SeriesStrip(board: board),
                            Expanded(child: MangaCanvas(board: board)),
                            _GachaBar(board: board),
                          ],
                        ),
                      ),
                      Container(
                        width: _chatWidth,
                        decoration: BoxDecoration(border: Border(left: side)),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            widget.chat,
                            widget.config,
                          ]),
                          builder: (context, _) => ChatPane(
                            vm: widget.chat,
                            config: widget.config,
                            input: _input,
                            inputFocus: _inputFocus,
                            onQuickAction: _appendInput,
                            onOpenSettings: widget.onOpenSettings,
                          ),
                        ),
                      ),
                      const SizedBox(width: RightBar.closedWidth),
                    ],
                  ),
                ),
                // 右边的侧栏:ComfyUI 和别的工作台共用;历史对话是分镜这场的。
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: RightBar(
                    vm: widget.chat,
                    runner: widget.chat.comfy,
                    config: widget.config,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.board,
    required this.onSave,
    required this.onExport,
    required this.onToLayout,
    required this.onToStudio,
  });

  final MangaBoard board;
  final VoidCallback onSave, onExport, onToLayout, onToStudio;

  @override
  Widget build(BuildContext context) {
    final page = board.page;
    final paper = mangaPapers.entries
        .where(
          (e) =>
              mmToUm(e.value.$1) == page.width &&
              mmToUm(e.value.$2) == page.height,
        )
        .firstOrNull
        ?.key;
    return PennaBar(
      color: PennaColors.card,
      children: [
        Icon(Icons.auto_stories_outlined, size: 15, color: PennaColors.primary),
        const SizedBox(width: 6),
        Text(
          tr('漫画分镜工作台'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 14),
        PopupMenuButton<String>(
          popUpAnimationStyle: Motion.menu(context),
          tooltip: tr('纸张'),
          position: PopupMenuPosition.under,
          onSelected: (k) {
            final (w, h) = mangaPapers[k]!;
            board.setPaper(mmToUm(w), mmToUm(h));
          },
          itemBuilder: (_) => [
            for (final MapEntry(key: k, value: (w, h)) in mangaPapers.entries)
              CheckedPopupMenuItem(
                value: k,
                checked: k == paper,
                height: 34,
                child: Text(
                  '$k  $w×$h mm',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
          ],
          child: PennaChip(
            label: paper ?? '${page.width ~/ 1000}×${page.height ~/ 1000} mm',
            selected: false,
            onTap: null,
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: tr('阅读方向'),
          child: PennaChip(
            label: page.rtl ? tr('日式 · 从右往左') : tr('从左往右'),
            selected: false,
            onTap: () => board.setRtl(!page.rtl),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: tr('格里画人偶草图;关掉只写字'),
          child: PennaChip(
            label: tr('人偶'),
            selected: board.showFigures,
            onTap: () => board.setView(figures: !board.showFigures),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: tr('按阅读顺序连起各格'),
          child: PennaChip(
            label: tr('动线'),
            selected: board.showFlow,
            onTap: () => board.setView(flow: !board.showFlow),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: tr('撤销'),
          iconSize: 17,
          icon: const Icon(Icons.undo),
          onPressed: board.canUndo ? board.undo : null,
        ),
        IconButton(
          tooltip: tr('重做'),
          iconSize: 17,
          icon: const Icon(Icons.redo),
          onPressed: board.canRedo ? board.redo : null,
        ),
        IconButton(
          tooltip: tr('导出 PNG'),
          iconSize: 17,
          icon: const Icon(Icons.image_outlined),
          onPressed: onExport,
        ),
        const SizedBox(width: 4),
        PennaButton(
          label: tr('保存'),
          icon: Icons.save_outlined,
          tooltip: tr('整部作品存进档案库'),
          borderColor: PennaColors.border,
          onPressed: onSave,
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: tr('交给区域控制'),
          icon: Icons.crop_free,
          tooltip: tr('整页一张图:摆好格框交给区域控制的 Agent 写完'),
          borderColor: PennaColors.border,
          onPressed: onToLayout,
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: tr('交给工作台'),
          icon: Icons.space_dashboard_outlined,
          tooltip: tr('一格一张图:让工作台的 Agent 逐格写提示词'),
          background: PennaColors.primary,
          foreground: Colors.white,
          onPressed: onToStudio,
        ),
      ],
    );
  }
}
