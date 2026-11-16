import 'package:flutter/material.dart';

import '../../../core/harness/soul_tags.dart';
import '../../../data/services/soul_store.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';

/// 回复下面的「已加入 PennaSoul 记录」:这条回复记下了什么,每条后面能撤销。
/// 撤销了(或在设置里删了)的那条变成灰字「已撤销」。
class SoulNotice extends StatelessWidget {
  const SoulNotice({super.key, required this.soul, required this.notes});

  final SoulStore soul;
  final List<SoulNote> notes;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: soul,
    builder: (context, _) => Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: PennaColors.primaryBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PennaColors.primaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_border, size: 14, color: PennaColors.primary),
              const SizedBox(width: 6),
              Text(
                tr('已加入 PennaSoul 记录'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PennaColors.primary,
                ),
              ),
            ],
          ),
          for (final n in notes) _row(n),
        ],
      ),
    ),
  );

  Widget _row(SoulNote n) {
    final kept = soul.find(n.text);
    return Row(
      children: [
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            '${n.kind == soulRule ? tr('约定') : tr('偏好')} · ${n.text}',
            style: TextStyle(
              fontSize: 12,
              color: kept == null ? PennaColors.slate400 : PennaColors.text,
              decoration: kept == null ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (kept != null)
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: () => soul.forget(kept.id),
            child: Text(tr('撤销')),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              tr('已撤销'),
              style: TextStyle(fontSize: 11.5, color: PennaColors.slate400),
            ),
          ),
      ],
    );
  }
}
