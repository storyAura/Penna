import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_panel.dart';
import 'studio_view_model.dart';

const _stripWidth = 34.0;
const _panelWidth = 300.0;

/// 多久测一次 ComfyUI 的连接。
const _pollEvery = Duration(seconds: 20);

/// 面板底色的不透明度(后面的对话透出来一点,再模糊掉)。
const _panelOpacity = 0.8;

enum _Panel { comfy, history }

/// 窗口最右边的侧栏(工作台和区域控制都有):一列图标,点开的面板半透明地盖在对话栏上。
/// ComfyUI(连接、工作流、LoRA)、历史对话、穿甲弹开关。
class RightBar extends StatefulWidget {
  const RightBar({
    super.key,
    required this.vm,
    required this.runner,
    required this.config,
  });

  /// 这一页的对话(历史对话是它的)。
  final StudioViewModel vm;
  final ComfyRunner runner;
  final ConfigService config;

  /// 收起时占多宽;外面排版要给它留出这一条。
  static const closedWidth = _stripWidth;

  @override
  State<RightBar> createState() => _RightBarState();
}

class _RightBarState extends State<RightBar> {
  _Panel? _open;

  /// 面板里画的是哪个:收起的动画播完才清掉,收的过程中内容还在。
  _Panel? _shown;
  Timer? _poll;

  ComfyRunner get runner => widget.runner;
  StudioViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    // 等这一帧建完再测:测连接会马上通知,两个页面共用一个 runner,别的页面正在建。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(runner.check());
    });
    _poll = Timer.periodic(_pollEvery, (_) => runner.check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _toggle(_Panel panel) {
    setState(() {
      _open = _open == panel ? null : panel;
      if (_open != null) _shown = _open;
    });
    // 打开时把名单也重读一遍:ComfyUI 那边可能刚放进新模型、新 LoRA。
    if (_open == _Panel.comfy) unawaited(runner.check(full: true));
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final shown = _shown;
    final width = _stripWidth + (open == null ? 0 : _panelWidth);
    return ListenableBuilder(
      listenable: Listenable.merge([runner, widget.config, vm]),
      builder: (context, _) => AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        curve: Motion.swift,
        width: width,
        onEnd: () {
          if (_open == null && _shown != null) setState(() => _shown = null);
        },
        decoration: BoxDecoration(
          boxShadow: open == null
              ? null
              : const [BoxShadow(color: Color(0x22000000), blurRadius: 14)],
        ),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerRight,
            minWidth: _stripWidth + _panelWidth,
            maxWidth: _stripWidth + _panelWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _panelWidth,
                  child: shown == null ? null : _glass(_panel(shown)),
                ),
                _strip(open),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 半透明、模糊后面的底。
  Widget _glass(Widget child) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PennaColors.card.withValues(alpha: _panelOpacity),
          border: Border(left: BorderSide(color: PennaColors.border)),
        ),
        child: child,
      ),
    ),
  );

  Widget _panel(_Panel panel) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 38,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                panel == _Panel.comfy ? 'ComfyUI' : tr('历史对话'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (panel == _Panel.comfy)
              IconButton(
                tooltip: tr('刷新'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate500,
                icon: const Icon(Icons.refresh),
                onPressed: runner.checking
                    ? null
                    : () => runner.check(full: true),
              ),
            // 不带悬停提示:点了按钮就收走了,提示会挂在原处。
            IconButton(
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate400,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _toggle(panel),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: panel == _Panel.comfy
            ? ComfyPanel(runner: runner, config: widget.config)
            : _history(),
      ),
    ],
  );

  Widget _history() {
    final chats = byRecent(vm.pastChats);
    if (chats.isEmpty) {
      return Center(
        child: Text(
          tr('还没有历史对话'),
          style: TextStyle(fontSize: 12, color: PennaColors.slate400),
        ),
      );
    }
    // 按最后说话的日子分组:今天、昨天、日期。
    final rows = <Object>[];
    String? day;
    for (final c in chats) {
      final key = dayKey(chatTime(c));
      if (key != day) rows.add(day = key);
      rows.add(c);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
      itemCount: rows.length,
      itemBuilder: (context, i) => switch (rows[i]) {
        final String key => Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
          child: Text(
            dayLabel(key),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PennaColors.slate500,
            ),
          ),
        ),
        final ChatSession chat => _historyRow(chat),
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _historyRow(ChatSession chat) {
    final t = chatTime(chat);
    String two(int n) => '$n'.padLeft(2, '0');
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      // 生成回复期间换不了对话。
      onTap: vm.isStreaming ? null : () => vm.openChat(chat.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chatTitle(chat.messages),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: PennaColors.slate700,
                    ),
                  ),
                  Text(
                    tr('{0} · {1} 条', [
                      '${two(t.hour)}:${two(t.minute)}',
                      chat.messages.length,
                    ]),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('删除这场对话'),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate400,
              icon: const Icon(Icons.close),
              onPressed: () => vm.deleteChat(chat.id),
            ),
          ],
        ),
      ),
    );
  }

  /// 一列图标,贴在最右边。
  Widget _strip(_Panel? open) {
    final cfg = widget.config.config;
    final piercing = cfg.piercing;
    return Container(
      width: _stripWidth,
      decoration: BoxDecoration(
        color: PennaColors.slate50,
        border: Border(left: BorderSide(color: PennaColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          _StripButton(
            tooltip: 'ComfyUI · ${comfyStatusText(runner.status)}',
            selected: open == _Panel.comfy,
            onTap: () => _toggle(_Panel.comfy),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.brush_outlined,
                  size: 16,
                  color: PennaColors.slate500,
                ),
                Positioned(
                  right: -3,
                  bottom: -2,
                  child: CircleAvatar(
                    radius: 3.5,
                    backgroundColor: comfyDot(runner.status),
                  ),
                ),
              ],
            ),
          ),
          _StripButton(
            tooltip: tr('历史对话'),
            selected: open == _Panel.history,
            onTap: () => _toggle(_Panel.history),
            child: Icon(Icons.history, size: 16, color: PennaColors.slate500),
          ),
          _StripButton(
            tooltip: piercing ? tr('穿甲弹:开') : tr('穿甲弹:关'),
            selected: piercing,
            onTap: () {
              widget.config.update(cfg.copyWith(piercing: !piercing));
              // 文档模式不填内容也能用。
              if (!piercing &&
                  !cfg.piercingDocument &&
                  cfg.piercingPrompt.trim().isEmpty) {
                showToast(context, tr('穿甲弹内容为空,在设置 → Preset 里填写'), warn: true);
              }
            },
            child: Icon(
              Icons.bolt,
              size: 16,
              color: piercing ? PennaColors.primary : PennaColors.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏上的一个图标按钮;[selected] 时底色标出。
class _StripButton extends StatelessWidget {
  const _StripButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? PennaColors.primaryBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: child,
        ),
      ),
    ),
  );
}
