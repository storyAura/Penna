import 'package:flutter/material.dart';

import '../../../core/harness/draft_block.dart';
import '../../../data/services/archive_store.dart';
import '../../core/theme.dart';
import '../../core/smooth_scroll.dart';
import '../../core/widgets.dart';
import '../archive/archive_page.dart';
import '../settings/settings_sections.dart';
import 'body_card.dart';
import 'polish_dialog.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'prompt_summary.dart';

/// 顶栏里的小计数,例如「128 字符」。
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.unit});

  final int value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate50,
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$value',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: PennaColors.text,
              ),
            ),
            TextSpan(text: ' $unit'),
          ],
        ),
        style: TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
    );
  }
}

/// 左栏:上半成稿工作区,下半提示词汇总。
class PromptPane extends StatelessWidget {
  const PromptPane({
    super.key,
    required this.vm,
    required this.archive,
    this.onDiscuss,
  });

  final StudioViewModel vm;
  final ArchiveStore archive;

  /// 用户要拿成稿里的某一段去和 Agent 讨论。
  final ValueChanged<String>? onDiscuss;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PennaColors.card,
      child: Column(
        children: [
          Expanded(
            flex: 14,
            child: _DraftSection(
              vm: vm,
              archive: archive,
              onDiscuss: onDiscuss,
            ),
          ),
          Expanded(flex: 10, child: _SummarySection(vm: vm)),
        ],
      ),
    );
  }
}

class _DraftSection extends StatefulWidget {
  const _DraftSection({
    required this.vm,
    required this.archive,
    required this.onDiscuss,
  });

  final StudioViewModel vm;
  final ArchiveStore archive;
  final ValueChanged<String>? onDiscuss;

  @override
  State<_DraftSection> createState() => _DraftSectionState();
}

class _DraftSectionState extends State<_DraftSection> {
  StudioViewModel get vm => widget.vm;
  ArchiveStore get archive => widget.archive;
  ValueChanged<String>? get onDiscuss => widget.onDiscuss;

  /// 每一段的中文对照都展开着。
  bool _zhOpen = false;

  /// [section] 是只润色某一段时那段提示词的范围;不给就按用户自己的选区来。
  Future<void> _polish(BuildContext context, {(int, int)? section}) async {
    if (section != null) vm.bodySelection = section;
    final instruction = await showPolishDialog(context, vm);
    if (instruction == null) {
      // 这个范围是替用户定的,取消了就别留着,免得下次润色还落在这一段上。
      if (section != null) vm.bodySelection = null;
      return;
    }
    final problem = await vm.polish(instruction);
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  Future<void> _clear(BuildContext context) async {
    if (await confirmDelete(
      context,
      tr('清空工作区?'),
      tr('当前成稿会记进历史提示词,可以从那里放回来。'),
    )) {
      vm.clearDraft();
    }
  }

  /// 把当前成稿存进档案库(带着分段标注,放回来时分段还在)。
  Future<void> _save(BuildContext context) async {
    final text = vm.labeledPrompt;
    final picked = await showSaveDialog(
      context,
      archive.categoriesOf(archivePrompt),
      title: vm.pageName,
    );
    if (picked == null) return;
    archive.add(text: text, title: picked.title, category: picked.category);
    if (context.mounted) showToast(context, tr('已存进档案库'));
  }

  /// 把眼前这个系列的每一页都存进档案库:一页一条,分类就是系列的名字。
  /// 档案库里已经有一字不差的就跳过,只存新的和改过的。
  void _saveSeries(BuildContext context) {
    final all = vm.seriesPrompts;
    if (all.isEmpty) return showToast(context, tr('这个系列还是空的'), warn: true);
    final saved = {
      for (final e in archive.entries)
        if (e.kind == archivePrompt) e.text,
    };
    final prompts = [
      for (final p in all)
        if (!saved.contains(p.text)) p,
    ];
    if (prompts.isEmpty) {
      return showToast(context, tr('这个系列的页都已经存过了'), warn: true);
    }
    final category = vm.seriesName(vm.series);
    final now = DateTime.now();
    // 档案库里新的在前:倒着存,第 1 页才排在最上面。时间各错开一点,编号不会撞。
    for (final (i, p) in prompts.reversed.indexed) {
      archive.add(
        text: p.text,
        title: p.title,
        category: category,
        now: now.add(Duration(microseconds: i)),
      );
    }
    final skipped = all.length - prompts.length;
    showToast(
      context,
      skipped == 0
          ? tr('「{0}」的 {1} 页已存进档案库', [category, prompts.length])
          : tr('「{0}」新存了 {1} 页,{2} 页之前存过', [category, prompts.length, skipped]),
    );
  }

  Future<void> _pin(BuildContext context) async {
    if (vm.pinSelection()) return;
    final text = await showPinDialog(context);
    if (text != null) vm.addPin(text);
  }

  Future<void> _translate(
    BuildContext context, {
    bool selection = false,
  }) async {
    final problem = await vm.translateDraft(selection: selection);
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  /// 界面语言要不要每段的对照译文(英文界面不要)。
  bool get _gloss => vm.config.config.glossLanguage != null;

  /// 工作区顶栏。[label] 放不下时把按钮上的字变成空串,[tip] 那时把名字放进悬停提示。
  Widget _toolbar(
    BuildContext context,
    String prompt,
    int words,
    bool series,
    String Function(String) label,
    String? Function(String, [String?]) tip,
  ) {
    return PennaBar(
      color: PennaColors.card,
      minContentWidth: 140 + 40 * (6 + (_gloss ? 1 : 0) + (series ? 1 : 0)),
      children: [
        CircleAvatar(radius: 4, backgroundColor: PennaColors.amber),
        const SizedBox(width: 6),
        Text(
          tr('工作区'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        // 窄的时候计数先让位,再是状态;放不下就不画,按钮始终完整。
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final chip = vm.pending != null && box.maxWidth >= _chipRoom;
              final stats =
                  prompt.isNotEmpty &&
                  box.maxWidth >= _statsRoom + (chip ? _chipRoom : 0);
              return ClipRect(
                child: Row(
                  children: [
                    if (stats) ...[
                      _Stat(value: prompt.length, unit: tr('字符')),
                      const SizedBox(width: 6),
                      _Stat(value: words, unit: tr('词')),
                      const SizedBox(width: 6),
                    ],
                    if (chip)
                      Flexible(child: _PendingChip(more: vm.queuedDiffs)),
                  ],
                ),
              );
            },
          ),
        ),
        PennaButton(
          label: label(tr('清空')),
          icon: Icons.cleaning_services_outlined,
          borderColor: PennaColors.border,
          tooltip: tip(tr('清空'), tr('清空工作区,开始写下一条')),
          onPressed: vm.body.isEmpty ? null : () => _clear(context),
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: label(tr('保存')),
          icon: Icons.bookmark_add_outlined,
          borderColor: PennaColors.border,
          tooltip: tip(tr('保存'), tr('存进档案库')),
          onPressed: prompt.isEmpty ? null : () => _save(context),
        ),
        // 这个系列不止一页时滑出来:把整个系列一起存。
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.swift,
          alignment: Alignment.centerLeft,
          child: series
              ? Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: PopIn(
                    child: PennaButton(
                      label: label(tr('保存系列')),
                      icon: Icons.collections_bookmark_outlined,
                      background: PennaColors.accent,
                      foreground: Colors.white,
                      tooltip: tip(tr('保存系列'), tr('把这个系列的每一页都存进档案库')),
                      onPressed: () => _saveSeries(context),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: label(tr('固定')),
          icon: Icons.push_pin_outlined,
          borderColor: PennaColors.border,
          tooltip: tip(tr('固定'), tr('固定选中的文字,没选就新增一段')),
          onPressed: vm.pending != null ? null : () => _pin(context),
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: label(tr('润色')),
          icon: Icons.auto_fix_high,
          borderColor: PennaColors.border,
          tooltip: tip(tr('润色'), tr('改写选中的一段,没选就是整栏')),
          onPressed: prompt.isEmpty || vm.isPolishing || vm.pending != null
              ? null
              : () => _polish(context),
        ),
        if (_gloss) ...[
          const SizedBox(width: 6),
          PennaButton(
            label: label(tr('翻译')),
            icon: Icons.translate,
            borderColor: PennaColors.border,
            tooltip: tip(tr('翻译')),
            onPressed: prompt.isEmpty || vm.isTranslating
                ? null
                : () => _translate(context),
          ),
        ],
        const SizedBox(width: 6),
        PennaButton(
          label: label(tr('合并')),
          icon: Icons.merge_type,
          borderColor: PennaColors.border,
          tooltip: tip(tr('合并'), tr('去掉分段,合成一整段文字')),
          onPressed:
              vm.pending == null &&
                  vm.blocks.any(
                    (b) => !b.pinned && sectionSpans(b.text).isNotEmpty,
                  )
              ? vm.unsection
              : null,
        ),
        const SizedBox(width: 6),
        PennaButton(
          label: label(_zhOpen ? tr('收起') : tr('展开')),
          icon: _zhOpen ? Icons.unfold_less : Icons.unfold_more,
          borderColor: PennaColors.border,
          tooltip: tip(_zhOpen ? tr('收起') : tr('展开'), tr('展开或收起每一段的中文')),
          onPressed: vm.body.contains(zhMark)
              ? () => setState(() => _zhOpen = !_zhOpen)
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompt = vm.finalPrompt;
    final words = RegExp(r'\S+').allMatches(prompt).length;
    final series = vm.seriesLength > 1;
    return Column(
      children: [
        // 按钮的字放不下时(窄窗口、英文这类长的语言)只留图标,名字挪进悬停提示。
        LayoutBuilder(
          builder: (context, box) {
            final labels = [
              tr('清空'),
              tr('保存'),
              if (series) tr('保存系列'),
              tr('固定'),
              tr('润色'),
              if (_gloss) tr('翻译'),
              tr('合并'),
              _zhOpen ? tr('收起') : tr('展开'),
            ];
            // 左右边距、圆点和「工作区」三个字大约占 140。
            final compact =
                box.maxWidth < 140 + pennaButtonsWidth(context, labels);
            String label(String s) => compact ? '' : s;
            String? tip(String s, [String? more]) =>
                compact ? (more == null ? s : '$s · $more') : more;
            return _toolbar(context, prompt, words, series, label, tip);
          },
        ),
        Expanded(
          child: ColoredBox(
            color: PennaColors.editorBg,
            child: SmoothScroller(
              builder: (controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.all(14),
                children: [
                  BodyCard(
                    // 换页就是换了一份成稿:各段展开没展开、光标在哪都重新算。
                    key: ValueKey(vm.pageIndex),
                    vm: vm,
                    zhOpen: _zhOpen,
                    onCopied: vm.recordPrompt,
                    onDiscuss: onDiscuss,
                    // 和顶栏的润色是同一套,只是范围先定在这一段上。
                    onPolish: vm.isPolishing
                        ? null
                        : (start, end) =>
                              _polish(context, section: (start, end)),
                    // 英文界面不要对照译文:几处翻译都不给。
                    onTranslateSelection: !_gloss
                        ? null
                        : () => _translate(context, selection: true),
                    onTranslate: !_gloss
                        ? null
                        : (section, text) async {
                            final problem = await vm.translateSection(
                              section,
                              text,
                            );
                            if (problem != null && context.mounted) {
                              showToast(context, problem, warn: true);
                            }
                          },
                  ),
                  if (vm.translation != null) ...[
                    const SizedBox(height: 10),
                    PopIn(
                      child: _TranslationCard(
                        text: vm.translation!,
                        engine: vm.translationBy,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 顶栏里「Diff 待合并」和两个计数至少各要这么宽才画得完整。
const _chipRoom = 100.0;
const _statsRoom = 190.0;

class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.more});

  /// 这一处后面还排着几处。
  final int more;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.lock,
      borderColor: PennaColors.lockBorder,
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        more == 0 ? tr('Diff 待合并') : tr('Diff 待合并 · 后面还有 {0} 处', [more]),
        overflow: TextOverflow.ellipsis,
        style: monoStyle.copyWith(fontSize: 11, color: PennaColors.lockText),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({required this.text, required this.engine});

  final String text;

  /// 译文出自哪个引擎。
  final String? engine;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.primaryBg,
      borderColor: PennaColors.primaryBorder,
      radius: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.translate, size: 13, color: PennaColors.primary),
              const SizedBox(width: 4),
              Text(
                engine == null ? tr('中文对照') : tr('中文对照 · {0}', [engine]),
                style: draftLabelStyle,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            contextMenuBuilder: pennaTextMenu,
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: PennaColors.slate700,
            ),
          ),
        ],
      ),
    );
  }
}
