import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../core/harness/attachment.dart';
import '../../../l10n/l10n.dart';
import '../../core/blur_veil.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// 点对话里的图片看大图:铺满窗口,滚轮缩放、拖着看;能复制到剪贴板,
/// 给了 [onReuse] 时还能直接附到输入框再发一次。点空白处或 Esc 关掉。
/// 给了 [album](同一处的几张,含 [image])时左右两个箭头、← →、左右滑动换前后一张。
/// 出的图、档案库的图给 [shown]:「图片模糊」开着时点图片糊上 / 看清,
/// true 是一开始就看清(从看清的缩略图点开的)。
Future<void> showImageViewer(
  BuildContext context,
  Attachment image, {
  List<Attachment>? album,
  ValueChanged<Attachment>? onReuse,
  bool? shown,
}) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: tr('关闭'),
  barrierColor: Colors.black.withValues(alpha: 0.82),
  transitionDuration: Motion.of(context, Motion.base),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Motion.enter),
    child: child,
  ),
  pageBuilder: (context, _, _) => _Viewer(
    images: _albumWith(image, album),
    index: _indexIn(image, album),
    onReuse: onReuse,
    shown: shown,
  ),
);

/// [image] 在 [album] 里的位置:同一个对象,或同一个文件。找不到算 -1。
int _find(Attachment image, List<Attachment> album) => album.indexWhere(
  (a) => identical(a, image) || (a.file != null && a.file == image.file),
);

/// 大图里能翻的几张;[album] 里找不到 [image] 时只看这一张。
List<Attachment> _albumWith(Attachment image, List<Attachment>? album) =>
    album != null && _find(image, album) >= 0 ? album : [image];

int _indexIn(Attachment image, List<Attachment>? album) =>
    album == null ? 0 : max(_find(image, album), 0);

/// 横着拖多远算滑到前后一张(逻辑像素)。
const _swipeDistance = 60.0;

/// 松手后惯性的阻力系数(0 到 1,越小停得越快)。惯性滑多远 ≈ 速度 ÷ |ln(系数)|,
/// 取最小的正数时快甩也只再滑几个像素,等于松手就停。
const _noGlide = double.minPositive;

/// 把图片放进剪贴板(别的软件里能贴)。成功返回 null,否则是给用户看的原因。
Future<String?> copyImage(Attachment image) async {
  // ponytail: pasteboard 只在 Windows 上写得了图;Linux 上提示复制不了。
  if (!Platform.isWindows) return tr('这个系统上复制不了图片');
  try {
    final png = await toPng(image);
    if (png == null) return tr('读不了这张图');
    await Pasteboard.writeImage(png);
    return null;
  } on PlatformException catch (e) {
    return tr('复制失败:{0}', [e.message ?? e.code]);
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({
    required this.images,
    required this.index,
    this.onReuse,
    this.shown,
  });

  final List<Attachment> images;
  final int index;
  final ValueChanged<Attachment>? onReuse;
  final bool? shown;

  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late int _index = widget.index;

  /// 缩放和拖动的位置;换图时放回原样。
  final _zoom = TransformationController();

  /// 按下时的位置,松手时比一比算不算滑动。
  Offset? _downAt;

  /// 复制完在按钮上说一声:弹窗盖着,底下的提示条看不见。
  String? _note;

  Attachment get _image => widget.images[_index];

  bool get _hasPrev => _index > 0;
  bool get _hasNext => _index < widget.images.length - 1;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  /// 换到前一张(-1)或后一张(1);到头了不动。
  void _step(int by) {
    final to = _index + by;
    if (to < 0 || to >= widget.images.length) return;
    setState(() {
      _index = to;
      _note = null;
      _zoom.value = Matrix4.identity();
    });
  }

  /// 没放大时横着拖过 [_swipeDistance] 算滑动:往左拖看后一张,往右拖看前一张。
  /// 放大了的拖动是在看图的别处,不换。
  void _swiped(Offset up) {
    final down = _downAt;
    _downAt = null;
    if (down == null || _zoom.value.getMaxScaleOnAxis() > 1.01) return;
    final d = up - down;
    if (d.dx.abs() < _swipeDistance || d.dx.abs() < d.dy.abs() * 1.5) return;
    _step(d.dx < 0 ? 1 : -1);
  }

  Future<void> _copy() async {
    final problem = await copyImage(_image);
    if (mounted) setState(() => _note = problem ?? tr('已复制'));
  }

  void _reuse() {
    widget.onReuse!(_image);
    _close();
  }

  /// 右键图片:复制、附到输入框;存在磁盘上的还能在文件夹里找到它。
  Future<void> _menu(Offset at) async {
    final file = _image.file;
    final copy = tr('复制图片'), reuse = tr('附到输入框'), reveal = tr('在文件夹中显示');
    final picked = await popMenu(context, at, [
      copy,
      if (widget.onReuse != null) reuse,
      if (file != null && Platform.isWindows) reveal,
    ]);
    if (picked == copy) return _copy();
    if (picked == reuse) return _reuse();
    if (picked == reveal) {
      await Process.run('explorer', ['/select,', file!]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _image.bytes;
    final shown = widget.shown;
    Widget picture = bytes == null || bytes.isEmpty
        ? _broken()
        : Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _broken(),
          );
    if (shown != null) {
      // 换图时模糊跟着回到一开始的样子。
      picture = BlurVeil(
        key: ValueKey(_index),
        revealed: shown,
        sigma: 60,
        child: picture,
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // 点图片以外的地方关掉;图片自己接住点击,不往下传。
            // 看图的那块(InteractiveViewer)会吃掉点击,所以关掉的手势包在它外面。
            Positioned.fill(
              child: Listener(
                onPointerDown: (e) => _downAt = e.position,
                onPointerUp: (e) => _swiped(e.position),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  // 看图的框铺满窗口,留白放在框里面:放大后图能挪到窗口边上,
                  // 不会在留白那一圈被裁成一个小框。
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    minScale: 0.5,
                    maxScale: 8,
                    // 松手就停,不再顺着惯性滑一段(用户反馈放大后图会漂)。
                    interactionEndFrictionCoefficient: _noGlide,
                    // 触控板两指上下滑也是缩放,和滚轮一样。
                    trackpadScrollCausesScale: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(72, 64, 72, 32),
                      child: Center(
                        child: GestureDetector(
                          onTap: () {},
                          onSecondaryTapUp: (d) => _menu(d.globalPosition),
                          child: picture,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.images.length > 1) ...[
              _arrow(left: true),
              _arrow(left: false),
            ],
            Positioned(top: 14, left: 16, right: 16, child: _toolbar()),
          ],
        ),
      ),
    );
  }

  /// 左右两边的翻页箭头,到头那边变灰。
  Widget _arrow({required bool left}) {
    final enabled = left ? _hasPrev : _hasNext;
    return Positioned(
      left: left ? 16 : null,
      right: left ? null : 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: IconButton(
          tooltip: left ? tr('上一张') : tr('下一张'),
          iconSize: 26,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white24,
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
          ),
          icon: Icon(left ? Icons.chevron_left : Icons.chevron_right),
          onPressed: enabled ? () => _step(left ? -1 : 1) : null,
        ),
      ),
    );
  }

  Widget _broken() =>
      Icon(Icons.broken_image_outlined, size: 48, color: PennaColors.slate400);

  Widget _toolbar() => Material(
    type: MaterialType.transparency,
    child: Row(
      children: [
        Expanded(
          child: Text(
            _image.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        if (widget.images.length > 1) ...[
          Text(
            '${_index + 1} / ${widget.images.length}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(width: 12),
        ],
        if (_note != null) ...[
          Text(
            _note!,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(width: 10),
        ],
        PennaButton(
          label: tr('复制图片'),
          icon: Icons.content_copy,
          onPressed: _copy,
        ),
        if (widget.onReuse != null) ...[
          const SizedBox(width: 6),
          PennaButton(
            label: tr('附到输入框'),
            icon: Icons.attach_file,
            onPressed: _reuse,
          ),
        ],
        const SizedBox(width: 6),
        IconButton(
          tooltip: tr('关闭'),
          iconSize: 18,
          color: Colors.white,
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ],
    ),
  );
}
