import 'package:flutter/material.dart';

import '../../core/harness/llm_log.dart';
import '../../core/harness/thinking.dart';
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
  LlmEventKind.replyTool => (tr('工具回覆'), PennaColors.primary),
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
      content: SizedBox(width: 720, height: 520, child: const _LogBody()),
    ),
  );
}

/// 日志窗口的正文:上面两个标签,「事件」是出了什么问题,「请求」是每次发了什么、回了什么。
class _LogBody extends StatefulWidget {
  const _LogBody();

  @override
  State<_LogBody> createState() => _LogBodyState();
}

class _LogBodyState extends State<_LogBody> {
  var _calls = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          PennaChip(
            label: tr('事件'),
            selected: !_calls,
            onTap: () => setState(() => _calls = false),
          ),
          const SizedBox(width: 6),
          PennaChip(
            label: tr('请求'),
            selected: _calls,
            onTap: () => setState(() => _calls = true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _calls ? tr('最近 40 次,只留在内存里,关掉软件就没了') : '',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListenableBuilder(
          listenable: llmLog,
          builder: (context, _) {
            final count = _calls ? llmLog.calls.length : llmLog.events.length;
            if (count == 0) {
              return Center(
                child: Text(
                  tr('暂无记录'),
                  style: TextStyle(color: PennaColors.slate500),
                ),
              );
            }
            return ListView.separated(
              itemCount: count,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: PennaColors.border),
              itemBuilder: (_, i) => _calls
                  ? _CallRow(llmLog.calls[i])
                  : _EventRow(llmLog.events[i]),
            );
          },
        ),
      ),
    ],
  );
}

/// 一次请求的状态:还在等、出错、说完了。
(String, Color) _callLook(LlmCall call) => call.took == null
    ? (tr('进行中'), PennaColors.primary)
    : call.error != null
    ? (tr('出错'), PennaColors.diffDelText)
    : (tr('完成'), PennaColors.slate500);

class _CallRow extends StatelessWidget {
  const _CallRow(this.call);

  final LlmCall call;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _callLook(call);
    final took = call.took;
    return InkWell(
      onTap: () => showLlmCall(context, call),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                _clock(call.time),
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
              child: Text(
                call.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            Text(
              [
                tr('发 {0} 条', [call.messages.length]),
                tr('回 {0} 字', [call.output.length]),
                if (took != null) tr('{0} 秒', [took.inSeconds]),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: PennaColors.slate400),
          ],
        ),
      ),
    );
  }
}

/// 一次请求的细节:发出去的每条消息、模型的思考、回的正文、出错的原因。
Future<void> showLlmCall(BuildContext context, LlmCall call) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${_clock(call.time)} · ${call.name}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: tr('关闭'),
            iconSize: 18,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 600,
        child: ListenableBuilder(
          listenable: llmLog,
          builder: (context, _) {
            final said = splitThinking(
              '${call.output}',
              done: call.took != null,
            );
            return ListView(
              children: [
                _CallPart(
                  tr('发给模型的'),
                  call.images == 0
                      ? tr('{0} 条消息', [call.messages.length])
                      : tr('{0} 条消息 · {1} 张图', [
                          call.messages.length,
                          call.images,
                        ]),
                ),
                for (final m in call.messages)
                  _CallText(m['role'] ?? '', m['content'] ?? ''),
                if (said.thinking.isNotEmpty) ...[
                  _CallPart(tr('模型的思考'), ''),
                  _CallText('', said.thinking),
                ],
                _CallPart(tr('模型回的'), call.took == null ? tr('还在写') : ''),
                _CallText('', said.rest.isEmpty ? tr('(没有内容)') : said.rest),
                if (call.error case final error?) ...[
                  _CallPart(tr('出错'), ''),
                  _CallText('', error),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// 细节里的小标题。
class _CallPart extends StatelessWidget {
  const _CallPart(this.title, this.note);

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        Text(note, style: TextStyle(fontSize: 12, color: PennaColors.slate500)),
      ],
    ),
  );
}

/// 细节里的一段原文:谁说的([role],可以没有)和能选能复制的文字。
class _CallText extends StatelessWidget {
  const _CallText(this.role, this.text);

  final String role;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: PennaCard(
      color: PennaColors.slate50,
      radius: 8,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (role.isNotEmpty) ...[
            Text(
              role,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: PennaColors.primary,
              ),
            ),
            const SizedBox(height: 4),
          ],
          SelectableText(
            text,
            contextMenuBuilder: pennaTextMenu,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
        ],
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
