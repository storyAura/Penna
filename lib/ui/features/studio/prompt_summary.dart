part of 'prompt_pane.dart';

// 工作区下半区:成稿汇总、最终提示词和历史提示词。

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.vm});

  final StudioViewModel vm;

  @override
  Widget build(BuildContext context) {
    final prompt = vm.finalPrompt;
    return Column(
      children: [
        const Divider(height: 1),
        // 页签留着:以后这里还会加别的分页。
        PennaBar(
          children: [
            Tooltip(
              message: tr('放大查看'),
              child: _Tab(
                icon: Icons.inventory_2_outlined,
                label: tr('成稿汇总'),
                selected: true,
                onTap: () => _showSummary(context, vm),
              ),
            ),
          ],
        ),
        Expanded(
          child: ColoredBox(
            color: PennaColors.editorBg,
            child: prompt.isEmpty && vm.tags.isEmpty && vm.promptLog.isEmpty
                ? Center(
                    child: Text(
                      tr('暂无内容'),
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate400,
                      ),
                    ),
                  )
                : SmoothScroller(
                    builder: (controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.all(14),
                      children: [
                        if (vm.tags.isNotEmpty) ...[
                          _CopyCard(
                            icon: Icons.sell_outlined,
                            iconColor: PennaColors.amber,
                            title: tr('Danbooru 风格 Tag 汇总'),
                            text: vm.tags,
                            toast: tr('已复制全部 Tag'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (prompt.isNotEmpty)
                          _CopyCard(
                            icon: Icons.verified_outlined,
                            iconColor: PennaColors.accent,
                            title: vm.pages.length > 1
                                ? tr(
                                    '最终提示词 · {0}'
                                    ' · 第 {1} 页',
                                    [
                                      vm.seriesName(vm.series),
                                      vm.pageNumber(vm.pageIndex),
                                    ],
                                  )
                                : tr('最终提示词'),
                            text: prompt,
                            toast: tr('已复制'),
                            onCopied: vm.recordPrompt,
                          ),
                        if (vm.promptLog.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(tr('历史提示词'), style: draftLabelStyle),
                          for (final record in vm.promptLog) ...[
                            const SizedBox(height: 8),
                            _HistoryCard(
                              key: ObjectKey(record),
                              vm: vm,
                              record: record,
                            ),
                          ],
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

/// 下半区顶上的一个页签。
class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PennaColors.primary : PennaColors.slate500;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.base,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? PennaColors.card : PennaColors.slate50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? PennaColors.border : PennaColors.slate50,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? PennaColors.text : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史提示词收起时最多显示几行。
const _historyLines = 3;

/// 历史提示词里的一条:当时的成稿,可以放回工作区或复制;长的可以展开看全。
class _HistoryCard extends StatefulWidget {
  const _HistoryCard({super.key, required this.vm, required this.record});

  final StudioViewModel vm;
  final PromptRecord record;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _open = false;

  StudioViewModel get vm => widget.vm;
  PromptRecord get record => widget.record;

  @override
  Widget build(BuildContext context) {
    // 复制和预览都用干净的提示词:标注和中文对照不带。
    final clean = stripSectionLabels(record.text);
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shortTime(record.time),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
              ),
              PennaButton(
                label: tr('放回成稿'),
                icon: Icons.keyboard_double_arrow_up,
                onPressed: () {
                  final problem = vm.restorePrompt(record);
                  if (problem != null) showToast(context, problem, warn: true);
                },
              ),
              PennaButton(
                label: tr('复制这条'),
                icon: Icons.content_copy,
                onPressed: () => copyWithToast(context, clean, tr('已复制')),
              ),
              IconButton(
                tooltip: tr('删除这条'),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.close),
                onPressed: () => vm.deletePrompt(record),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, box) {
              final style = monoStyle.copyWith(fontSize: 11.5);
              // 收起时放得下就不用「展开」按钮。
              final long = (TextPainter(
                text: TextSpan(text: clean, style: style),
                maxLines: _historyLines,
                textDirection: TextDirection.ltr,
              )..layout(maxWidth: box.maxWidth)).didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: Motion.base,
                    curve: Motion.swift,
                    alignment: Alignment.topLeft,
                    child: Text(
                      clean,
                      maxLines: _open ? null : _historyLines,
                      overflow: _open ? null : TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  if (long)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PennaButton(
                        label: _open ? tr('收起') : tr('展开'),
                        icon: _open ? Icons.expand_less : Icons.expand_more,
                        background: Colors.transparent,
                        foreground: PennaColors.slate500,
                        onPressed: () => setState(() => _open = !_open),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CopyCard extends StatelessWidget {
  const _CopyCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.text,
    required this.toast,
    this.onCopied,
    this.fontSize = 11.5,
  });

  /// 正文字号:放大查看的窗口里大一号。
  final double fontSize;

  /// 点了复制之后顺带做的事(记进历史提示词)。
  final VoidCallback? onCopied;

  final IconData icon;
  final Color iconColor;
  final String title;
  final String text;
  final String toast;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PennaButton(
                label: tr('一键复制'),
                icon: Icons.content_copy,
                background: PennaColors.primaryBg,
                foreground: PennaColors.primary,
                borderColor: PennaColors.primaryBorder,
                onPressed: () {
                  onCopied?.call();
                  copyWithToast(context, text, toast);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          PennaCard(
            color: PennaColors.slate50,
            radius: 4,
            child: SelectableText(
              contextMenuBuilder: pennaTextMenu,
              text,
              style: monoStyle.copyWith(fontSize: fontSize),
            ),
          ),
        ],
      ),
    );
  }
}

/// 点「成稿汇总」弹出的大窗口:眼前这页完整的最终提示词(有 Tag 时连 Tag 汇总),
/// 跟着成稿实时变。
Future<void> _showSummary(BuildContext context, StudioViewModel vm) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final screen = MediaQuery.sizeOf(context);
        return Dialog(
          backgroundColor: PennaColors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: (screen.width * 0.8).clamp(360, 1000),
            height: screen.height * 0.8,
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 8, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: PennaColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('成稿汇总'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('关闭'),
                          iconSize: 18,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: vm.finalPrompt.isEmpty && vm.tags.isEmpty
                        ? Center(
                            child: Text(
                              tr('暂无内容'),
                              style: TextStyle(
                                fontSize: 12,
                                color: PennaColors.slate400,
                              ),
                            ),
                          )
                        : SmoothScroller(
                            builder: (controller) => ListView(
                              controller: controller,
                              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                              children: [
                                if (vm.tags.isNotEmpty) ...[
                                  _CopyCard(
                                    icon: Icons.sell_outlined,
                                    iconColor: PennaColors.amber,
                                    title: tr('Danbooru 风格 Tag 汇总'),
                                    text: vm.tags,
                                    toast: tr('已复制全部 Tag'),
                                    fontSize: 13,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (vm.finalPrompt.isNotEmpty)
                                  _CopyCard(
                                    icon: Icons.verified_outlined,
                                    iconColor: PennaColors.accent,
                                    title: vm.pages.length > 1
                                        ? tr('最终提示词 · {0} · 第 {1} 页', [
                                            vm.seriesName(vm.series),
                                            vm.pageNumber(vm.pageIndex),
                                          ])
                                        : tr('最终提示词'),
                                    text: vm.finalPrompt,
                                    toast: tr('已复制'),
                                    onCopied: vm.recordPrompt,
                                    fontSize: 13,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
