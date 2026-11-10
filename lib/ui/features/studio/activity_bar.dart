import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_queue_panel.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

const _closedWidth = 30.0;
const _openWidth = 320.0;

/// 左侧栏展开的是哪一块。
enum _Panel { actions, queue }

String _clock(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 工作台最左边的一条窄边:操作记录(一列流水账,新的在上)和出图队列,点哪个图标展开哪个。
class ActivityBar extends StatefulWidget {
  const ActivityBar({super.key, required this.vm});

  final StudioViewModel vm;

  /// 收起、展开时各占多宽;外面排版要用。
  static double widthOf({required bool open}) =>
      open ? _openWidth : _closedWidth;

  @override
  State<ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<ActivityBar> {
  _Panel? _panel;

  bool get _open => _panel != null;

  void _toggle(_Panel p) => setState(() => _panel = _panel == p ? null : p);

  /// 一个切换按钮:展开的那块高亮;排着队时队列图标上带个数。
  Widget _button(_Panel p) {
    final queue = p == _Panel.queue;
    final selected = _panel == p;
    final runner = widget.vm.comfy;
    return Tooltip(
      message: queue ? tr('出图队列') : tr('操作记录'),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _toggle(p),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: selected ? PennaColors.primaryBg : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: ListenableBuilder(
            listenable: runner,
            builder: (context, _) {
              final count = runner.waiting + (runner.running ? 1 : 0);
              // 个数画在按钮自己的右上角里面,不压到旁边的按钮和标题。
              return Stack(
                children: [
                  Center(
                    child: Icon(
                      queue ? Icons.burst_mode_outlined : Icons.history,
                      size: 16,
                      color: selected
                          ? PennaColors.primary
                          : PennaColors.slate500,
                    ),
                  ),
                  if (queue && count > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 11),
                        height: 11,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: PennaColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontSize: 8,
                            height: 1,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.vm.actions;
    const panels = _Panel.values;
    return AnimatedContainer(
      duration: Motion.base,
      curve: Motion.swift,
      width: ActivityBar.widthOf(open: _open),
      decoration: BoxDecoration(
        color: PennaColors.slate50,
        border: Border(right: BorderSide(color: PennaColors.border)),
        // 区域控制页里它展开时盖在属性栏上,带一点影子看得出浮在上面。
        boxShadow: _open
            ? const [BoxShadow(color: Color(0x22000000), blurRadius: 14)]
            : null,
      ),
      // 宽度变化的过程中里面的东西不换行、不报溢出,多出来的裁掉。
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: ActivityBar.widthOf(open: _open),
          maxWidth: ActivityBar.widthOf(open: _open),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_open)
                for (final p in panels)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Center(child: _button(p)),
                  )
              else
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      const SizedBox(width: 2),
                      for (final p in panels) _button(p),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _panel == _Panel.queue ? tr('出图队列') : tr('操作记录'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: tr('收起'),
                        child: InkWell(
                          onTap: () => setState(() => _panel = null),
                          child: Icon(
                            Icons.chevron_left,
                            size: 16,
                            color: PennaColors.slate400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              if (_open) const Divider(height: 1),
              if (_panel == _Panel.queue)
                Expanded(child: ComfyQueuePanel(runner: widget.vm.comfy)),
              if (_panel == _Panel.actions)
                Expanded(
                  child: actions.isEmpty
                      ? Center(
                          child: Text(
                            tr('还没有操作'),
                            style: TextStyle(
                              fontSize: 12,
                              color: PennaColors.slate400,
                            ),
                          ),
                        )
                      : _actionList(context, actions),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 撤销、重做两个按钮,下面一行一笔(新的在前),点哪笔回到它做完之后;
  /// 最底下「最开始」回到第一笔之前。
  Widget _actionList(BuildContext context, List<ActionRecord> actions) {
    final vm = widget.vm;
    final atStart = !vm.canUndo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              PennaButton(
                icon: Icons.undo,
                label: tr('撤销'),
                onPressed: vm.canUndo
                    ? () => _report(context, vm.undo())
                    : null,
              ),
              const SizedBox(width: 4),
              PennaButton(
                icon: Icons.redo,
                label: tr('重做'),
                onPressed: vm.canRedo
                    ? () => _report(context, vm.redo())
                    : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final (i, a) in actions.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ActionTile(
                    record: a,
                    state: vm.stateOf(i),
                    onTap: () => _report(context, vm.restoreTo(i)),
                  ),
                ),
              _StartTile(
                current: atStart,
                onTap: () => _report(context, vm.rollback(actions.length - 1)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _report(BuildContext context, String? problem) {
  if (problem != null) showToast(context, problem, warn: true);
}

/// 操作记录里的一笔:时间、做了什么(合成的几步用小字列在下面)。点它回到这一步做完之后。
/// 眼前这一笔底色标出;撤回来的是灰字。
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.record,
    required this.state,
    required this.onTap,
  });

  final ActionRecord record;
  final ActionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = state == ActionState.current;
    final away = state == ActionState.undone;
    return _Tile(
      current: current,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _clock(record.time),
                style: TextStyle(fontSize: 10.5, color: PennaColors.slate400),
              ),
              if (current || away) ...[
                const SizedBox(width: 6),
                Text(
                  current ? tr('当前') : tr('已撤销'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: current ? PennaColors.primary : PennaColors.slate400,
                  ),
                ),
              ],
            ],
          ),
          Text(
            record.text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: away ? PennaColors.slate400 : PennaColors.slate700,
            ),
          ),
          for (final step in record.details)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                '· $step',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: away ? PennaColors.slate400 : PennaColors.slate500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 最底下那一行:回到第一笔之前。
class _StartTile extends StatelessWidget {
  const _StartTile({required this.current, required this.onTap});

  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Tile(
    current: current,
    onTap: onTap,
    child: Row(
      children: [
        Icon(Icons.flag_outlined, size: 13, color: PennaColors.slate400),
        const SizedBox(width: 4),
        Text(
          tr('最开始'),
          style: TextStyle(fontSize: 12, color: PennaColors.slate500),
        ),
        if (current) ...[
          const SizedBox(width: 6),
          Text(
            tr('当前'),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: PennaColors.primary,
            ),
          ),
        ],
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.current,
    required this.onTap,
    required this.child,
  });

  final bool current;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: current ? PennaColors.primaryBg : Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(
        color: current ? PennaColors.primaryBorder : Colors.transparent,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: current ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: child,
      ),
    ),
  );
}
