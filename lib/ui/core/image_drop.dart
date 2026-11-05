import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../core/harness/attachment.dart';
import 'theme.dart';
import 'widgets.dart';
import '../../l10n/l10n.dart';
import 'motion.dart';

/// 一张图的位置:点一下选图或直接拖进来;有图时显示它,右上角可以换图、移除。
class ImageDrop extends StatefulWidget {
  const ImageDrop({
    super.key,
    required this.image,
    required this.onChanged,
    this.hint,
    this.compress = false,
  });

  final Attachment? image;

  /// 大图读进来时缩小、转成 WebP(软件设置里的「压缩大图」)。
  final bool compress;

  /// 没有图时中间的那句话;不给就是「点击或拖入参考图」。
  final String? hint;

  /// 换了图(移除时是 null)。
  final ValueChanged<Attachment?> onChanged;

  @override
  State<ImageDrop> createState() => _ImageDropState();
}

class _ImageDropState extends State<ImageDrop> {
  /// 有文件拖在上面:亮起来告诉用户可以松手。
  bool _over = false;

  void _hover(bool over) {
    if (over != _over) setState(() => _over = over);
  }

  Future<void> _use(BuildContext context, String path) async {
    try {
      final picked = await readAttachment(
        File(path),
        compress: widget.compress,
      );
      if (!picked.isImage) throw AttachmentException(tr('这不是图片'));
      widget.onChanged(picked);
      if (picked.compressed && context.mounted) {
        showToast(context, tr('大图已压缩为 WebP,可在软件设置里关闭'));
      }
    } on AttachmentException catch (e) {
      if (context.mounted) showToast(context, e.message, warn: true);
    }
  }

  /// 鼠标在框上、又没有输入框在打字时,框拿到焦点,Ctrl+V 才归它。
  final _focus = FocusNode(debugLabel: 'ImageDrop');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _grabFocus() {
    final typing = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (typing == null) _focus.requestFocus();
  }

  /// 剪贴板里是文件(资源管理器里复制的)就读第一个,是图(截图、网页上复制的)就转成附件。
  Future<void> _paste(BuildContext context) async {
    _focus.requestFocus();
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        if (context.mounted) await _use(context, files.first);
        return;
      }
      final raw = await Pasteboard.image;
      final picked = raw == null || raw.length > maxPastedBytes
          ? null
          : await pastedImage(raw, compress: widget.compress);
      if (!context.mounted) return;
      if (picked == null) {
        return showToast(context, tr('剪贴板里没有图片'), warn: true);
      }
      widget.onChanged(picked);
    } on Object {
      if (context.mounted) showToast(context, tr('读不了这张图'), warn: true);
    }
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('图片'), extensions: imageMimes.keys.toList()),
      ],
    );
    if (picked != null && context.mounted) await _use(context, picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    final drop = DropTarget(
      onDragEntered: (_) => _hover(true),
      onDragExited: (_) => _hover(false),
      onDragDone: (d) {
        _hover(false);
        if (d.files.isNotEmpty) _use(context, d.files.first.path);
      },
      child: Stack(
        // 外面给多大就多大,和没加这层时一样。
        fit: StackFit.passthrough,
        children: [
          image == null
              ? _EmptyImage(
                  hint: widget.hint ?? tr('点击或拖入参考图'),
                  onTap: () => _pick(context),
                  onPaste: () => _paste(context),
                )
              : _ImageBox(
                  image: image,
                  onReplace: () => _pick(context),
                  onClear: () => widget.onChanged(null),
                ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _over ? 1 : 0,
                duration: Motion.snap,
                child: const _DropHint(),
              ),
            ),
          ),
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) => _grabFocus(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
              _paste(context),
        },
        child: Focus(focusNode: _focus, child: drop),
      ),
    );
  }
}

/// 拖着文件经过时盖在上面的一层:蓝框、浅蓝底、「松开放入图片」。
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PennaColors.primaryBg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PennaColors.primary, width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.file_download_outlined,
              size: 30,
              color: PennaColors.primary,
            ),
            SizedBox(height: 6),
            Text(
              tr('松开放入图片'),
              style: TextStyle(fontSize: 13, color: PennaColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyImage extends StatelessWidget {
  const _EmptyImage({
    required this.hint,
    required this.onTap,
    required this.onPaste,
  });

  final String hint;
  final VoidCallback onTap;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: PennaCard(
          color: PennaColors.slate50,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 26,
                  color: PennaColors.slate400,
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
                const SizedBox(height: 12),
                PennaButton(
                  label: tr('从剪贴板粘贴'),
                  icon: Icons.content_paste,
                  borderColor: PennaColors.border,
                  onPressed: onPaste,
                ),
                const SizedBox(height: 6),
                Text(
                  tr('或按 Ctrl+V'),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({
    required this.image,
    required this.onReplace,
    required this.onClear,
  });

  final Attachment image;
  final VoidCallback onReplace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate50,
      padding: const EdgeInsets.all(6),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.memory(
              image.bytes!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: PennaColors.slate400,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Row(
              children: [
                PennaButton(
                  label: tr('换图'),
                  icon: Icons.swap_horiz,
                  borderColor: PennaColors.border,
                  onPressed: onReplace,
                ),
                const SizedBox(width: 4),
                PennaButton(
                  label: tr('移除'),
                  icon: Icons.close,
                  borderColor: PennaColors.border,
                  onPressed: onClear,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
