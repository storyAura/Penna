part of 'chat_pane.dart';

// 对话顶栏:选模型、新对话、历史、切换 Preset。

/// 顶栏:当前模型(点击去设置)+ Preset 切换。
class _Header extends StatelessWidget {
  const _Header({
    required this.vm,
    required this.config,
    required this.onOpenSettings,
  });

  final StudioViewModel vm;
  final ConfigService config;

  /// 「新对话」和「历史」两个按钮;生成中换不了,所以先禁用。
  List<Widget> _chatButtons(BuildContext context) => [
    _piercingToggle(context),
    const SizedBox(width: 6),
    // 和旁边的「历史」同一个样子、同样大。
    MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: vm.isStreaming || vm.messages.isEmpty ? null : vm.newChat,
        child: _HeaderChip(
          icon: Icons.add_comment_outlined,
          label: tr('新对话'),
          enabled: !vm.isStreaming && vm.messages.isNotEmpty,
        ),
      ),
    ),
    const SizedBox(width: 6),
    PopupMenuButton<String>(
      tooltip: tr('历史对话'),
      enabled: !vm.isStreaming && vm.pastChats.isNotEmpty,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
      onSelected: vm.openChat,
      itemBuilder: (menu) => [
        for (final chat in vm.pastChats)
          PopupMenuItem(
            value: chat.id,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        tr(
                          '{0} · '
                          '{1} 条',
                          [
                            shortTime(chat.messages.first.time),
                            chat.messages.length,
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: PennaColors.slate400,
                        ),
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
                  onPressed: () {
                    vm.deleteChat(chat.id);
                    Navigator.pop(menu);
                  },
                ),
              ],
            ),
          ),
      ],
      child: _HeaderChip(
        icon: Icons.history,
        label: tr('历史'),
        enabled: vm.pastChats.isNotEmpty,
      ),
    ),
    const SizedBox(width: 6),
  ];
  final VoidCallback onOpenSettings;

  /// 穿甲弹的快捷开关(内容在「设置 → Preset」里写);对话栏窄,只放图标。
  Widget _piercingToggle(BuildContext context) {
    final cfg = config.config;
    final on = cfg.piercing;
    return Tooltip(
      message: on ? tr('穿甲弹:开') : tr('穿甲弹:关'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            config.update(cfg.copyWith(piercing: !on));
            if (!on && cfg.piercingPrompt.trim().isEmpty) {
              showToast(context, tr('穿甲弹内容为空,在设置 → Preset 里填写'), warn: true);
            }
          },
          child: Bouncy(
            child: PennaCard(
              color: on ? PennaColors.primaryBg : PennaColors.card,
              borderColor: on ? PennaColors.primaryBorder : null,
              radius: 6,
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.bolt,
                size: 15,
                color: on ? PennaColors.primary : PennaColors.slate500,
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    return PennaBar(
      color: PennaColors.card,
      children: [
        if (chain.isEmpty)
          PennaButton(
            label: tr('未连接模型 · 去设置'),
            icon: Icons.auto_awesome,
            background: PennaColors.slate50,
            foreground: PennaColors.slate500,
            borderColor: PennaColors.border,
            onPressed: onOpenSettings,
          )
        else
          PopupMenuButton<String>(
            tooltip: tr('Agent 使用的模型'),
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            onSelected: (id) => id == _manageModels
                ? onOpenSettings()
                : config.update(
                    cfg.copyWith(activeLlmId: () => id == _byOrder ? null : id),
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
                    Text(
                      chain.first.name.trim().isEmpty
                          ? tr('未命名')
                          : chain.first.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
        const Spacer(),
        ..._chatButtons(context),
        PopupMenuButton<String>(
          tooltip: tr('切换 Preset'),
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          onSelected: (id) => config.update(cfg.copyWith(activePresetId: id)),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 14, color: PennaColors.slate500),
                  const SizedBox(width: 4),
                  Text(
                    cfg.activePreset.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PennaColors.slate700,
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
      ],
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
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (selected) Icon(Icons.check, size: 14, color: color),
        ],
      ),
    );
  }
}
