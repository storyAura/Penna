part of 'chat_pane.dart';

// 对话顶栏:选模型、新对话、切换 Preset。

/// 顶栏:当前模型(点击去设置)+ Preset 切换。
class _Header extends StatelessWidget {
  const _Header({
    required this.vm,
    required this.config,
    required this.onOpenSettings,
  });

  final StudioViewModel vm;
  final ConfigService config;

  /// 「新对话」按钮;生成中换不了,所以先禁用。历史对话、穿甲弹在右边的侧栏里。
  List<Widget> _chatButtons(BuildContext context, {required bool compact}) => [
    Tooltip(
      message: tr('新对话'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: vm.isStreaming || vm.messages.isEmpty ? null : vm.newChat,
          child: _HeaderChip(
            icon: Icons.add_comment_outlined,
            label: compact ? '' : tr('新对话'),
            enabled: !vm.isStreaming && vm.messages.isNotEmpty,
          ),
        ),
      ),
    ),
    const SizedBox(width: 6),
  ];
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cfg = config.config;
    final chain = cfg.agentChain;
    // 指定的模型被删了或关了,就当作按顺序。
    final pinned = chain.any((l) => l.id == cfg.activeLlmId)
        ? cfg.activeLlmId
        : null;
    PopupMenuItem<String> item(String value, String name, bool selected) =>
        PopupMenuItem(
          value: value,
          height: 34,
          padding: EdgeInsets.zero,
          child: _PresetMenuRow(name: name, selected: selected),
        );
    return LayoutBuilder(
      builder: (context, box) {
        // 区域控制的 420px 对话栏给名称留出位置,操作仍使用原来的图标和菜单。
        final compact = box.maxWidth < 560;
        return PennaBar(
          color: PennaColors.card,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: chain.isEmpty
                    ? PennaButton(
                        label: compact ? '' : tr('未连接模型 · 去设置'),
                        tooltip: tr('未连接模型 · 去设置'),
                        icon: Icons.auto_awesome,
                        background: PennaColors.slate50,
                        foreground: PennaColors.slate500,
                        borderColor: PennaColors.border,
                        onPressed: onOpenSettings,
                      )
                    : PopupMenuButton<String>(
                        popUpAnimationStyle: Motion.menu(context),
                        tooltip: tr('Agent 使用的模型'),
                        position: PopupMenuPosition.under,
                        offset: const Offset(0, 6),
                        onSelected: (id) => id == _manageModels
                            ? onOpenSettings()
                            : config.update(
                                cfg.copyWith(
                                  activeLlmId: () => id == _byOrder ? null : id,
                                ),
                              ),
                        itemBuilder: (_) => [
                          item(_byOrder, tr('按顺序'), pinned == null),
                          for (final l in chain)
                            item(
                              l.id,
                              l.name.trim().isEmpty ? tr('未命名') : l.name,
                              pinned == l.id,
                            ),
                          const PopupMenuDivider(height: 8),
                          item(_manageModels, tr('管理模型…'), false),
                        ],
                        child: Bouncy(
                          child: PennaCard(
                            color: PennaColors.slate50,
                            radius: 6,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 14,
                                  color: PennaColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    chain.first.name.trim().isEmpty
                                        ? tr('未命名')
                                        : chain.first.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 14,
                                  color: PennaColors.slate500,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 6),
            ..._chatButtons(context, compact: compact),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.3),
              child: PopupMenuButton<String>(
                popUpAnimationStyle: Motion.menu(context),
                tooltip: tr('切换 Preset'),
                position: PopupMenuPosition.under,
                offset: const Offset(0, 6),
                onSelected: (id) =>
                    config.update(cfg.copyWith(activePresetId: id)),
                itemBuilder: (_) => [
                  for (final p in cfg.presets)
                    PopupMenuItem(
                      value: p.id,
                      height: 34,
                      padding: EdgeInsets.zero,
                      child: _PresetMenuRow(
                        name: p.displayName,
                        selected: p.id == cfg.activePreset.id,
                      ),
                    ),
                ],
                child: Bouncy(
                  child: PennaCard(
                    color: PennaColors.slate100,
                    borderColor: PennaColors.slate100,
                    radius: 6,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 14, color: PennaColors.slate500),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            cfg.activePreset.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: PennaColors.slate700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: PennaColors.slate500,
                        ),
                      ],
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
}

/// 顶栏上「新对话」「历史」这种白底小按钮。
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? PennaColors.slate700 : PennaColors.slate400;
    return Bouncy(
      child: PennaCard(
        color: PennaColors.card,
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetMenuRow extends StatelessWidget {
  const _PresetMenuRow({required this.name, required this.selected});

  final String name;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PennaColors.primary : PennaColors.slate700;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? PennaColors.primaryBg : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
          if (selected) Icon(Icons.check, size: 14, color: color),
        ],
      ),
    );
  }
}
