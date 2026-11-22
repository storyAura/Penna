import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/size_panel.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'layout_board.dart';

export '../../core/size_panel.dart' show aspectLabel, sizePadKey;

/// 顶栏的「分辨率」按钮:点开是一块拖动板(左下角是原点,拖右上角定宽高,
/// 拖上边只改高、拖右边只改宽)和存下的常用尺寸。
class LayoutSizePicker extends StatelessWidget {
  const LayoutSizePicker({super.key, required this.board, required this.snap});

  final LayoutBoard board;

  /// 宽高取它的倍数(设置里的分辨率对齐)。
  final int Function() snap;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: MenuStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStatePropertyAll(PennaColors.card),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PennaColors.border),
        ),
      ),
    ),
    alignmentOffset: const Offset(0, 4),
    menuChildren: [
      // MenuAnchor 自己不带动画:打开时从上往下轻轻浮出,和下拉菜单一致。
      PopIn.popover(
        from: Alignment.topCenter,
        child: ListenableBuilder(
          listenable: board,
          builder: (context, _) => SizePanel(
            size: (width: board.layout.width, height: board.layout.height),
            onSize: (s) => board.setSize(s.width, s.height),
            sizes: board.sizes,
            onSave: board.saveSize,
            onRemove: board.removeSize,
            maxSizes: LayoutBoard.maxSizes,
            snap: snap,
            defaultSize: board.defaultSize,
            onSetDefault: board.setDefaultSize,
          ),
        ),
      ),
    ],
    builder: (context, menu, _) => IconButton(
      tooltip: tr('分辨率'),
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      isSelected: menu.isOpen,
      icon: const Icon(Icons.aspect_ratio),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}
