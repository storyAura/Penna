import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import 'comfy_runner.dart';

/// 出的图当成图片附件显示(点开看大图、复制),文件读不了时显示空的。
Attachment comfyImageAttachment(String path) {
  final name = File(path).uri.pathSegments.last;
  final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  return Attachment.saved(
    name: name,
    file: path,
    mime: imageMimes[ext] ?? 'image/png',
  );
}

/// 出图进度:一行字(排队中 / 出图中 · 40%)加一条进度条,右边可以停止。
class ComfyProgressRow extends StatelessWidget {
  const ComfyProgressRow({super.key, required this.runner});

  final ComfyRunner runner;

  @override
  Widget build(BuildContext context) {
    final p = runner.progress;
    final style = TextStyle(fontSize: 12, color: PennaColors.slate500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.brush_outlined, size: 14, color: PennaColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                p == null ? tr('排队中') : tr('出图中 · {0}%', [(p * 100).round()]),
                style: style,
              ),
            ),
            InkWell(
              onTap: runner.stop,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(tr('停止'), style: style),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: p,
            minHeight: 4,
            backgroundColor: PennaColors.slate100,
            color: PennaColors.primary,
          ),
        ),
      ],
    );
  }
}
