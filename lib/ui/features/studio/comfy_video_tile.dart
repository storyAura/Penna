import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import 'comfy_video_player.dart';

/// ComfyUI 出的视频:深色方块、播放图标和文件名,点了在 Penna 里播放([showVideoPlayer])。
// ponytail: 方块上不显示视频的第一帧(要先解码一帧);嫌认不出是哪个时再加缩略图。
class ComfyVideoTile extends StatelessWidget {
  const ComfyVideoTile({super.key, required this.path, required this.height});

  final String path;
  final double height;

  @override
  Widget build(BuildContext context) {
    final name = File(path).uri.pathSegments.last;
    return Tooltip(
      message: '$name\n${tr('点击播放')}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showVideoPlayer(context, path),
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
