import 'package:flutter/material.dart';

import '../data/services/archive_store.dart';
import '../data/services/character_store.dart';
import '../data/services/config_service.dart';
import '../data/services/notebook_store.dart';
import '../data/services/skill_store.dart';
import 'core/theme.dart';
import 'core/version.dart';
import 'core/widgets.dart';
import 'features/archive/archive_page.dart';
import 'features/characters/characters_page.dart';
import 'features/layout/layout_board.dart';
import 'features/layout/layout_page.dart';
import 'features/local/local_model.dart';
import 'features/local/local_page.dart';
import 'features/notebook/notebook_page.dart';
import 'features/settings/settings_page.dart';
import 'features/studio/side_chat.dart';
import 'features/studio/studio_page.dart';
import 'features/studio/studio_view_model.dart';
import 'features/update/update_flow.dart';
import '../l10n/l10n.dart';
import 'core/motion.dart';

export 'core/version.dart';

const _studio = 0,
    _archivePage = 1,
    _settings = 2,
    _charactersPage = 3,
    _localPage = 4,
    _layoutPage = 5,
    _notebookPage = 6;

/// 应用外壳:最左图标栏,右边在「工作台」「档案库」「角色库」「本地反推」「布局」「记事本」「设置」之间切换。
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.vm,
    required this.config,
    required this.skills,
    this.layoutChat,
    this.archive,
    this.notebooks,
    this.local,
    this.checkUpdates = false,
  });

  /// 记事本;不给就用一个只在内存里的(测试用)。
  final NotebookStore? notebooks;

  /// 布局页右边那场对话;不给就用一个只在内存里的(测试用)。
  final StudioViewModel? layoutChat;

  final StudioViewModel vm;
  final ConfigService config;
  final SkillStore skills;

  /// 档案库;不给就用一个只在内存里的(测试用)。
  final ArchiveStore? archive;

  /// 本地反推;不给就用一个只在内存里、不能下载的(测试用)。
  final LocalModel? local;

  /// 打开时悄悄检查一次更新,有新版本才弹窗(正式版才开,测试里不联网)。
  final bool checkUpdates;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    // 测试里没在 main() 接上:Agent 用的就是这一页上的本地反推。
    widget.vm.local ??= _local;
    widget.vm.layoutAgent ??= _layoutChat;
    widget.vm.side ??= SideChat(widget.vm);
    _layoutChat.side ??= SideChat(_layoutChat);
    if (widget.checkUpdates) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => checkForUpdate(
          context,
          quiet: true,
          channel: widget.vm.config.config.updateChannel,
        ),
      );
    }
  }

  int _page = _studio;
  late final _archive = widget.archive ?? ArchiveStore();
  late final _notebooks = widget.notebooks ?? NotebookStore();
  // 角色库跟着工作台走:Agent 存进去的和这一页上看到的是同一份。
  late final _characters = widget.vm.characters ?? CharacterStore();
  // 布局画板同样跟着工作台走:Agent 写的布局放到这一页上。
  late final _layout =
      widget.vm.layout ??
      LayoutBoard(quality: () => widget.config.config.layoutQuality);
  late final _layoutChat =
      widget.layoutChat ??
      StudioViewModel(
        config: widget.config,
        streamChat: widget.vm.streamChat,
        skills: widget.skills,
        characters: _characters,
        characterDict: widget.vm.characterDict,
        layout: _layout,
        layoutOnly: true,
      );

  /// 别的页面要交给 Agent 的话:工作台收到后填进聊天输入框。
  final _toChat = ValueNotifier<String?>(null);

  late final _local =
      widget.local ?? LocalModel(streamChat: widget.vm.streamChat);

  void _go(int page) => setState(() => _page = page);

  @override
  void dispose() {
    _toChat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.config,
        builder: (context, _) => Column(
          children: [
            if (widget.config.lastError != null)
              _ErrorBanner(message: widget.config.lastError!),
            Expanded(
              child: Row(
                children: [
                  _NavRail(page: _page, onSelect: _go),
                  Expanded(
                    // 几页都一直留着,切去设置时工作台的输入和滚动位置不丢。
                    child: Stack(
                      children: [
                        _Page(
                          active: _page == _studio,
                          child: StudioPage(
                            vm: widget.vm,
                            config: widget.config,
                            archive: _archive,
                            onOpenSettings: () => _go(_settings),
                            onOpenLayout: () => _go(_layoutPage),
                            inbox: _toChat,
                          ),
                        ),
                        _Page(
                          active: _page == _archivePage,
                          child: ArchivePage(
                            archive: _archive,
                            vm: widget.vm,
                            board: _layout,
                            onOpenStudio: () => _go(_studio),
                            onOpenLayout: () => _go(_layoutPage),
                          ),
                        ),
                        _Page(
                          active: _page == _charactersPage,
                          child: CharactersPage(
                            store: _characters,
                            dict: widget.vm.characterDict,
                          ),
                        ),
                        _Page(
                          active: _page == _localPage,
                          child: LocalPage(
                            model: _local,
                            config: widget.config,
                            vm: widget.vm,
                            onOpenStudio: () => _go(_studio),
                            onSendToAgent: (text) {
                              _go(_studio);
                              _toChat.value = text;
                            },
                          ),
                        ),
                        _Page(
                          active: _page == _layoutPage,
                          child: LayoutPage(
                            board: _layout,
                            vm: widget.vm,
                            chat: _layoutChat,
                            archive: _archive,
                            config: widget.config,
                            onOpenStudio: () => _go(_studio),
                            onOpenSettings: () => _go(_settings),
                          ),
                        ),
                        _Page(
                          active: _page == _notebookPage,
                          child: NotebookPage(store: _notebooks),
                        ),
                        _Page(
                          active: _page == _settings,
                          child: SettingsPage(
                            service: widget.config,
                            skills: widget.skills,
                            local: _local,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 3,
                          child: IgnorePointer(
                            child: Text(
                              'v$appVersion',
                              style: TextStyle(
                                fontSize: 10,
                                color: PennaColors.slate400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一页内容:切入时淡入并轻轻弹上来,切出后不可见也不响应点击。
class _Page extends StatelessWidget {
  const _Page({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: ExcludeFocus(
          excluding: !active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: Motion.base,
            child: AnimatedSlide(
              offset: active ? Offset.zero : const Offset(0, 0.02),
              duration: Motion.sheet,
              curve: Curves.easeOutBack,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PennaColors.diffDel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SelectableText(
        contextMenuBuilder: pennaTextMenu,
        message,
        style: TextStyle(fontSize: 12, color: PennaColors.diffDelText),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.page, required this.onSelect});

  final int page;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      // 顶部留白让第一个按钮和右边 PennaBar 那一行垂直居中对齐。
      padding: const EdgeInsets.only(top: 1, bottom: 12),
      decoration: BoxDecoration(
        color: PennaColors.sidebar,
        border: Border(right: BorderSide(color: PennaColors.border)),
      ),
      child: Column(
        children: [
          _RailButton(
            icon: Icons.space_dashboard_outlined,
            tooltip: tr('工作台'),
            selected: page == _studio,
            onTap: () => onSelect(_studio),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.inventory_2_outlined,
            tooltip: tr('档案库'),
            selected: page == _archivePage,
            onTap: () => onSelect(_archivePage),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.face_retouching_natural_outlined,
            tooltip: tr('角色库'),
            selected: page == _charactersPage,
            onTap: () => onSelect(_charactersPage),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.memory_outlined,
            tooltip: tr('本地反推'),
            selected: page == _localPage,
            onTap: () => onSelect(_localPage),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.crop_free,
            tooltip: tr('区域控制工作台'),
            selected: page == _layoutPage,
            onTap: () => onSelect(_layoutPage),
          ),
          const SizedBox(height: 6),
          _RailButton(
            icon: Icons.sticky_note_2_outlined,
            tooltip: tr('记事本'),
            selected: page == _notebookPage,
            onTap: () => onSelect(_notebookPage),
          ),
          const Spacer(),
          _RailButton(
            icon: Icons.settings_outlined,
            tooltip: tr('设置'),
            selected: page == _settings,
            onTap: () => onSelect(_settings),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Bouncy(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.base,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? PennaColors.card : PennaColors.sidebar,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? PennaColors.border : PennaColors.sidebar,
                ),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected ? PennaColors.primary : PennaColors.slate500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
