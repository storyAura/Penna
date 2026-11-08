part of 'prompt_pane.dart';

// 最终提示词卡片上的「出图」「系列出图」,和下半区「出图」页签里这次出过的图。

const _thumbHeight = 220.0;

/// 系列出图一次超过这么多张要先问一句。
const _seriesConfirmAt = 60;

/// 「出图」按钮:把最终提示词交给 ComfyUI。正在出图时也能点,排进队列。
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({required this.vm, required this.onStart});

  final StudioViewModel vm;

  /// 点了之后顺带做的事(换到「出图」页签)。
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => PennaButton(
    label: tr('出图'),
    icon: Icons.brush_outlined,
    tooltip: tr('用 ComfyUI 出图'),
    // 和旁边的「一键复制」分开:实心主题色,深色模式下也看得清。
    background: PennaColors.primary,
    foreground: Colors.white,
    onPressed: () {
      onStart();
      unawaited(vm.comfy.generate(vm.finalPrompt));
    },
  );
}

/// 「系列出图」:眼前这个系列从第 1 页起一页一张排进队列;超过 [_seriesConfirmAt] 张先确认。
class _SeriesGenerateButton extends StatelessWidget {
  const _SeriesGenerateButton({required this.vm, required this.onStart});

  final StudioViewModel vm;
  final VoidCallback onStart;

  Future<void> _run(BuildContext context) async {
    final prompts = vm.finalPromptsOf(vm.series);
    if (prompts.isEmpty) {
      return showToast(context, tr('这个系列还是空的'), warn: true);
    }
    if (prompts.length > _seriesConfirmAt &&
        !await confirmDelete(
          context,
          tr('系列出图'),
          tr('这个系列有 {0} 页,要全部排进出图队列吗?', [prompts.length]),
          action: tr('全部出图'),
        )) {
      return;
    }
    onStart();
    // 按页的先后排:队列先进先出,第 1 页最先出。
    for (final p in prompts) {
      unawaited(vm.comfy.generate(p));
    }
    if (context.mounted) {
      showToast(context, tr('已排进出图队列 {0} 张', [prompts.length]));
    }
  }

  @override
  Widget build(BuildContext context) => PennaButton(
    label: tr('系列出图'),
    icon: Icons.burst_mode_outlined,
    tooltip: tr('这个系列从第 1 页起按顺序出图'),
    borderColor: PennaColors.primaryBorder,
    foreground: PennaColors.primary,
    onPressed: () => _run(context),
  );
}

/// 「出图」页签:进度、错误和这次出过的图(新的在前,点开看大图)。
class _ComfyStrip extends StatelessWidget {
  const _ComfyStrip({required this.runner});

  final ComfyRunner runner;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runner,
    builder: (context, _) {
      final error = runner.error;
      final images = runner.images;
      if (!runner.running &&
          runner.waiting == 0 &&
          error == null &&
          images.isEmpty) {
        return Center(
          child: Text(
            tr('还没有出过图'),
            style: TextStyle(fontSize: 12, color: PennaColors.slate400),
          ),
        );
      }
      return SmoothScroller(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(14),
          children: [
            if (runner.running) ComfyProgressRow(runner: runner),
            if (runner.waiting > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('队列里还有 {0} 张', [runner.waiting]),
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
              ),
            if (error != null)
              SelectableText(
                error,
                contextMenuBuilder: pennaTextMenu,
                style: TextStyle(fontSize: 12, color: PennaColors.diffDelText),
              ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final g in images) _thumb(context, g.path)],
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _thumb(BuildContext context, String path) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () => showImageViewer(context, comfyImageAttachment(path)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          comfyImageAttachment(path).bytes!,
          height: _thumbHeight,
          cacheHeight: (_thumbHeight * 2).round(),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => SizedBox.square(
            dimension: _thumbHeight,
            child: Icon(
              Icons.broken_image_outlined,
              color: PennaColors.slate400,
            ),
          ),
        ),
      ),
    ),
  );
}
