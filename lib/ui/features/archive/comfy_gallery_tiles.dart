part of 'comfy_gallery.dart';

/// 一天的标题行:箭头、日子、张数,点了收起或展开。
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: Motion.of(context, Motion.snap),
            curve: Motion.swift,
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: PennaColors.slate500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            tr('{0} 张', [count]),
            style: TextStyle(fontSize: 11, color: PennaColors.slate400),
          ),
        ],
      ),
    ),
  );
}

/// 一张图:方形缩略图,下面是时刻和提示词开头;悬停看整条提示词。
class _Tile extends StatelessWidget {
  const _Tile({
    required this.shot,
    required this.url,
    required this.headers,
    required this.onOpen,
    required this.onMenu,
    this.row = false,
    this.busy = false,
  });

  /// 正在读原图(点开大图之前)。
  final bool busy;

  /// 列表里的一行:左边小缩略图,右边时刻和整条提示词。
  final bool row;
  final ComfyShot shot;
  final String url;
  final Map<String, String> headers;

  /// 点开看大图;参数是「从看清的缩略图点的」(点图片以外的地方是 false)。
  final ValueChanged<bool> onOpen;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final time = shot.time;
    return Tooltip(
      message: shot.prompt.isEmpty ? '${shot.file['filename']}' : shot.prompt,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onOpen(false),
          onSecondaryTapUp: (d) => onMenu(d.globalPosition),
          child: row
              ? _row()
              : PennaCard(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(aspectRatio: 1, child: _image(400)),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (time != null) shortTime(time),
                          if (shot.prompt.isNotEmpty) shot.prompt,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: PennaColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// 缩略图:硬盘上的直接读文件(ComfyUI 没开也看得到),别的让 ComfyUI 压成 WebP 再给。
  Widget _image(int cacheWidth) {
    Widget broken(BuildContext _, Object _, StackTrace? _) =>
        Icon(Icons.broken_image_outlined, color: PennaColors.slate400);
    final path = shot.path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BlurVeil(
            onOpen: () => onOpen(true),
            child: path != null
                ? Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                    errorBuilder: broken,
                  )
                : Image.network(
                    url,
                    headers: headers,
                    fit: BoxFit.cover,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                    errorBuilder: broken,
                  ),
          ),
          if (busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row() {
    final time = shot.time;
    return PennaCard(
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 64, child: _image(160)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (time != null)
                  Text(
                    shortTime(time),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                const SizedBox(height: 2),
                Text(
                  shot.prompt.isEmpty
                      ? '${shot.file['filename']}'
                      : shot.prompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: PennaColors.slate700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
