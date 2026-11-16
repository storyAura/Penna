import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

/// 用系统默认的程序打开一个文件(视频交给系统的播放器)。
Future<void> openWithSystem(String path) =>
    Process.run(Platform.isWindows ? 'explorer' : 'xdg-open', [path]);

/// ComfyUI 出的视频:深色方块、播放图标和文件名,点了用系统的播放器打开。
// ponytail: 不在 Penna 里播放(Windows / Linux 上的 Flutter 播放器要另带一套 mpv 之类的库);
// 要在窗口里看再接 media_kit。
class ComfyVideoTile extends StatelessWidget {
  const ComfyVideoTile({super.key, required this.path, required this.height});

  final String path;
  final double height;

  @override
  Widget build(BuildContext context) {
    final name = File(path).uri.pathSegments.last;
    return Tooltip(
      message: '$name\n${tr('点击用系统播放器打开')}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => openWithSystem(path),
          child: Container(
            width: height * 16 / 9,
            height: height,
            decoration: BoxDecoration(
              // 不跟深浅色变:视频方块总是深色的。
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_circle_outline,
                  size: (height * 0.3).clamp(16, 56),
                  color: Colors.white,
                ),
                if (height > 60)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
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
