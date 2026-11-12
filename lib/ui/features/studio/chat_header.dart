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
  List<Widget> _chatButtons(BuildContext context) => [
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
  ];
  final VoidCallback onOpenSettings;

  /// 菜单里选中一项:换 Agent 用的接口和模型。读最新的设置,菜单开着时可能已经换过一次。
  void _pick(String v) {
    final (id, model) = _llmPick(v);
    config.update(
      config.config.copyWith(activeLlmId: () => id, activeModel: () => model),
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
            popUpAnimationStyle: Motion.menu(context),
            tooltip: tr('Agent 使用的模型'),
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            onSelected: (v) {
              if (v == _manageModels) return onOpenSettings();
              _pick(v);
            },
            itemBuilder: (_) => _llmMenu(chain, pinned, _pick),
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
                      _llmLabel(chain.first),
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
          popUpAnimationStyle: Motion.menu(context),
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

String _llmName(LlmProfile l) => l.name.trim().isEmpty ? tr('未命名') : l.name;

/// 顶栏上显示的名字:接口填了几个模型时带上眼前先用的那个。
String _llmLabel(LlmProfile l) =>
    l.models.length > 1 ? '${_llmName(l)} · ${l.models.first}' : _llmName(l);

/// 菜单值里接口 id 和模型名的分隔。
const _modelSep = '\u0000';

/// 选模型的下拉:按顺序、各接口;接口填了几个模型时,只有眼前用着的那个接口
/// 下面缩进列出它的模型(2026-11-13 用户要求)。点这种接口不关菜单:换过去、
/// 它的模型展开,原来那个收起;点模型、单个模型的接口、按顺序才关。
/// [chain] 里指定的接口已经把选中的模型排到第一个。[pick] 是选中某项后改设置。
List<PopupMenuEntry<String>> _llmMenu(
  List<LlmProfile> chain,
  String? pinned,
  ValueChanged<String> pick,
) {
  // 菜单开着时换接口,各行靠它跟着变。
  final open = ValueNotifier(pinned);
  PopupMenuItem<String> item(String value, String name, String? id) =>
      PopupMenuItem(
        value: value,
        height: 34,
        padding: EdgeInsets.zero,
        child: ValueListenableBuilder(
          valueListenable: open,
          builder: (_, now, _) =>
              _PresetMenuRow(name: name, selected: id != null && now == id),
        ),
      );
  return [
    PopupMenuItem(
      value: _byOrder,
      height: 34,
      padding: EdgeInsets.zero,
      child: ValueListenableBuilder(
        valueListenable: open,
        builder: (_, now, _) =>
            _PresetMenuRow(name: tr('按顺序'), selected: now == null),
      ),
    ),
    for (final l in chain)
      if (l.models.length > 1)
        _LlmGroup(
          llm: l,
          open: open,
          onPin: () {
            open.value = l.id;
            pick(l.id);
          },
        )
      else
        item(l.id, _llmName(l), l.id),
    const PopupMenuDivider(height: 8),
    item(_manageModels, tr('管理模型…'), null),
  ];
}

/// 填了几个模型的接口:一行接口名,眼前用着它时下面展开它的模型。
class _LlmGroup extends PopupMenuEntry<String> {
  const _LlmGroup({required this.llm, required this.open, required this.onPin});

  final LlmProfile llm;
  final ValueNotifier<String?> open;
  final VoidCallback onPin;

  @override
  double get height => 34;

  @override
  bool represents(String? value) => false;

  @override
  State<_LlmGroup> createState() => _LlmGroupState();
}

class _LlmGroupState extends State<_LlmGroup> {
  @override
  Widget build(BuildContext context) {
    final l = widget.llm;
    return ValueListenableBuilder(
      valueListenable: widget.open,
      builder: (context, now, _) {
        final here = now == l.id;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: here ? null : widget.onPin,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 34),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _PresetMenuRow(name: _llmName(l), selected: false),
                ),
              ),
            ),
            // 模型一直排着(菜单宽度不跳),只把高度在 0 和全高之间动。
            ClipRect(
              child: AnimatedAlign(
                duration: Motion.of(context, Motion.base),
                curve: Motion.expand,
                alignment: Alignment.topCenter,
                heightFactor: here ? 1 : 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, m) in l.models.indexed)
                      InkWell(
                        onTap: () =>
                            Navigator.pop(context, '${l.id}$_modelSep$m'),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 30),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _PresetMenuRow(
                                name: m,
                                selected: here && i == 0,
                                sub: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 菜单值 → (指定的接口 id, 先用的模型);按顺序是 (null, null)。
(String?, String?) _llmPick(String value) {
  if (value == _byOrder) return (null, null);
  final i = value.indexOf(_modelSep);
  return i < 0
      ? (value, null)
      : (value.substring(0, i), value.substring(i + 1));
}

class _PresetMenuRow extends StatelessWidget {
  const _PresetMenuRow({
    required this.name,
    required this.selected,
    this.sub = false,
  });

  final String name;
  final bool selected;

  /// 接口下面的模型:字小一点、灰一点。
  final bool sub;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? PennaColors.primary
        : sub
        ? PennaColors.slate500
        : PennaColors.slate700;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: sub ? 5 : 7),
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
                fontSize: sub ? 12 : 12.5,
                fontWeight: sub ? FontWeight.w500 : FontWeight.w600,
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
