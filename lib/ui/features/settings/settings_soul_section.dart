import 'package:flutter/material.dart';

import '../../../data/services/soul_store.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_agent_sections.dart' show hintStyle;
import 'settings_sections.dart';

/// PennaSoul:Agent 记着的约定和偏好。在这里看、加约定、删掉不要的。
class SoulSection extends StatelessWidget {
  const SoulSection({super.key, required this.soul});

  final SoulStore soul;

  Future<void> _add(BuildContext context) async {
    final text = await askName(
      context,
      tr('添加约定'),
      '',
      label: tr('约定'),
      hint: '',
      maxLines: 4,
    );
    if (text != null && text.trim().isNotEmpty) soul.remember(soulRule, text);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: soul,
    builder: (context, _) {
      final rules = soul.entries.where((e) => e.kind == soulRule).toList();
      final likes = soul.entries.where((e) => e.kind != soulRule).toList();
      final cast = soul.cast;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading('PennaSoul', tr('记住的约定和偏好')),
          PennaCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(tr('约定'), style: titleStyle)),
                    PennaButton(
                      label: tr('添加约定'),
                      icon: Icons.add,
                      borderColor: PennaColors.border,
                      onPressed: () => _add(context),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (rules.isEmpty) Text(tr('还没有'), style: hintStyle),
                for (final e in rules) _SoulRow(entry: e, soul: soul),
              ],
            ),
          ),
          gap,
          PennaCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('偏好'), style: titleStyle),
                const SizedBox(height: 6),
                if (likes.isEmpty) Text(tr('还没有'), style: hintStyle),
                for (final e in likes) _SoulRow(entry: e, soul: soul),
              ],
            ),
          ),
          gap,
          PennaCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('常用角色'), style: titleStyle),
                const SizedBox(height: 8),
                if (cast.isEmpty)
                  Text(tr('还没有'), style: hintStyle)
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in cast)
                        InputChip(
                          label: Text(
                            '${c.name}  ${c.count}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          visualDensity: VisualDensity.compact,
                          deleteIcon: const Icon(Icons.close, size: 14),
                          deleteButtonTooltipMessage: tr('删除'),
                          onDeleted: () => soul.forgetCharacter(c.name),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// 一条记忆:原话、编辑、删除。
class _SoulRow extends StatelessWidget {
  const _SoulRow({required this.entry, required this.soul});

  final SoulEntry entry;
  final SoulStore soul;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(entry.text, style: const TextStyle(fontSize: 13))),
      IconButton(
        tooltip: tr('编辑'),
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        color: PennaColors.slate400,
        icon: const Icon(Icons.edit_outlined),
        onPressed: () async {
          final text = await askName(
            context,
            tr('编辑'),
            entry.text,
            label: entry.kind == soulRule ? tr('约定') : tr('偏好'),
            hint: '',
            maxLines: 4,
          );
          if (text != null) soul.edit(entry.id, text);
        },
      ),
      IconButton(
        tooltip: tr('删除'),
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        color: PennaColors.slate400,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => soul.forget(entry.id),
      ),
    ],
  );
}
