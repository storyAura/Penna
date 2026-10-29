import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

const _closedWidth = 30.0;
const _openWidth = 210.0;

String _clock(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 工作台最左边的操作记录:平时是一条窄边,点开是一列流水账(新的在上)。
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
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final actions = widget.vm.actions;
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
              Tooltip(
                message: _open ? tr('收起操作记录') : tr('操作记录'),
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        const SizedBox(width: 7),
                        Icon(
                          Icons.history,
                          size: 16,
                          color: PennaColors.slate500,
                        ),
                        if (_open) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr('操作记录'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_left,
                            size: 16,
                            color: PennaColors.slate400,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_open) const Divider(height: 1),
              if (_open)
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
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: actions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, i) => _ActionTile(
                            record: actions[i],
                            state: widget.vm.stateOf(i),
                            onBefore: () =>
                                _report(context, widget.vm.rollback(i)),
                            onAfter: () =>
                                _report(context, widget.vm.restoreTo(i)),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void _report(BuildContext context, String? problem) {
  if (problem != null) showToast(context, problem, warn: true);
}

/// 操作记录里的一笔:时间、和眼前的关系、做了什么(合成的几步用小字列在下面),
/// 右上角两个按钮回到它之前、之后。眼前这一笔底色标出;撤回来的、别的分支上的是灰字。
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.record,
    required this.state,
    required this.onBefore,
    required this.onAfter,
  });

  final ActionRecord record;
  final ActionState state;
  final VoidCallback onBefore;
  final VoidCallback onAfter;

  @override
  Widget build(BuildContext context) {
    final current = state == ActionState.current;
    final away = state == ActionState.undone || state == ActionState.branch;
    final tag = switch (state) {
      ActionState.current => tr('当前'),
      ActionState.undone => tr('已撤销'),
      ActionState.branch => tr('另一分支'),
      ActionState.done => null,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 2, 6),
      decoration: BoxDecoration(
        color: current ? PennaColors.primaryBg : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: current ? PennaColors.primaryBorder : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (state == ActionState.branch) ...[
                Icon(Icons.call_split, size: 11, color: PennaColors.slate400),
                const SizedBox(width: 3),
              ],
              Text(
                _clock(record.time),
                style: TextStyle(fontSize: 10.5, color: PennaColors.slate400),
              ),
              if (tag != null) ...[
                const SizedBox(width: 6),
                Text(
                  tag,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: current ? PennaColors.primary : PennaColors.slate400,
                  ),
                ),
              ],
              const Spacer(),
              _jump(Icons.undo, tr('回到这一步之前'), onBefore),
              if (!current) _jump(Icons.redo, tr('回到这一步之后'), onAfter),
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

  Widget _jump(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 13, color: PennaColors.slate500),
      ),
    ),
  );
}
