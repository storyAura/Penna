import 'package:flutter/material.dart';

import 'theme.dart';

/// 两栏之间可左右拖的分割线(工作台、区域控制、漫画分镜共用)。
class PaneSplitter extends StatelessWidget {
  const PaneSplitter({super.key, required this.onDrag});

  /// 这一下往右拖了多少像素(往左是负的)。
  final ValueChanged<double> onDrag;

  static const width = 4.0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Container(
          width: width,
          color: PennaColors.border,
          alignment: Alignment.center,
          child: Container(width: 2, height: 32, color: PennaColors.slate400),
        ),
      ),
    );
  }
}

/// 右边对话栏拖动后的宽度:不窄于 [min],不宽于窗口的一半。
double chatPaneWidth(BuildContext context, double width, double min) =>
    width.clamp(min, (MediaQuery.sizeOf(context).width * 0.5).clamp(min, 2000));
