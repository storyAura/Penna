import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../l10n/l10n.dart';
import 'layout_board.dart';
import 'layout_camera.dart';
import 'layout_canvas.dart';
import '../../core/motion.dart';

/// 全屏摆放:画布(3D 视图时连同摄像机栏)铺满整个软件窗口,属性栏、对话、左边的
/// 图标栏都先让开,方便转镜头、挪框。标题栏还在(窗口的按钮要能点)。Esc 或「退出全屏」回去;
/// 自由镜头开着时 Esc 先退自由镜头(画布先接住它)。画板是同一个,改了什么回去都在。
Future<void> showFullCanvas(
  BuildContext context, {
  required LayoutBoard board,
  required VoidCallback onToggle3D,
}) => showGeneralDialog(
  context: context,
  barrierDismissible: false,
  barrierLabel: tr('全屏摆放'),
  transitionDuration: Motion.of(context, Motion.snap),
  pageBuilder: (context, _, _) =>
      _FullCanvas(board: board, onToggle3D: onToggle3D),
);

class _FullCanvas extends StatelessWidget {
  const _FullCanvas({required this.board, required this.onToggle3D});

  final LayoutBoard board;
  final VoidCallback onToggle3D;

  @override
  Widget build(BuildContext context) {
    void close() => Navigator.of(context).pop();
    return Material(
      color: PennaColors.editorBg,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
        child: Focus(
          autofocus: true,
          child: ListenableBuilder(
            listenable: board,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PennaBar(
                  color: PennaColors.card,
                  children: [
                    Icon(
                      Icons.fullscreen,
                      size: 16,
                      color: PennaColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('全屏摆放'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: board.threeD ? tr('回到平面视图') : tr('3D 视图'),
                      child: PennaChip(
                        label: '3D',
                        selected: board.threeD,
                        onTap: onToggle3D,
                      ),
                    ),
                    const Spacer(),
                    PennaButton(
                      label: tr('退出全屏'),
                      icon: Icons.fullscreen_exit,
                      borderColor: PennaColors.border,
                      onPressed: close,
                    ),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: LayoutCanvas(board: board),
                        ),
                      ),
                      if (board.threeD) CameraPanel(board: board),
                    ],
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
