import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/layout.dart';
import '../../../data/services/archive_store.dart';
import '../../../data/services/config_service.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../archive/archive_page.dart';
import '../settings/settings_sections.dart';
import '../studio/activity_bar.dart';
import '../studio/chat_pane.dart';
import '../studio/page_strip.dart';
import '../studio/studio_view_model.dart';
import 'layout_board.dart';
import 'layout_camera.dart';
import 'layout_canvas.dart';
import 'layout_canvas_tools.dart';
import 'layout_fullscreen.dart';
import 'layout_scene_view.dart';
import 'layout_size_picker.dart';
import 'layout_json_view.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'layout_props.dart';

const _propsWidth = 340.0;

/// 镜头停下这么久才算"调好了",提醒按视角改描述。
const _settleDelay = Duration(milliseconds: 1200);
const _chatWidth = 420.0;

/// 区域控制工作台:左边写各块的属性,中间在画布上画框,右边和布局 Agent 对话,
/// 得到 MOSS-Image 的布局 JSON。能存进档案库的「区域控制」分区。
class LayoutPage extends StatefulWidget {
  const LayoutPage({
    super.key,
    required this.board,
    required this.vm,
    required this.chat,
    required this.config,
    required this.archive,
    required this.onOpenStudio,
    required this.onOpenSettings,
  });

  final LayoutBoard board;

  /// 「保存」存进它的「区域控制」分区。
  final ArchiveStore archive;

  /// 工作台:「放到成稿」放进它当前那一页。
  final StudioViewModel vm;

  /// 布局页自己那场对话(`layoutOnly`):和工作台的是两场,界面一样。
  final StudioViewModel chat;
  final ConfigService config;
  final VoidCallback onOpenStudio;
  final VoidCallback onOpenSettings;

  @override
  State<LayoutPage> createState() => _LayoutPageState();
}

class _LayoutPageState extends State<LayoutPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  /// 各块在属性栏里的卡片和正文输入框,按第几块记。
  final _cards = <int, GlobalKey>{};
  final _fields = <int, FocusNode>{};

  LayoutBoard get board => widget.board;

  GlobalKey _cardKey(int i) => _cards.putIfAbsent(i, GlobalKey.new);
  FocusNode _fieldFocus(int i) => _fields.putIfAbsent(i, FocusNode.new);

  /// 镜头调好了(停下一会儿)而描述还是原来视角的,在画布下面提醒一句。
  /// [_lastCamera] 是上次看到的镜头,一变就重新计时;[_answered] 是用户已经回应过
  /// (改了或说先不改)的那个镜头,同一个镜头不再提醒。
  Camera? _lastCamera, _answered;
  Timer? _settle;
  bool _settled = false;

  /// 3D 视图里开着自由摄像机(画布旁边多一个随意转着看的视口)。
  bool _scene = false;

  bool get _stale =>
      _settled && board.cameraMoved && board.layout.camera != _answered;

  @override
  void initState() {
    super.initState();
    board.addListener(_watchCamera);
  }

  void _watchCamera() {
    final c = board.layout.camera;
    if (c == _lastCamera) return;
    _lastCamera = c;
    _settle?.cancel();
    if (_settled) setState(() => _settled = false);
    _settle = Timer(_settleDelay, () {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  void dispose() {
    board.removeListener(_watchCamera);
    _settle?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// 图层面板里展开着的几块(按第几块记);默认都折叠。
  var _open = <int>{};

  void _toggle(int i) => setState(
    () => _open = _open.contains(i) ? ({..._open}..remove(i)) : {..._open, i},
  );

  /// 拖着换前后。序号都变了,展开状态只留给挪动的那一块(它展开着的话)。
  void _move(int from, int to) {
    final wasOpen = _open.contains(from);
    board.move(from, to);
    setState(() => _open = {if (wasOpen) ?board.selected});
  }

  /// 删掉一块:后面的序号往前挪一个,展开状态跟着挪。
  void _delete(int i) {
    board.removeBox(i);
    setState(
      () => _open = {
        for (final j in _open)
          if (j != i) j > i ? j - 1 : j,
      },
    );
  }

  /// 画布上点了第 [i] 块:属性栏滚到它那张卡片;[edit] 时展开它并把光标放进正文。
  void _reveal(int i, {bool edit = false}) {
    if (edit && !_open.contains(i)) setState(() => _open = {..._open, i});
    // 等这一帧建好(刚画出来的框还没有卡片,刚展开的还没有输入框)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final card = _cards[i]?.currentContext;
      if (card == null || !card.mounted) return;
      Scrollable.ensureVisible(card, duration: Motion.base, alignment: 0.05);
      if (edit) _fields[i]?.requestFocus();
    });
  }

  void _toDraft() {
    final problem = widget.vm.restorePrompt((
      time: DateTime.now(),
      text: board.json,
    ), title: tr('区域控制'));
    if (problem != null) return showToast(context, problem, warn: true);
    widget.onOpenStudio();
  }

  /// 「交给 Agent」:照画板现在的形状、视角、灯光、体块写描述(唯一的入口,见 [handOverRequest])。
  void _handOver() {
    setState(() => _answered = board.layout.camera);
    _send(handOverRequest(board));
  }

  /// 对话里放进一张参考图:它和画布一横一竖时,问一句要不要把画布对调
  /// (开了自动审批就直接换)。
  Future<void> _matchImage(Attachment image) async {
    final to = await board.swapFor(image.bytes!);
    if (to == null || !mounted) return;
    final size = '${to.width}×${to.height}';
    if (!widget.config.config.autoApprove &&
        !await confirmDelete(
          context,
          to.width > to.height ? tr('参考图是横构图') : tr('参考图是竖构图'),
          tr('画布换成 {0}?', [size]),
          action: tr('换'),
        )) {
      return;
    }
    board.swap();
    if (mounted) showToast(context, tr('画布已换成 {0}', [size]));
  }

  /// 开 / 关 3D 视图。打开时有体块是程序猜的,问一句要不要让 Agent 估
  /// (开了自动审批直接交给它)。
  Future<void> _toggle3D() async {
    if (board.threeD) {
      // 回平面视图前,镜头转过了而描述没跟着改:确认一次。
      if (board.cameraMoved && board.layout.camera != _answered) {
        final redo = await confirmDelete(
          context,
          tr('视角变了,描述要跟着改吗?'),
          tr('框已按新视角算好,描述里的朝向和位置关系还是原来的。'),
          action: tr('交给 Agent'),
        );
        if (!mounted) return;
        redo ? _handOver() : setState(() => _answered = board.layout.camera);
      }
      return board.setThreeD(false);
    }
    board.setThreeD(true);
    if (!board.guessedBodies) return;
    if (!widget.config.config.autoApprove &&
        !await confirmDelete(
          context,
          tr('让 Agent 估体块?'),
          tr('有几块的远近、厚度、朝向是按图层猜的。'),
          action: tr('估'),
        )) {
      return;
    }
    _handOver();
  }

  void _send(String text) {
    final problem = widget.chat.send(text);
    if (problem != null) showToast(context, problem, warn: true);
  }

  /// 画布区:开着自由摄像机时和视口按画布比例摆成上下或左右两块。
  Widget _canvasArea() {
    final canvas = LayoutCanvas(
      board: board,
      onPick: _reveal,
      onEdit: (i) => _reveal(i, edit: true),
    );
    if (!board.threeD || !_scene) return canvas;
    final l = board.layout;
    return SceneSplit(
      aspect: l.width / l.height,
      canvas: canvas,
      scene: SceneView(board: board),
    );
  }

  /// 带着这一块去对话里:输入框上方出现它,接着打字说怎么改。
  void _discuss(int i) {
    final b = board.layout.boxes[i];
    final name = b.name.trim().isEmpty ? tr('第 {0} 块', [i + 1]) : b.name.trim();
    widget.chat.quoteSection(
      '【$name】${b.label} · x ${b.left} y ${b.top} · '
      '${b.width}×${b.height}\n${b.caption.trim()}',
    );
    _inputFocus.requestFocus();
  }

  /// 快捷操作:接在输入框已有的话后面,不替换。
  void _appendInput(String text) {
    final had = _input.text.trimRight();
    final next = had.isEmpty ? text : '$had $text';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: PennaColors.border);
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) => ColoredBox(
        color: PennaColors.editorBg,
        child: Column(
          children: [
            _TopBar(
              board: board,
              archive: widget.archive,
              title: () => widget.chat.pageName,
              snap: () => widget.config.config.layoutSnap,
              onToggle3D: _toggle3D,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 给收起的操作记录留出窄边;展开时它盖在属性栏上,不挤画布。
                        SizedBox(width: ActivityBar.widthOf(open: false)),
                        Container(
                          width: _propsWidth,
                          decoration: BoxDecoration(
                            color: PennaColors.bg,
                            border: Border(right: side),
                          ),
                          child: _Properties(
                            board: board,
                            config: widget.config,
                            onDiscuss: _discuss,
                            onToDraft: _toDraft,
                            cardKey: _cardKey,
                            fieldFocus: _fieldFocus,
                            isOpen: _open.contains,
                            onToggle: _toggle,
                            onMove: _move,
                            onDelete: _delete,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 各系列、各页,同工作台的成稿区;每页是一张布局。
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  0,
                                ),
                                child: ListenableBuilder(
                                  listenable: widget.chat,
                                  builder: (context, _) => PageStrip(
                                    vm: widget.chat,
                                    label: tr('布局'),
                                    tips: false,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          24,
                                          48,
                                          24,
                                          24,
                                        ),
                                        child: _canvasArea(),
                                      ),
                                    ),
                                    // 形状工具、自由摄像机、全屏。
                                    Positioned(
                                      top: 6,
                                      left: 24,
                                      right: 0,
                                      child: CanvasTools(
                                        board: board,
                                        scene: _scene,
                                        onScene: () =>
                                            setState(() => _scene = !_scene),
                                        onFullscreen: () => showFullCanvas(
                                          context,
                                          board: board,
                                          onToggle3D: _toggle3D,
                                        ),
                                        onHandOver: _handOver,
                                      ),
                                    ),
                                    if (_stale)
                                      Positioned(
                                        left: 16,
                                        right: 16,
                                        bottom: 12,
                                        child: Center(
                                          child: _StaleViewNote(
                                            onHandOver: _handOver,
                                            onLater: () => setState(
                                              () => _answered =
                                                  board.layout.camera,
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
                        // 3D 视图的摄像机一栏贴在画布右边,不盖住画布。
                        if (board.threeD) CameraPanel(board: board),
                        Container(
                          width: _chatWidth,
                          decoration: BoxDecoration(border: Border(left: side)),
                          child: ListenableBuilder(
                            listenable: Listenable.merge([
                              widget.chat,
                              widget.config,
                            ]),
                            builder: (context, _) => ChatPane(
                              vm: widget.chat,
                              config: widget.config,
                              input: _input,
                              inputFocus: _inputFocus,
                              onQuickAction: _appendInput,
                              onOpenSettings: widget.onOpenSettings,
                              onImage: _matchImage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 操作记录:画板上的改动、换页都记在区域控制那场对话上,能回滚。
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: ListenableBuilder(
                      listenable: widget.chat,
                      builder: (context, _) => ActivityBar(vm: widget.chat),
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

/// 画布下面的提醒:镜头调好了,描述还是原来视角的。按钮就是统一的「交给 Agent」。
class _StaleViewNote extends StatelessWidget {
  const _StaleViewNote({required this.onHandOver, required this.onLater});

  final VoidCallback onHandOver, onLater;

  @override
  Widget build(BuildContext context) => Material(
    color: PennaColors.card,
    elevation: 6,
    shadowColor: const Color(0x33000000),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PennaColors.primaryBorder),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Icon(Icons.info_outline, size: 16, color: PennaColors.primary),
          Text(
            tr('视角变了,描述还是原来的'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          FilledButton.icon(
            onPressed: onHandOver,
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(tr('交给 Agent'), style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: PennaColors.primary,
            ),
          ),
          TextButton(
            onPressed: onLater,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(tr('先不改'), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.board,
    required this.archive,
    required this.title,
    required this.snap,
    required this.onToggle3D,
  });

  final LayoutBoard board;
  final ArchiveStore archive;

  /// 眼前这页的名字,存档案库时先填进名称。
  final String Function() title;

  /// 画布宽高取它的倍数(「设置 → 软件设置」的分辨率对齐)。
  final int Function() snap;
  final VoidCallback onToggle3D;

  /// 把整张布局(连同画布尺寸和各块的名字)存进档案库的「区域控制」分区。
  Future<void> _save(BuildContext context) async {
    final picked = await showSaveDialog(
      context,
      archive.categoriesOf(archiveLayout),
      title: title(),
    );
    if (picked == null) return;
    archive.add(
      text: jsonEncode(board.layout.toJson()),
      title: picked.title,
      category: picked.category,
      kind: archiveLayout,
    );
    if (context.mounted) showToast(context, tr('已存进档案库'));
  }

  @override
  Widget build(BuildContext context) {
    final l = board.layout;
    void resize(int? w, int? h) {
      final want = (width: w ?? l.width, height: h ?? l.height);
      if (want.width < minLayoutSide ||
          want.width > maxLayoutSide ||
          want.height < minLayoutSide ||
          want.height > maxLayoutSide) {
        showToast(
          context,
          tr('边长要在 {0} 到 {1} 之间', [minLayoutSide, maxLayoutSide]),
          warn: true,
        );
        return;
      }
      // 对齐到设置里的倍数(默认 16,MOSS-Image 的要求),并说一声。
      final step = snap();
      final got = (
        width: snapLayoutSide(want.width, step),
        height: snapLayoutSide(want.height, step),
      );
      board.setSize(got.width, got.height);
      if (got != want) {
        showToast(
          context,
          tr('已对齐到 {0} 的倍数:{1}×{2}', [step, got.width, got.height]),
        );
      }
    }

    return PennaBar(
      color: PennaColors.card,
      children: [
        Icon(Icons.crop_free, size: 15, color: PennaColors.primary),
        const SizedBox(width: 6),
        Text(
          tr('区域控制工作台'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 16),
        _SideField(
          value: l.width,
          tooltip: tr('宽'),
          onSubmit: (v) => resize(v, null),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('×', style: TextStyle(color: PennaColors.slate500)),
        ),
        _SideField(
          value: l.height,
          tooltip: tr('高'),
          onSubmit: (v) => resize(null, v),
        ),
        IconButton(
          tooltip: tr('横竖对调'),
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.swap_horiz),
          onPressed: board.swap,
        ),
        LayoutSizePicker(board: board, snap: snap),
        const SizedBox(width: 4),
        _PerspectiveButton(board: board),
        const SizedBox(width: 4),
        Tooltip(
          message: board.threeD ? tr('回到平面视图') : tr('3D 视图'),
          child: PennaChip(
            label: '3D',
            selected: board.threeD,
            onTap: onToggle3D,
          ),
        ),
        const Spacer(),
        const SizedBox(width: 6),
        PennaButton(
          label: tr('保存'),
          icon: Icons.save_outlined,
          borderColor: PennaColors.border,
          onPressed: l.isEmpty ? null : () => _save(context),
        ),
        const SizedBox(width: 6),
        // 和工作区顶栏的「清空」同一个样子。
        PennaButton(
          label: tr('清空'),
          icon: Icons.cleaning_services_outlined,
          borderColor: PennaColors.border,
          onPressed: l.isEmpty
              ? null
              : () async {
                  if (await confirmDelete(
                    context,
                    tr('清空区域控制?'),
                    tr('框和描述都会清掉,画布尺寸留着。'),
                  )) {
                    board.clear();
                  }
                },
        ),
      ],
    );
  }
}

/// 透视辅助的开关:点开选一点、两点、三点透视,或关掉。默认关。
class _PerspectiveButton extends StatelessWidget {
  const _PerspectiveButton({required this.board});

  final LayoutBoard board;

  @override
  Widget build(BuildContext context) {
    final on = board.layout.perspective;
    final names = {1: tr('一点透视'), 2: tr('两点透视'), 3: tr('三点透视')};
    return PopupMenuButton<int>(
      tooltip: tr('透视辅助'),
      position: PopupMenuPosition.under,
      onSelected: (n) => board.setPerspective(n == 0 ? null : n),
      itemBuilder: (_) => [
        for (final MapEntry(key: n, value: name) in names.entries)
          CheckedPopupMenuItem(
            value: n,
            checked: on?.points == n,
            height: 34,
            child: Text(name, style: const TextStyle(fontSize: 12.5)),
          ),
        if (on != null) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 0,
            height: 34,
            child: Text(tr('关闭'), style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ],
      child: PennaChip(
        label: on == null ? tr('透视') : names[on.points]!,
        selected: on != null,
        onTap: null,
      ),
    );
  }
}

/// 一条边长的输入框:回车或离开时才生效;外面改了尺寸(对调、点了存的尺寸)跟着变。
class _SideField extends StatefulWidget {
  const _SideField({
    required this.value,
    required this.tooltip,
    required this.onSubmit,
  });

  final int value;
  final String tooltip;
  final ValueChanged<int?> onSubmit;

  @override
  State<_SideField> createState() => _SideFieldState();
}

class _SideFieldState extends State<_SideField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(_SideField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _controller.text = '${widget.value}';
  }

  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == widget.value) return;
    widget.onSubmit(v ?? 0);
    // 没换成(超出范围):把原来的数放回去。
    if (mounted) _controller.text = '${widget.value}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: PennaColors.border),
    );
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox(
        width: 64,
        child: TextField(
          contextMenuBuilder: pennaTextMenu,
          controller: _controller,
          focusNode: _focus,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: PennaColors.card,
            contentPadding: const EdgeInsets.symmetric(vertical: 7),
            border: border,
            enabledBorder: border,
          ),
        ),
      ),
    );
  }
}
