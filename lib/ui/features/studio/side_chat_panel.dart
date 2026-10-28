part of 'chat_pane.dart';

// 副聊天的浮窗:盖在对话右边,底色半透明,看得见后面的对话;关掉不丢记录。
// 气泡和主聊天的是同一个 ChatMessageView,回复里的成稿一样放进工作区。

/// 浮窗底色的不透明度:后面的对话透得出来,字也看得清。
const _sideOpacity = 0.9;
const _sideWidth = 440.0;

/// 浮窗里的快捷操作最多露出几个,多的横着滚。
const _maxSideQuickActions = 4;

/// 快捷操作那一排最右边的开关。
class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PennaButton(
    label: tr('副聊天'),
    icon: Icons.forum_outlined,
    background: open ? PennaColors.primaryBg : PennaColors.slate100,
    foreground: open ? PennaColors.primary : null,
    borderColor: open ? PennaColors.primaryBorder : null,
    onPressed: onTap,
  );
}

class _SidePanel extends StatefulWidget {
  const _SidePanel({
    super.key,
    required this.chat,
    required this.pane,
    required this.config,
    required this.onClose,
    required this.onOpenSettings,
  });

  final SideChat chat;

  /// 主聊天那一栏:成稿卡片的「放到成稿」、状态,和主聊天的走同一套。
  final _ChatPaneState pane;
  final ConfigService config;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> with _Attachments<_SidePanel> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  ConfigService get _config => widget.config;
  @override
  FocusNode get _inputFocus => _focus;
  @override
  void _onImage(Attachment a) => widget.pane.widget.onImage?.call(a);

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final problem = widget.chat.send(_input.text, attachments: _attachments);
    if (problem != null) return showToast(context, problem, warn: true);
    _input.clear();
    setState(() => _attachments = const []);
  }

  /// 快捷操作:和主聊天一样接在输入框末尾,不替换已有的字。
  void _quick(String text) {
    final had = _input.text.trimRight();
    final next = had.isEmpty ? text : '$had $text';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _focus.requestFocus();
  }

  /// Enter 发送,Shift+Enter 换行;输入法选字时不拦。Ctrl+V 能贴图片和文件。
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    _pasteOn(event);
    final isEnter =
        event is! KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter);
    if (!isEnter ||
        HardwareKeyboard.instance.isShiftPressed ||
        _input.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // 主聊天的工作台变了(成稿放进去了)卡片上的状态也要跟着变。
      listenable: Listenable.merge([
        widget.chat,
        widget.config,
        widget.pane.widget.vm,
      ]),
      builder: (context, _) {
        final rows = foldLookups(widget.chat.messages).reversed.toList();
        return Material(
          color: PennaColors.card.withValues(alpha: _sideOpacity),
          elevation: 6,
          shadowColor: Colors.black26,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: PennaColors.border),
          ),
          child: Column(
            children: [
              _head(),
              Divider(height: 1, color: PennaColors.border),
              Expanded(
                // 倒着排:新消息贴在底下,生成时不用自己滚。
                child: ListView.separated(
                  reverse: true,
                  padding: const EdgeInsets.all(14),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _row(rows[i], last: i == 0),
                ),
              ),
              _composer(),
            ],
          ),
        );
      },
    );
  }

  Widget _head() {
    final config = widget.config;
    final cfg = config.config;
    final chain = cfg.sideChain;
    // 指定的模型被删了或关了,就当作按顺序。
    final pinned = chain.any((l) => l.id == cfg.sideLlmId)
        ? cfg.sideLlmId
        : null;
    PopupMenuItem<String> item(String value, String name, bool selected) =>
        PopupMenuItem(
          value: value,
          height: 34,
          padding: EdgeInsets.zero,
          child: _PresetMenuRow(name: name, selected: selected),
        );
    String nameOf(LlmProfile l) => l.name.trim().isEmpty ? tr('未命名') : l.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Icon(Icons.forum_outlined, size: 16, color: PennaColors.primary),
          const SizedBox(width: 6),
          Text(
            tr('副聊天'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: tr('副聊天使用的模型'),
              position: PopupMenuPosition.under,
              onSelected: (id) => id == _manageModels
                  ? widget.onOpenSettings()
                  : config.update(
                      cfg.copyWith(sideLlmId: () => id == _byOrder ? null : id),
                    ),
              itemBuilder: (_) => [
                item(_byOrder, tr('按顺序'), pinned == null),
                for (final l in chain) item(l.id, nameOf(l), pinned == l.id),
                const PopupMenuDivider(height: 8),
                item(_manageModels, tr('管理模型…'), false),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      chain.isEmpty ? tr('未连接模型') : nameOf(chain.first),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: PennaColors.slate500,
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
          const Spacer(),
          Tooltip(
            message: tr('副聊天单独的穿甲弹开关'),
            child: PennaChip(
              label: tr('穿甲弹'),
              selected: cfg.sidePiercing,
              onTap: () =>
                  config.update(cfg.copyWith(sidePiercing: !cfg.sidePiercing)),
            ),
          ),
          IconButton(
            tooltip: tr('清空副聊天'),
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: widget.chat.messages.isEmpty ? null : widget.chat.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: tr('关闭'),
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// 和主聊天一样的气泡:成稿卡片、选项、工具记录都有;成稿放进工作区。
  Widget _row(ChatRow row, {required bool last}) {
    final chat = widget.chat;
    final pane = widget.pane;
    final vm = pane.widget.vm;
    final cfg = widget.config.config;
    return ChatMessageView(
      message: row.message,
      lookups: row.lookups,
      agentAvatar: cfg.agentAvatar,
      userAvatar: cfg.userAvatar,
      onAdoptDraft: (draft) => pane._adoptDraft(draft, null),
      draftStatus: pane._draftStatus,
      userSkills: vm.skills?.skills ?? const [],
      onAddSkill: pane._addSkill,
      onAdoptLayout: pane._adoptLayout,
      streaming: chat.isStreaming && last,
      onRetry: !chat.isStreaming && last && !row.message.fromUser
          ? _retry
          : null,
      onOption: !chat.isStreaming && last ? _answer : null,
      draftSections: [
        for (final s in vm.sectionsHere)
          (label: s.label, detail: s.text.trim()),
      ],
    );
  }

  void _retry() {
    final problem = widget.chat.regenerate();
    if (problem != null) showToast(context, problem, warn: true);
  }

  void _answer(String option) {
    final problem = widget.chat.send(option);
    if (problem != null) showToast(context, problem, warn: true);
  }

  Widget _composer() {
    final streaming = widget.chat.isStreaming;
    final quick = widget.config.config.quickActions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quick.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: ScrollStrip(
                visible: _maxSideQuickActions,
                children: [
                  for (final action in quick)
                    PennaButton(
                      label: tr(action.label),
                      background: PennaColors.slate100,
                      onPressed: () => _quick(tr(action.prompt)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (_attachments.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, a) in _attachments.indexed)
                  AttachmentChip(
                    attachment: a,
                    onRemove: () => _removeAttachment(i),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: tr('添加图片或文本文件'),
                onPressed: _pickFiles,
                color: PennaColors.slate500,
                icon: const Icon(Icons.attach_file, size: 17),
              ),
              Expanded(
                child: Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 13),
                    contextMenuBuilder: pennaTextMenu,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: tr('问问工作区里的提示词'),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: PennaColors.slate400,
                      ),
                      filled: true,
                      fillColor: PennaColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: PennaColors.border),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: streaming ? tr('停止') : tr('发送'),
                onPressed: streaming ? widget.chat.stop : _send,
                icon: Icon(
                  streaming
                      ? Icons.stop_circle_outlined
                      : Icons.arrow_circle_up,
                  color: PennaColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
