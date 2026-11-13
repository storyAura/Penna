import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 吉祥物的几张图(用户给的像素画,去了白底,在 `assets/mascot/`)。
/// 原图里人物在同一处,统一裁切,换图时人不跳。后加的 11 张(2026-11-13)是 2048 见方的原图
/// 缩到 0.246 倍、从 (47, 14) 起裁 417×480,和前六张对齐。
enum MascotLook {
  /// 委屈地张嘴、挂着泪(平时)
  whine,

  /// 笑着挥手
  wave,

  /// 抱着胳膊、撅嘴脸红(哼)
  huff,

  /// 打哈欠、冒「Z」
  yawn,

  /// 坐着托腮打瞌睡
  doze,

  /// 坐着抱膝、撅嘴脸红
  sulk,

  /// 张大嘴吃惊
  gasp,

  /// 叉腰得意
  proud,

  /// 笑着往右指
  point,

  /// 冒汗慌张
  panic,

  /// 手指抵下巴、头顶问号
  think,

  /// 双手举起欢呼
  cheer,

  /// 拿着羽毛笔和本子
  write,

  /// 坐着、手放膝上,醒着
  sit,

  /// 坐着、睁大眼盯着看
  watch,

  /// 坐着比耶、翘脚
  peace,

  /// 坐着抱头 ＞＜
  cower;

  String get asset => 'assets/mascot/$name.png';

  /// 宽 / 高(六张一样)。
  double get aspect => 417 / 480;
}

/// 解码好的图和它的像素(点的地方透明就点穿过去)。
typedef _Picture = ({ui.Image image, ByteData pixels});

final _pictures = <MascotLook, Future<_Picture>>{};

/// 已经解码好的,建部件时直接拿来画,不用等一帧。
final _decoded = <MascotLook, _Picture>{};

Future<_Picture> _load(MascotLook look) =>
    _pictures.putIfAbsent(look, () async {
      final data = await rootBundle.load(look.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return _decoded[look] = (image: image, pixels: pixels!);
    });

/// 先把几张图都解码好(测试里在真的异步里调)。
Future<void> precacheMascot() => Future.wait(MascotLook.values.map(_load));

/// 吉祥物,高 [height]。[bob] 时半秒一拍轻轻上下晃(系统「减少动画」时不晃)。
/// 只有画出来的地方接得到点击。
class PixelMascot extends StatefulWidget {
  const PixelMascot({
    super.key,
    required this.look,
    this.height = 200,
    this.bob = false,
  });

  final MascotLook look;
  final double height;
  final bool bob;

  @override
  State<PixelMascot> createState() => _PixelMascotState();
}

class _PixelMascotState extends State<PixelMascot> {
  Timer? _beat;
  bool _up = false;

  @override
  void initState() {
    super.initState();
    // 几张图一起先解码好,换表情时不闪。
    for (final look in MascotLook.values) {
      if (_decoded.containsKey(look)) continue;
      _load(look).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _beat?.cancel();
    _beat = null;
    if (widget.bob && !MediaQuery.disableAnimationsOf(context)) {
      _beat = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => setState(() => _up = !_up),
      );
    }
  }

  @override
  void dispose() {
    _beat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.height * widget.look.aspect, widget.height);
    final picture = _decoded[widget.look];
    return SizedBox.fromSize(
      size: size,
      child: picture == null
          ? null
          : CustomPaint(
              painter: _Painter(picture, size, _up ? widget.height / 120 : 0),
            ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.picture, this.size, this.lift);

  final _Picture picture;
  final Size size;
  final double lift;

  @override
  void paint(Canvas canvas, Size _) {
    paintImage(
      canvas: canvas,
      rect: Offset(0, -lift) & size,
      image: picture.image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }

  /// 透明的地方点不到她,点穿到底下去。
  @override
  bool hitTest(Offset p) {
    final image = picture.image;
    final x = (p.dx / size.width * image.width).floor();
    final y = ((p.dy + lift) / size.height * image.height).floor();
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return false;
    return picture.pixels.getUint8((y * image.width + x) * 4 + 3) > 40;
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.picture != picture || old.size != size || old.lift != lift;
}
