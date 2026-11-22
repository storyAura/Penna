import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';
import '../../../data/services/soul_store.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_agent_sections.dart' show hintStyle;
import 'settings_sections.dart';

/// 「设置 → 实验性功能」(2026-11-23 用户要求):还没定型的功能各一个开关,默认关。
/// 现在只有 PennaSoul;以后的实验性功能也加在这一页。
class ExperimentalSection extends StatelessWidget {
  const ExperimentalSection({
    super.key,
    required this.service,
    required this.soul,
  });

  final ConfigService service;
  final SoulStore soul;

  Future<void> _toggleSoul(BuildContext context, bool on) async {
    if (on &&
        !await confirmDelete(
          context,
          tr('开启 PennaSoul'),
          tr(
            'PennaSoul 会跨对话记住你明确要求记下的约定和偏好,之后每次对话自动交给 Agent。\n\n'
            '开启后可能出现的问题:\n'
            '· 约定会带进每一次对话,Agent 一律照办,写无关的画面时也可能被它带偏。\n'
            '· 偏好和常用角色会影响创作点子,点子可能反复围着同一类题材或角色。\n'
            '· 记下的内容可能不准确,把某一次画面里的服装、动作或情节当成长期喜好。\n'
            '· 工作台、区域控制、漫画分镜和副聊天共用同一份记录,一处记下处处生效。\n\n'
            '提示词出现跑偏时,回到这里关掉 PennaSoul,或删掉相关的记录。',
          ),
          action: tr('开启'),
        )) {
      return;
    }
    service.update(service.config.copyWith(soulOn: on));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('实验性功能'), tr('尚在试验')),
        PennaCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PennaSoul', style: titleStyle),
                    Text(tr('跨对话记住约定,可能污染提示词'), style: hintStyle),
                  ],
                ),
              ),
              Switch(
                value: service.config.soulOn,
                onChanged: (v) => _toggleSoul(context, v),
              ),
            ],
          ),
        ),
        gap,
        SoulSection(soul: soul),
      ],
    ),
  );
}

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
