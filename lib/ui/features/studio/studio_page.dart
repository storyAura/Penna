import 'package:flutter/material.dart';

import '../../../data/services/archive_store.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import 'activity_bar.dart';
import 'comfy_bar.dart';
import 'chat_pane.dart';
import 'prompt_pane.dart';
import 'studio_view_model.dart';

const _splitterWidth = 4.0;
const _minSplit = 0.3;
const _maxSplit = 0.7;

/// 工作台:左成稿 + 可拖分割线 + 右对话。
// ponytail: 小窗不折叠成页签,靠 windows/runner/win32_window.cpp 里的最小窗口尺寸
// (1100x700)兜底;要支持更小的窗口时再做页签降级。
class StudioPage extends StatefulWidget {
  const StudioPage({
    super.key,
    required this.vm,
    required this.config,
    required this.archive,
    required this.onOpenSettings,
    this.onOpenLayout,
    this.inbox,
  });

  final StudioViewModel vm;
  final ArchiveStore archive;
  final ConfigService config;
  final VoidCallback onOpenSettings;

  /// 切到区域控制工作台。
  final VoidCallback? onOpenLayout;

  /// 别的页面交过来的话(比如本地反推的结果):收到就填进聊天输入框。
  final ValueNotifier<String?>? inbox;

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final _changes = Listenable.merge([widget.vm, widget.config]);
  double _split = 0.53;

  @override
  void initState() {
    super.initState();
    widget.inbox?.addListener(_takeInbox);
  }

  /// 收下别的页面交过来的话。这时工作台可能还没切到前面(拿不到焦点),等下一帧再填。
  void _takeInbox() {
    final text = widget.inbox?.value;
    if (text == null) return;
    widget.inbox!.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fillInput(text);
    });
  }

  @override
  void dispose() {
    widget.inbox?.removeListener(_takeInbox);
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 把快捷指令填进输入框,光标放到末尾并聚焦,方便接着打字。
  void _fillInput(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocus.requestFocus();
  }

  /// 快捷操作:接在输入框已有的话后面(中间空一格),不替换。
  void _appendInput(String text) {
    final had = _input.text.trimRight();
    _fillInput(had.isEmpty ? text : '$had $text');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // ComfyUI 侧栏的窄边只从对话栏里扣,工作区宽度不变。
        final usable =
            box.maxWidth - _splitterWidth - ActivityBar.widthOf(open: false);
        return ListenableBuilder(
          listenable: _changes,
          builder: (context, _) => Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    // 给收起的操作记录留出窄边;展开时它盖在成稿栏上,不挤别的(同区域控制页)。
                    SizedBox(width: ActivityBar.widthOf(open: false)),
                    SizedBox(
                      width: usable * _split,
                      child: PromptPane(
                        vm: widget.vm,
                        archive: widget.archive,
                        // 选中一段后直接去输入框打字。
                        onDiscuss: (section) {
                          widget.vm.quoteSection(section);
                          _inputFocus.requestFocus();
                        },
                      ),
                    ),
                    _Splitter(
                      onDrag: (dx) => setState(() {
                        _split = (_split + dx / usable).clamp(
                          _minSplit,
                          _maxSplit,
                        );
                      }),
                    ),
                    Expanded(
                      child: ChatPane(
                        vm: widget.vm,
                        config: widget.config,
                        input: _input,
                        inputFocus: _inputFocus,
                        onQuickAction: _appendInput,
                        onOpenSettings: widget.onOpenSettings,
                        onOpenLayout: widget.onOpenLayout,
                      ),
                    ),
                    // 给收起的 ComfyUI 侧栏留出窄边;展开时它盖在对话栏上。
                    const SizedBox(width: ComfyBar.closedWidth),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: ActivityBar(vm: widget.vm),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: ComfyBar(runner: widget.vm.comfy, config: widget.config),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Splitter extends StatelessWidget {
  const _Splitter({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Container(
          width: _splitterWidth,
          color: PennaColors.border,
          alignment: Alignment.center,
          child: Container(width: 2, height: 32, color: PennaColors.slate400),
        ),
      ),
    );
  }
}
