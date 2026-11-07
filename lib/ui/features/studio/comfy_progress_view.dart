import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_runner.dart';

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
            PennaButton(
              label: tr('停止'),
              icon: Icons.stop_circle_outlined,
              foreground: PennaColors.diffDelText,
              borderColor: PennaColors.border,
              onPressed: runner.stop,
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

/// 排在队列里还没轮到的那一单:前面还有几张,右边可以撤掉。
class ComfyQueuedRow extends StatelessWidget {
  const ComfyQueuedRow({super.key, required this.runner, required this.owner});

  final ComfyRunner runner;
  final Object owner;

  @override
  Widget build(BuildContext context) {
    final job = runner.jobs
        .where((j) => j.owner == owner && j.state == ComfyJobState.waiting)
        .firstOrNull;
    if (job == null) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.schedule, size: 14, color: PennaColors.slate500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tr('已加入出图队列 · 前面还有 {0} 张', [runner.aheadOf(owner) ?? 0]),
            style: TextStyle(fontSize: 12, color: PennaColors.slate500),
          ),
        ),
        PennaButton(
          label: tr('撤掉'),
          icon: Icons.close,
          borderColor: PennaColors.border,
          onPressed: () => runner.cancel(job.id),
        ),
      ],
    );
  }
}
