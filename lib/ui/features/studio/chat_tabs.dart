import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/scroll_strip.dart';

/// 对话顶栏下面的一行标签:一个标签一场对话(`vm.chatTabs`)。
/// 点一下换过去;叉掉只是关标签,对话还在历史里;最后的加号开一场新的。
/// 标签多了用两头的箭头翻(和快捷操作同一个 [ScrollStrip]),鼠标滚轮也能滚。
// ponytail: 同一时间只有眼前这场在生成,生成中换不了标签;
// 要几场同时生成,得让每场对话各有自己的回复流,而不是共用 vm 里那一个。
class ChatTabs extends StatefulWidget {
  const ChatTabs({super.key, required this.vm});

  final StudioViewModel vm;

  @override
  State<ChatTabs> createState() => _ChatTabsState();
}

class _ChatTabsState extends State<ChatTabs> {
  /// 眼前这场对话的标签;换了对话就把它滚进视野。
  final _current = GlobalKey();
  late String _shown = widget.vm.chatId;

  StudioViewModel get vm => widget.vm;

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _current.currentContext;
      if (at != null && at.mounted) {
        Scrollable.ensureVisible(at, alignment: 0.5, duration: Motion.base);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chats = vm.chatTabs;
    final busy = vm.isStreaming;
    if (_shown != vm.chatId) {
      _shown = vm.chatId;
      _reveal();
    }
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: PennaColors.slate50,
        border: Border(bottom: BorderSide(color: PennaColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ScrollStrip(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final chat in chats)
                  _Tab(
                    key: chat.id == vm.chatId ? _current : null,
                    title: chatTitle(chat.messages),
                    selected: chat.id == vm.chatId,
                    onTap: busy || chat.id == vm.chatId
                        ? null
                        : () => vm.openChat(chat.id),
                    onClose: () {
                      if (!vm.closeChat(chat.id)) {
                        showToast(context, tr('正在生成,请先停止当前回复'), warn: true);
                      }
                    },
                  ),
              ],
            ),
          ),
          Tooltip(
            message: tr('新对话'),
            child: InkWell(
              onTap: busy || vm.messages.isEmpty ? null : vm.newChat,
              child: SizedBox(
                width: 34,
                height: 40,
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: busy || vm.messages.isEmpty
                      ? PennaColors.slate400
                      : PennaColors.slate700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.base,
      height: 26,
      padding: const EdgeInsets.only(left: 9, right: 3),
      decoration: BoxDecoration(
        color: selected ? PennaColors.card : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? PennaColors.primaryBorder : PennaColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? PennaColors.primary
                        : PennaColors.slate500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Tooltip(
            message: tr('关掉这个标签(历史里还在)'),
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 12, color: PennaColors.slate400),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
