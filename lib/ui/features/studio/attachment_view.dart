import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'image_viewer.dart';

const _thumbSize = 18.0;
const _previewHeight = 96.0;

/// 一个附件标签:图片带小缩略图,文件带图标;给了 [onRemove] 就带一个叉。
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({super.key, required this.attachment, this.onRemove});

  final Attachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final bytes = attachment.bytes;
    return PennaCard(
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bytes == null)
            Icon(
              Icons.description_outlined,
              size: 14,
              color: PennaColors.slate500,
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.memory(
                bytes,
                width: _thumbSize,
                height: _thumbSize,
                cacheWidth: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  size: 14,
                  color: PennaColors.slate500,
                ),
              ),
            ),
          const SizedBox(width: 5),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: PennaColors.slate700,
                ),
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close, size: 12, color: PennaColors.slate500),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 已发出的消息下面的附件:图片显示预览(点了看大图),文件显示标签。
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.attachments, this.onReuse});

  final List<Attachment> attachments;

  /// 大图里点「附到输入框」时把这张图交回去;为 null 时没有这个按钮。
  final ValueChanged<Attachment>? onReuse;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final a in attachments)
          if (a.bytes == null)
            AttachmentChip(attachment: a)
          else
            Tooltip(
              message: a.name,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => showImageViewer(context, a, onReuse: onReuse),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      a.bytes!,
                      height: _previewHeight,
                      cacheHeight: 288,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => AttachmentChip(attachment: a),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
