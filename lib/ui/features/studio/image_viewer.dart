import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../core/harness/attachment.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// 点对话里的图片看大图:铺满窗口,滚轮缩放、拖着看;能复制到剪贴板,
/// 给了 [onReuse] 时还能直接附到输入框再发一次。点空白处或 Esc 关掉。
Future<void> showImageViewer(
  BuildContext context,
  Attachment image, {
  ValueChanged<Attachment>? onReuse,
}) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: tr('关闭'),
  barrierColor: Colors.black.withValues(alpha: 0.82),
  transitionDuration: Motion.of(context, Motion.base),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
    child: child,
  ),
  pageBuilder: (context, _, _) => _Viewer(image: image, onReuse: onReuse),
);

/// 把图片放进剪贴板(别的软件里能贴)。成功返回 null,否则是给用户看的原因。
Future<String?> copyImage(Attachment image) async {
  // ponytail: pasteboard 只在 Windows 上写得了图;Linux 上提示复制不了。
  if (!Platform.isWindows) return tr('这个系统上复制不了图片');
  try {
    final png = await toPng(image);
    if (png == null) return tr('读不了这张图');
    await Pasteboard.writeImage(png);
    return null;
  } on PlatformException catch (e) {
    return tr('复制失败:{0}', [e.message ?? e.code]);
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({required this.image, this.onReuse});

  final Attachment image;
  final ValueChanged<Attachment>? onReuse;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  /// 复制完在按钮上说一声:弹窗盖着,底下的提示条看不见。
  String? _note;

  void _close() => Navigator.of(context).pop();

  Future<void> _copy() async {
    final problem = await copyImage(widget.image);
    if (mounted) setState(() => _note = problem ?? tr('已复制'));
  }

  void _reuse() {
    widget.onReuse!(widget.image);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.image.bytes;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // 点图片以外的地方关掉;图片自己接住点击,不往下传。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 8,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: bytes == null || bytes.isEmpty
                          ? _broken()
                          : Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => _broken(),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(top: 14, left: 16, right: 16, child: _toolbar()),
          ],
        ),
      ),
    );
  }

  Widget _broken() =>
      Icon(Icons.broken_image_outlined, size: 48, color: PennaColors.slate400);

  Widget _toolbar() => Material(
    type: MaterialType.transparency,
    child: Row(
      children: [
        Expanded(
          child: Text(
            widget.image.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        if (_note != null) ...[
          Text(
            _note!,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(width: 10),
        ],
        PennaButton(
          label: tr('复制图片'),
          icon: Icons.content_copy,
          onPressed: _copy,
        ),
        if (widget.onReuse != null) ...[
          const SizedBox(width: 6),
          PennaButton(
            label: tr('附到输入框'),
            icon: Icons.attach_file,
            onPressed: _reuse,
          ),
        ],
        const SizedBox(width: 6),
        IconButton(
          tooltip: tr('关闭'),
          iconSize: 18,
          color: Colors.white,
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ],
    ),
  );
}
