part of 'prompt_pane.dart';

// 最终提示词卡片上的「出图」,和卡片下面这次出过的图。

const _thumbHeight = 84.0;

/// 「出图」按钮:把最终提示词交给 ComfyUI。出图时变灰,停止在下面的进度条上。
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({required this.vm});

  final StudioViewModel vm;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm.comfy,
    builder: (context, _) => PennaButton(
      label: tr('出图'),
      icon: Icons.brush_outlined,
      tooltip: tr('用 ComfyUI 出图'),
      // 和旁边的「一键复制」分开:实心主题色,深色模式下也看得清。
      background: PennaColors.primary,
      foreground: Colors.white,
      onPressed: vm.comfy.running
          ? null
          : () => vm.comfy.generate(vm.finalPrompt),
    ),
  );
}

/// 出图的进度、错误和出过的图(新的在前,点开看大图)。
class _ComfyStrip extends StatelessWidget {
  const _ComfyStrip({required this.runner});

  final ComfyRunner runner;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runner,
    builder: (context, _) {
      final error = runner.error;
      final images = runner.images;
      if (!runner.running && error == null && images.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (runner.running) ComfyProgressRow(runner: runner),
            if (error != null)
              SelectableText(
                error,
                contextMenuBuilder: pennaTextMenu,
                style: TextStyle(fontSize: 12, color: PennaColors.diffDelText),
              ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: _thumbHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => _thumb(context, images[i].path),
                ),
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
