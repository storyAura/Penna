import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../../l10n/l10n.dart';
import 'motion.dart';

/// 底部的小提示。[warn] 用于"没法这么做"的提醒,图标不同。
void showToast(BuildContext context, String message, {bool warn = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        width: 380,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(
              warn ? Icons.info_outline : Icons.check_circle,
              size: 16,
              color: warn ? PennaColors.amber : const Color(0xFF34D399),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// 历史列表里用的短时间,例如「10-08 14:28」。
String shortTime(DateTime t) {
  String two(int n) => '$n'.padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 按下时缩一下、松手时弹回来。
class Bouncy extends StatefulWidget {
  const Bouncy({super.key, required this.child});

  final Widget child;

  @override
  State<Bouncy> createState() => _BouncyState();
}

class _BouncyState extends State<Bouncy> {
  bool _down = false;

  void _set(bool down) {
    // 按着的时候组件被移除(比如 diff 块消失),松手事件仍会送到这里。
    if (mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      // 按下轻轻一缩,松手稍微回弹一下就停,不像果冻那样来回晃。
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: Motion.of(
          context,
          _down ? Motion.fast : const Duration(milliseconds: 450),
        ),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// 出现时从下方轻轻弹入。[animate] 为 false 时直接显示(用于滚回视野的旧内容)。
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.animate = true});

  final Widget child;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: Motion.of(context, Motion.sheet),
      curve: Motion.enter,
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// 可选中的小药丸,用来代替 Material 自带的 Chip。
class PennaChip extends StatelessWidget {
  const PennaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// 为 null 时不接点击(套在 PopupMenuButton 里,让它来接)。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PennaColors.primary : PennaColors.slate700;
    return Bouncy(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.base,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? PennaColors.primaryBg : PennaColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? PennaColors.primaryBorder
                    : PennaColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 14, color: color),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> copyWithToast(
  BuildContext context,
  String text,
  String message,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } on PlatformException catch (e) {
    if (context.mounted) {
      showToast(context, tr('复制失败:{0}', [e.message ?? e.code]));
    }
    return;
  }
  if (context.mounted) showToast(context, message);
}

const pennaButtonText = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

/// 一排 [PennaButton](都带图标,间隔 [gap])完整显示要多宽;放不下时可以改成只显示图标。
double pennaButtonsWidth(
  BuildContext context,
  Iterable<String> labels, {
  double gap = 6,
}) {
  var width = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(pennaButtonText),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // 左右内边距 10 + 10,图标 14,图标和字之间 4。
    width += painter.width + 38 + gap;
    painter.dispose();
  }
  return width;
}

/// 原型里的小号圆角按钮;[onPressed] 为 null 时显示为禁用。
class PennaButton extends StatelessWidget {
  const PennaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.background,
    this.foreground,
    this.borderColor,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// 默认是卡片底色 / 深灰字(随配色变)。
  final Color? background;
  final Color? foreground;
  final Color? borderColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Bouncy(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: background ?? PennaColors.card,
          foregroundColor: foreground ?? PennaColors.slate700,
          disabledBackgroundColor: PennaColors.slate100,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          // 桌面上默认是紧凑密度,会把上下内边距各减 8,字就贴着边框了。
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: borderColor == null
                ? BorderSide.none
                : BorderSide(color: borderColor!),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 14),
            // label 为空时只有图标(放不下时的紧凑样子)。
            if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
            if (label.isNotEmpty) Text(label, style: pennaButtonText),
          ],
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

const pennaBarHeight = 48.0;

/// 面板顶部/底部的横条。
class PennaBar extends StatelessWidget {
  const PennaBar({
    super.key,
    required this.children,
    this.color,
    this.borderOnTop = false,
  });

  final List<Widget> children;
  final Color? color;
  final bool borderOnTop;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(color: PennaColors.border);
    // 高度固定:并排的几栏(工作区和对话)顶栏的底边才对得齐。
    return Container(
      height: pennaBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color ?? PennaColors.slate50,
        border: borderOnTop ? Border(top: side) : Border(bottom: side),
      ),
      child: Row(children: children),
    );
  }
}

class PennaCard extends StatelessWidget {
  const PennaCard({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.radius = 8,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? PennaColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? PennaColors.border),
      ),
      child: child,
    );
  }
}

/// 带标题的输入框。初始值只在创建时读一次,之后由用户输入驱动;
/// 要换成另一条数据时给它一个不同的 key。
class PennaField extends StatefulWidget {
  const PennaField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
    this.focusNode,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final FocusNode? focusNode;

  /// 机密字段:默认打码,可点眼睛查看。
  final bool obscure;
  final int maxLines;

  @override
  State<PennaField> createState() => _PennaFieldState();
}

class _PennaFieldState extends State<PennaField> {
  late final _controller = TextEditingController(text: widget.value);
  bool _hidden = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: PennaColors.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PennaColors.slate500,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          contextMenuBuilder: pennaTextMenu,
          controller: _controller,
          focusNode: widget.focusNode,
          onChanged: widget.onChanged,
          obscureText: widget.obscure && _hidden,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          style: const TextStyle(fontSize: 13, height: 1.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: PennaColors.card,
            hintText: widget.hint,
            hintStyle: TextStyle(color: PennaColors.slate400),
            contentPadding: const EdgeInsets.all(10),
            border: border,
            enabledBorder: border,
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? tr('显示') : tr('隐藏'),
                    iconSize: 16,
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// 对话里的圆头像。[path] 是用户在设置里选的图片,空串或读不了时用默认的:
/// Agent 是黑色羽毛笔,用户是小人。
class PennaAvatar extends StatelessWidget {
  const PennaAvatar({
    super.key,
    required this.fromUser,
    required this.path,
    this.size = 32,
  });

  final bool fromUser;
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = fromUser
        ? ColoredBox(
            color: PennaColors.slate100,
            child: Icon(
              Icons.person,
              size: size * 0.62,
              color: PennaColors.slate500,
            ),
          )
        : Image.asset('assets/avatar.png', fit: BoxFit.cover);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: PennaColors.border),
      ),
      child: path.trim().isEmpty
          ? fallback
          : Image.file(
              File(path.trim()),
              fit: BoxFit.cover,
              cacheWidth: 128,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

Map<ContextMenuButtonType, (String, IconData)> get _menuItems => {
  ContextMenuButtonType.cut: (tr('剪切'), Icons.content_cut),
  ContextMenuButtonType.copy: (tr('复制'), Icons.content_copy),
  ContextMenuButtonType.paste: (tr('粘贴'), Icons.content_paste),
  ContextMenuButtonType.selectAll: (tr('全选'), Icons.select_all),
  ContextMenuButtonType.delete: (tr('删除'), Icons.delete_outline),
};

/// 文字上的右键菜单:系统那几项换成中文,样子和别处的弹出菜单一致。
/// [extra] 是选中了文字才有的几项(名字、图标、要做的事),和系统那几项之间隔一条线。
Widget pennaTextMenu(
  BuildContext context,
  EditableTextState state, {
  List<(String, IconData, VoidCallback)> extra = const [],
}) {
  Widget row(String label, IconData icon, VoidCallback? run) => InkWell(
    onTap: run,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 15, color: PennaColors.slate500),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: PennaColors.text)),
        ],
      ),
    ),
  );
  final system = [
    for (final item in state.contextMenuButtonItems)
      if (_menuItems[item.type] case (final label, final icon))
        row(label, icon, item.onPressed),
  ];
  final more = [
    if (!state.textEditingValue.selection.isCollapsed)
      for (final (label, icon, run) in extra)
        row(label, icon, () {
          ContextMenuController.removeAny();
          run();
        }),
  ];
  if (system.isEmpty && more.isEmpty) return const SizedBox.shrink();
  return CustomSingleChildLayout(
    delegate: DesktopTextSelectionToolbarLayoutDelegate(
      anchor: state.contextMenuAnchors.primaryAnchor,
    ),
    child: Material(
      color: PennaColors.card,
      elevation: 8,
      shadowColor: const Color(0x330F172A),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: PennaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 148),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...system,
                if (system.isNotEmpty && more.isNotEmpty)
                  Divider(height: 9, color: PennaColors.border),
                ...more,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 问用户要一个名字。点「确定」返回文字(可以是空串),取消返回 null。
Future<String?> askName(
  BuildContext context,
  String title,
  String initial, {
  String? hint,
}) {
  var text = initial;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 320,
        child: PennaField(
          label: tr('名字'),
          hint: hint ?? tr('留空就用默认的'),
          value: initial,
          onChanged: (v) => text = v,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, text),
          child: Text(tr('确定')),
        ),
      ],
    ),
  );
}

/// 在鼠标的位置弹一个小菜单,返回选中的那一项。
/// [at] 是窗口坐标;菜单按弹窗层自己的坐标放(它在标题栏下面,还可能被「界面大小」放大过)。
Future<String?> popMenu(BuildContext context, Offset at, List<String> items) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final p = overlay.globalToLocal(at);
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(p.dx, p.dy, p.dx, p.dy),
    items: [
      for (final item in items)
        PopupMenuItem(
          value: item,
          height: 34,
          child: Text(item, style: const TextStyle(fontSize: 13)),
        ),
    ],
  );
}
