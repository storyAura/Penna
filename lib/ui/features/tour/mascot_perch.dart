import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../studio/studio_view_model.dart';
import 'pixel_mascot.dart';

/// 被点了说的话,随便挑一句。
List<String> get _lines => [
  tr('干、干嘛啦!'),
  tr('别、别戳了!笨蛋!'),
  tr('再戳会长不高的啦!'),
  tr('哼……才不是在等你呢!'),
];

const _height = 160.0;

/// 坐着的两张图里,她屁股坐着的那条线在图高的多少处(往下是垂着的腿和长袖)。
const _seat = 0.68;

/// 输入区左边的内边距;她坐在快捷操作那一排让出来的最左边。
const _pad = 16.0;

/// 快捷操作那一排要让出的宽度(`MascotRoom`):她的宽度加一点空隙。
final mascotRoom = _height * MascotLook.doze.aspect + 4;

/// 「设置 → 召唤吉祥物」:她坐在 [anchor] 那块(对话的输入区)的上沿打瞌睡,腿和长袖垂在框前,
/// 落在快捷操作那一排给她让出来的空地上(`MascotRoom`)。
/// 鼠标移上去她抱膝撅嘴;左键点她,她抱头蹦一下、嘟囔一句,过一会儿接着打瞌睡。
/// 给了 [chat] 时跟着对话:写回复时盯着看,写完比耶、出错慌张,之后醒着坐一会儿再睡。
/// 铺满整页放在最上面,只有她自己那些格子接点击。
class MascotPerch extends StatefulWidget {
  const MascotPerch({super.key, required this.anchor, this.chat});

  final GlobalKey anchor;
  final StudioViewModel? chat;

  @override
  State<MascotPerch> createState() => _MascotPerchState();
}

class _MascotPerchState extends State<MascotPerch> {
  Rect? _box;
  bool _hover = false;
  bool _poked = false, _hop = false;
  String? _line;
  Timer? _calm, _watch, _moodEnd, _nap;
  final _random = math.Random();

  /// 对话正在写回复;写完那一下的反应;反应过后醒着坐一会儿。
  bool _busy = false, _awake = false;
  MascotLook? _mood;

  @override
  void initState() {
    super.initState();
    _busy = widget.chat?.isStreaming ?? false;
    widget.chat?.addListener(_onChat);
    // 输入框打了几行字会变高:半秒看一次框在哪。
    _watch = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _measure(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    widget.chat?.removeListener(_onChat);
    for (final t in [_calm, _watch, _moodEnd, _nap]) {
      t?.cancel();
    }
    super.dispose();
  }

  void _onChat() {
    final chat = widget.chat!;
    if (chat.isStreaming == _busy || !mounted) return;
    _busy = chat.isStreaming;
    if (_busy) return setState(() {});
    final last = chat.messages.lastOrNull;
    if (last == null || last.fromUser || last.stopped) return _feel(null);
    _feel(last.failed ? MascotLook.panic : MascotLook.peace);
  }

  /// 反应 3 秒,之后醒着坐 30 秒再接着睡。
  void _feel(MascotLook? mood) {
    _moodEnd?.cancel();
    _nap?.cancel();
    setState(() {
      _mood = mood;
      _awake = true;
    });
    _moodEnd = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _mood = null);
    });
    _nap = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _awake = false);
    });
  }

  void _measure() {
    if (!mounted) return;
    final me = context.findRenderObject();
    final target = widget.anchor.currentContext?.findRenderObject();
    Rect? box;
    if (me is RenderBox &&
        me.hasSize &&
        target is RenderBox &&
        target.attached &&
        target.hasSize) {
      box = MatrixUtils.transformRect(
        target.getTransformTo(me),
        Offset.zero & target.size,
      );
    }
    if (box != _box) setState(() => _box = box);
  }

  void _poke() {
    _calm?.cancel();
    setState(() {
      _poked = _hop = true;
      _line = _lines[_random.nextInt(_lines.length)];
    });
    // 蹦一下就落回去;撅嘴一会儿再接着打瞌睡。
    Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _hop = false);
    });
    _calm = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _poked = false;
          _line = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final box = _box;
    if (box == null) return const SizedBox.shrink();
    final look = _poked
        ? MascotLook.cower
        : _hover
        ? MascotLook.sulk
        : _mood ??
              (_busy
                  ? MascotLook.watch
                  : _awake
                  ? MascotLook.sit
                  : MascotLook.doze);
    final width = _height * look.aspect;
    // 坐在最左边让出来的那块上(右下角有「回到底部」按钮);坐着的那条线压在框的上沿。
    final left = box.left + _pad - 2;
    final top = box.top - _height * _seat;
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            // 默认整个方块都算她;只认画出来的格子。
            hitTestBehavior: HitTestBehavior.deferToChild,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: _poke,
              child: AnimatedSlide(
                offset: _hop ? const Offset(0, -0.06) : Offset.zero,
                duration: Motion.of(context, Motion.snap),
                curve: Motion.swift,
                child: PixelMascot(look: look, height: _height),
              ),
            ),
          ),
        ),
        // 说的话:冒在她头的右边。
        Positioned(
          left: left + width - 8,
          top: top + 24,
          width: 160,
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.base),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.leave,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(begin: 0.85, end: 1.0).animate(a),
                  alignment: Alignment.centerLeft,
                  child: child,
                ),
              ),
              child: _line == null
                  ? const SizedBox.shrink()
                  : Align(
                      key: ValueKey(_line),
                      alignment: Alignment.centerLeft,
                      child: _Bubble(text: _line!),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: PennaColors.card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: PennaColors.primaryBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: PennaColors.text)),
  );
}
