import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_runner.dart';
import 'image_viewer.dart';

String _two(int n) => '$n'.padLeft(2, '0');

/// 今天的只写钟点,别的日子带上月日。
String _when(DateTime t) {
  final now = DateTime.now();
  final clock = '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return today ? clock : '${_two(t.month)}-${_two(t.day)} $clock';
}

/// 列表里显示的提示词:区域控制交的是多行的布局 JSON,取它的整体描述;
/// 别的把换行和连着的空白并成一个空格。
String _promptText(String prompt) {
  final text = prompt.trim();
  if (text.startsWith('{')) {
    try {
      final j = jsonDecode(text);
      final summary = j is Map ? j['summary'] : null;
      final caption = summary is Map ? summary['caption'] : null;
      if (caption is String && caption.trim().isNotEmpty) return caption.trim();
    } on FormatException {
      // 不是 JSON,照普通文字显示。
    }
  }
  return text.replaceAll(RegExp(r'\s+'), ' ');
}

String _took(Duration d) => d.inSeconds < 60
    ? tr('耗时 {0} 秒', [d.inSeconds])
    : tr('耗时 {0} 分 {1} 秒', [d.inMinutes, d.inSeconds % 60]);

/// 左侧栏里的出图队列:排着的、正在出的、出完的,新的在上;
/// 每单左边是缩略图(点开看大图),右边是时间、状态、耗时和提示词。
class ComfyQueuePanel extends StatelessWidget {
  const ComfyQueuePanel({super.key, required this.runner});

  final ComfyRunner runner;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: runner,
    builder: (context, _) {
      final jobs = runner.jobs;
      if (jobs.isEmpty) {
        return Center(
          child: Text(
            tr('还没有出过图'),
            style: TextStyle(fontSize: 12, color: PennaColors.slate400),
          ),
        );
      }
      final finished = jobs.any(
        (j) =>
            j.state != ComfyJobState.waiting &&
            j.state != ComfyJobState.running,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) =>
                  _JobTile(job: jobs[i], runner: runner),
            ),
          ),
          if (finished)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: PennaButton(
                label: tr('清空记录'),
                icon: Icons.delete_sweep_outlined,
                borderColor: PennaColors.border,
                onPressed: runner.clearFinished,
              ),
            ),
        ],
      );
    },
  );
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.runner});

  final ComfyJob job;
  final ComfyRunner runner;

  @override
  Widget build(BuildContext context) {
    final progress = runner.progress;
    final (label, color) = switch (job.state) {
      ComfyJobState.waiting => (tr('排队中'), PennaColors.slate500),
      ComfyJobState.running => (
        progress == null
            ? tr('出图中')
            : tr('出图中 · {0}%', [(progress * 100).round()]),
        PennaColors.primary,
      ),
      ComfyJobState.done => (tr('已完成'), PennaColors.slate500),
      ComfyJobState.failed => (tr('失败'), PennaColors.diffDelText),
      ComfyJobState.canceled => (tr('已撤掉'), PennaColors.slate400),
    };
    final took = job.took;
    final small = TextStyle(fontSize: 10.5, color: PennaColors.slate400);
    final active =
        job.state == ComfyJobState.waiting ||
        job.state == ComfyJobState.running;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: PennaColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PennaColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumb(context),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_when(job.queued), style: small),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (took != null) Text(_took(took), style: small),
                Tooltip(
                  message: job.error ?? _promptText(job.prompt),
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    job.error ?? _promptText(job.prompt),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: job.error == null
                          ? PennaColors.slate500
                          : PennaColors.diffDelText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (active)
            Tooltip(
              message: job.state == ComfyJobState.running ? tr('停止') : tr('撤掉'),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => runner.cancel(job.id),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: PennaColors.slate500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 出完的是第一张图的缩略图,点开看大图;别的是一个图标占位。
  Widget _thumb(BuildContext context) {
    const size = 46.0;
    final path = job.images.firstOrNull;
    final box = BoxDecoration(
      color: PennaColors.slate100,
      borderRadius: BorderRadius.circular(5),
    );
    if (path == null) {
      return Container(
        width: size,
        height: size,
        decoration: box,
        child: Icon(
          job.state == ComfyJobState.failed
              ? Icons.error_outline
              : Icons.image_outlined,
          size: 18,
          color: PennaColors.slate400,
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showImageViewer(context, comfyImageAttachment(path)),
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: box,
          child: Image.file(
            File(path),
            cacheWidth: 112,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              Icons.broken_image_outlined,
              size: 18,
              color: PennaColors.slate400,
            ),
          ),
        ),
      ),
    );
  }
}
