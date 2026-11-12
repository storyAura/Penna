import 'package:flutter/material.dart';

import '../../core/harness/llm_log.dart';
import '../../l10n/l10n.dart';
import 'theme.dart';
import 'widgets.dart';

// 「模型日志」:左侧栏设置上面的按钮和点开的窗口(2026-11-13 用户要求)。

/// 每种事件的名字和颜色。
(String, Color) _look(LlmEventKind kind) => switch (kind) {
  LlmEventKind.failover => (tr('换下一个'), PennaColors.amber),
  LlmEventKind.error => (tr('出错'), PennaColors.diffDelText),
  LlmEventKind.cut => (tr('截断'), PennaColors.amber),
  LlmEventKind.stopped => (tr('停止'), PennaColors.slate500),
  LlmEventKind.search => (tr('联网搜索'), PennaColors.primary),
  LlmEventKind.retry => (tr('重试'), PennaColors.slate500),
  LlmEventKind.tier => (tr('档位'), PennaColors.primary),
};

String _clock(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 打开模型日志;打开就算看过了,按钮上的数字清掉。
Future<void> showLlmLog(BuildContext context) {
  llmLog.markSeen();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(tr('模型日志'), style: const TextStyle(fontSize: 16)),
          ),
          TextButton(onPressed: llmLog.clear, child: Text(tr('清空'))),
          IconButton(
            tooltip: tr('关闭'),
            iconSize: 18,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 480,
        child: ListenableBuilder(
          listenable: llmLog,
          builder: (context, _) {
            final events = llmLog.events;
            if (events.isEmpty) {
              return Center(
                child: Text(
                  tr('暂无记录'),
                  style: TextStyle(color: PennaColors.slate500),
                ),
              );
            }
            return ListView.separated(
              itemCount: events.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: PennaColors.border),
              itemBuilder: (_, i) => _EventRow(events[i]),
            );
          },
        ),
      ),
    ),
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.event);

  final LlmEvent event;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _look(event.kind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              _clock(event.time),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
          ),
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              event.model.isEmpty
                  ? event.message
                  : '${event.model}:${event.message}',
              contextMenuBuilder: pennaTextMenu,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 左侧栏设置上面那个按钮:有没看过的问题时右上角标个数。
class LlmLogButton extends StatelessWidget {
  const LlmLogButton({super.key, required this.button});

  /// 侧栏统一样子的按钮(由侧栏传进来,点了打开日志)。
  final Widget Function(VoidCallback onTap) button;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: llmLog,
    builder: (context, _) {
      final unseen = llmLog.unseen;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          button(() => showLlmLog(context)),
          if (unseen > 0)
            Positioned(
              right: -4,
              top: -4,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PennaColors.diffDelText,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unseen > 99 ? '99+' : '$unseen',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
