import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/comfy_workflow.dart';
import '../../../data/models/app_config.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// 侧栏里的「LoRA 语法」框。
///
/// 它不关心这段文字存在哪里:工作流里写着 `{{lora}}` 时由设置保存，
/// 否则就直接改那个喂给 LoraManager 的文本节点——都通过 [onChanged] 交出去。
///
/// 每条前面有个开关:关掉的从语法里摘出来，记在 [rows] 的 `on: false` 里，
/// 位置不动、权重留着，再点一下就原样加回去。
/// 鼠标停在名字上，面板里会浮出它在 Lora Manager 里的预览图。
class LoraSyntaxEditor extends StatefulWidget {
  const LoraSyntaxEditor({
    super.key,
    required this.text,
    required this.rows,
    required this.onChanged,
    required this.onToggle,
    required this.onOffStrength,
    required this.onForget,
    this.previewOf,
    this.imageHeaders = const {},
  });

  /// 现在这段语法(只含开着的)。
  final String text;

  /// 显示用的条目，已按展示顺序排好;`on` 是开没开。
  final List<LoraSetting> rows;

  /// 改完之后交给外面保存(值已经收拢成标准写法)。
  final ValueChanged<String> onChanged;

  /// 开/关一条。
  final void Function(String name, bool on) onToggle;

  /// 改一条关掉的 LoRA 的权重。
  final void Function(String name, double strength) onOffStrength;

  /// 把一条关掉的彻底删掉。
  final void Function(String name) onForget;

  /// 查这条 LoRA 的预览图地址(完整 http 地址;查不到给空串)。
  final Future<String> Function(String name)? previewOf;

  /// 预览图要带的请求头(云端 ComfyUI 的 Key)。
  final Map<String, String> imageHeaders;

  @override
  State<LoraSyntaxEditor> createState() => _LoraSyntaxEditorState();
}

class _LoraSyntaxEditorState extends State<LoraSyntaxEditor> {
  late final TextEditingController _text;
  final _focus = FocusNode();

  /// 正在悬停的那条、它的预览图(查过的存着，不再重复请求)。
  String? _hover;
  final _previews = <String, String>{};

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.text);
    _text.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(LoraSyntaxEditor old) {
    super.didUpdateWidget(old);
    // 外面换了内容(比如切了工作流、点了开关)时跟着换;正在打字时不打断。
    if (!_focus.hasFocus && widget.text != _text.text) {
      _text.text = widget.text;
    }
  }

  @override
  void dispose() {
    _text.removeListener(_onChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  /// 收拢成标准写法后交出去。
  void _write(String text) {
    final next = loraSyntaxNormalize(text);
    widget.onChanged(next);
    if (next != _text.text) {
      _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  Future<void> _enter(String name) async {
    final load = widget.previewOf;
    if (load == null) return;
    setState(() => _hover = name);
    if (_previews.containsKey(name)) return;
    String url;
    try {
      url = await load(name);
    } on Object {
      url = '';
    }
    _previews[name] = url;
    if (!mounted || _hover != name) return;
    setState(() {});
  }

  void _leave(String name) {
    if (_hover != name) return;
    setState(() => _hover = null);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.rows.where((r) => r.on).length;
    final off = widget.rows.length - on;
    final preview = _previews[_hover ?? ''] ?? '';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('LoRA 语法'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PennaColors.slate500,
                    ),
                  ),
                ),
                _iconButton(
                  icon: Icons.copy_all_outlined,
                  tip: tr('复制'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: _text.text));
                    if (context.mounted) showToast(context, tr('已复制'));
                  },
                ),
                _iconButton(
                  icon: Icons.cleaning_services_outlined,
                  tip: tr('清空'),
                  onTap: () => _write(''),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _text,
              focusNode: _focus,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: PennaColors.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PennaColors.editorBg,
                hintText: '<lora:名字:0.75> <lora:另一个:0.3>',
                hintStyle: TextStyle(
                  fontSize: 10.5,
                  color: PennaColors.slate400,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: PennaColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: PennaColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: PennaColors.primary),
                ),
              ),
              onSubmitted: _write,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  off == 0
                      ? tr('共 {0} 条', [on])
                      : tr('共 {0} 条 · 关 {1}', [on, off]),
                  style: TextStyle(fontSize: 10.5, color: PennaColors.slate500),
                ),
                const Spacer(),
                PennaButton(
                  label: tr('应用'),
                  foreground: PennaColors.primary,
                  onPressed: () => _write(_text.text),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final r in widget.rows)
              _row(name: r.name, strength: r.strength, on: r.on),
          ],
        ),
        // 悬停预览:浮在面板里，不改变布局。
        if (preview.isNotEmpty)
          Positioned(
            right: 0,
            top: 76,
            child: IgnorePointer(
              child: Container(
                width: 150,
                decoration: BoxDecoration(
                  color: PennaColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PennaColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Image.network(
                        preview,
                        headers: widget.imageHeaders,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, _, _) => Container(
                          color: PennaColors.editorBg,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 18,
                            color: PennaColors.slate400,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Text(
                        loraDisplayName(_hover ?? ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: PennaColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tip,
    required VoidCallback onTap,
  }) => IconButton(
    tooltip: tip,
    iconSize: 14,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    color: PennaColors.slate500,
    icon: Icon(icon),
    onPressed: onTap,
  );

  /// 那条 LoRA 前面的开关(和 Lora Manager 里一样的小方块)。
  Widget _toggle({required bool on, required VoidCallback onTap}) => Tooltip(
    message: tr(on ? '关掉' : '打开'),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        width: 15,
        height: 15,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? PennaColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: on ? PennaColors.primary : PennaColors.slate400,
            width: 1.2,
          ),
        ),
        child: on
            ? const Icon(Icons.check, size: 11, color: Colors.white)
            : null,
      ),
    ),
  );

  Widget _row({
    required String name,
    required double strength,
    required bool on,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        _toggle(on: on, onTap: () => widget.onToggle(name, !on)),
        const SizedBox(width: 5),
        Expanded(
          child: MouseRegion(
            onEnter: (_) => _enter(name),
            onExit: (_) => _leave(name),
            child: Text(
              loraDisplayName(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: on ? PennaColors.text : PennaColors.slate400,
              ),
            ),
          ),
        ),
        _step(
          icon: Icons.remove,
          onTap: () => _strength(name, strength - 0.05, on),
        ),
        SizedBox(
          width: 34,
          child: Text(
            strength.toStringAsFixed(2),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: on ? PennaColors.slate700 : PennaColors.slate400,
            ),
          ),
        ),
        _step(
          icon: Icons.add,
          onTap: () => _strength(name, strength + 0.05, on),
        ),
        _iconButton(
          icon: Icons.close,
          tip: tr(on ? '删除' : '移除记录'),
          onTap: () {
            if (on) {
              _write(loraSyntaxRemove(_text.text, name));
            } else {
              widget.onForget(name);
            }
          },
        ),
      ],
    ),
  );

  void _strength(String name, double value, bool on) {
    final v = value.clamp(0, 2).toDouble();
    if (on) {
      _write(loraSyntaxSet(_text.text, name, v));
    } else {
      widget.onOffStrength(name, v);
    }
  }

  Widget _step({required IconData icon, required VoidCallback onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 13, color: PennaColors.slate500),
        ),
      );
}

/// 列表里显示的名字:去掉目录和后缀。
String loraDisplayName(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  return base.replaceFirst(RegExp(r'\.(safetensors|ckpt|pt|pth|bin)$'), '');
}
