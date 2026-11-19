import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'motion.dart';

/// 「图片模糊」开着没有(`AppConfig.blurImages`,默认关;`applyLook` 和 `LookSwitcher` 跟着设置改)。
final blurImages = ValueNotifier(false);

/// 出的图、档案库的图外面罩的一层:「图片模糊」开着时先糊着,点一下看清,再点一下糊回去。
/// 只是显示上的处理,图片文件不动。原来点一下做的事([onOpen],看大图)
/// 关着时照旧,开着时挪到看清之后右上角的按钮上。
// ponytail: 用模糊滤镜现算;档案库一屏几十张时滚动要是卡,换成按很小的尺寸解码再放大。
class BlurVeil extends StatefulWidget {
  const BlurVeil({
    super.key,
    required this.child,
    this.onOpen,
    this.revealed = false,
    this.sigma = 24,
  });

  final Widget child;
  final VoidCallback? onOpen;

  /// 一开始就是看清的(从看清的缩略图点开的大图)。
  final bool revealed;

  /// 糊的程度;铺满窗口的大图要大一些才看不出来。
  final double sigma;

  @override
  State<BlurVeil> createState() => _BlurVeilState();
}

class _BlurVeilState extends State<BlurVeil> {
  late var _shown = widget.revealed;

  Widget _tap(VoidCallback onTap, Widget child) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(onTap: onTap, child: child),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: blurImages,
    builder: (context, on, _) {
      final open = widget.onOpen;
      if (!on) {
        // 关掉再打开时从糊着开始。
        _shown = widget.revealed;
        return open == null ? widget.child : _tap(open, widget.child);
      }
      return _tap(
        () => setState(() => _shown = !_shown),
        Stack(
          fit: StackFit.passthrough,
          children: [
            // 裁掉糊到外面的那一圈。
            ClipRect(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _shown ? 0 : widget.sigma),
                duration: Motion.of(context, Motion.snap),
                curve: Motion.swift,
                builder: (context, sigma, child) => ImageFiltered(
                  enabled: sigma > 0,
                  imageFilter: ImageFilter.blur(
                    sigmaX: sigma,
                    sigmaY: sigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: child,
                ),
                child: widget.child,
              ),
            ),
            if (!_shown)
              const Positioned.fill(
                child: Center(
                  child: Icon(
                    Icons.visibility_off_outlined,
                    size: 20,
                    color: Colors.white70,
                  ),
                ),
              ),
            if (_shown && open != null)
              Positioned(
                top: 4,
                right: 4,
                child: Tooltip(
                  message: tr('看大图'),
                  child: _tap(
                    open,
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x99000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.open_in_full,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
