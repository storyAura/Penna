import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/layout.dart';
import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_gacha.dart';
import '../../../core/harness/manga/manga_script.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../studio/chat_pane.dart';
import '../studio/right_bar.dart';
import '../studio/studio_view_model.dart';
import 'manga_board.dart';
import 'manga_canvas.dart';
import 'manga_inspector.dart';

part 'manga_gacha_bar.dart';

const _inspectorWidth = 320.0;
const _chatWidth = 420.0;

/// 漫画分镜工作台:左边设定和本格,中间一页页的分格(抽卡在下面),右边和分镜 Agent 对话。
/// 定好的一页交给区域控制工作台(带格子的布局)或主工作台(逐格写提示词)出图。
class MangaWorkbench extends StatefulWidget {
  const MangaWorkbench({
    super.key,
    required this.board,
    required this.chat,
    required this.config,
    required this.onToLayout,
    required this.onToStudio,
    required this.onOpenSettings,
  });

  final MangaBoard board;

  /// 分镜 Agent 那场对话(`chat.manga` 就是 [board])。
  final StudioViewModel chat;
  final ConfigService config;

  /// 一页换成的布局交给区域控制;放不了返回原因。
  final String? Function(Layout layout, String name) onToLayout;

  /// 交给主工作台对话框的一段话。
  final ValueChanged<String> onToStudio;
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

  String get _pageName => [
    if (board.project.title.isNotEmpty) board.project.title,
    tr('第 {0} 页', [board.pageIndex + 1]),
  ].join(' ');

  void _toLayout() {
    final layout = mangaToLayout(
      board.project,
      board.pageIndex,
      step: widget.config.config.layoutSnap,
    );
    final problem = widget.onToLayout(layout, _pageName);
    if (problem != null) showToast(context, problem, warn: true);
  }

  Future<void> _export() async {
    final at = await getSaveLocation(
      suggestedName: '$_pageName.png',
      acceptedTypeGroups: [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (at == null) return;
    final bytes = await mangaPng(board.page);
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
              onExport: _export,
              onToLayout: _toLayout,
              onToStudio: () =>
                  widget.onToStudio(mangaBrief(board.project, board.pageIndex)),
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
                            _PageTabs(board: board),
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
    required this.onExport,
    required this.onToLayout,
    required this.onToStudio,
  });

  final MangaBoard board;
  final VoidCallback onExport, onToLayout, onToStudio;

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
        const SizedBox(width: 16),
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
        const SizedBox(width: 4),
        PennaButton(
          label: tr('导出 PNG'),
          icon: Icons.image_outlined,
          borderColor: PennaColors.border,
          onPressed: onExport,
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: tr('交给区域控制'),
          icon: Icons.crop_free,
          tooltip: tr('整页一张图:每格一个框,人物和台词各一块'),
          borderColor: PennaColors.border,
          onPressed: onToLayout,
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: tr('交给工作台'),
          icon: Icons.space_dashboard_outlined,
          tooltip: tr('一格一张图:让 Agent 逐格写提示词'),
          background: PennaColors.primary,
          foreground: Colors.white,
          onPressed: onToStudio,
        ),
      ],
    );
  }
}

/// 页签:第几页,点了换过去;右键删除;最后一个「+」加一页。
class _PageTabs extends StatelessWidget {
  const _PageTabs({required this.board});

  final MangaBoard board;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: board,
    builder: (context, _) => SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        children: [
          for (var i = 0; i < board.project.pages.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onSecondaryTap: board.project.pages.length <= 1
                    ? null
                    : () async {
                        if (await confirmDelete(
                          context,
                          tr('删除第 {0} 页?', [i + 1]),
                          tr('这一页的分格和内容都会删掉,可以撤销。'),
                        )) {
                          board.removePage(i);
                        }
                      },
                child: Tooltip(
                  message: tr('右键删除'),
                  waitDuration: const Duration(milliseconds: 600),
                  child: PennaChip(
                    label: tr('第 {0} 页', [i + 1]),
                    selected: i == board.pageIndex,
                    onTap: () => board.showPage(i),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: tr('加一页'),
            iconSize: 17,
            icon: const Icon(Icons.add),
            onPressed: board.addPage,
          ),
        ],
      ),
    ),
  );
}
