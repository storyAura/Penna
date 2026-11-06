part of 'prompt_pane.dart';

// 最终提示词卡片上的「出图」,和卡片下面这次出过的图。

const _thumbHeight = 84.0;

/// 「出图」按钮:把最终提示词交给 ComfyUI。出图时变成「停止」。
class _GenerateButton extends StatelessWidget {
  const _GenerateButton({required this.vm});

  final StudioViewModel vm;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm.comfy,
    builder: (context, _) => vm.comfy.running
        ? PennaButton(
            label: tr('停止'),
            icon: Icons.stop_circle_outlined,
            borderColor: PennaColors.border,
            onPressed: vm.comfy.stop,
          )
        : PennaButton(
            label: tr('出图'),
            icon: Icons.brush_outlined,
            tooltip: tr('用 ComfyUI 出图'),
            borderColor: PennaColors.border,
            onPressed: () => vm.comfy.generate(vm.finalPrompt),
          ),
  );
}

/// 出图的进度、错误和出过的图(新的在前,点开看大图)。
class _ComfyStrip extends StatelessWidget {
  const _ComfyStrip({required this.runner});

  final ComfyRunner runner;

  Attachment _attachment(String path) {
    final name = File(path).uri.pathSegments.last;
    final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    return Attachment.saved(
      name: name,
      file: path,
      mime: imageMimes[ext] ?? 'image/png',
    );
  }

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
            if (runner.running)
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('出图中'),
                    style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                  ),
                ],
              ),
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
      onTap: () => showImageViewer(context, _attachment(path)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
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
