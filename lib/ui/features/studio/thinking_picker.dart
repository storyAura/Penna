part of 'chat_pane.dart';

// 输入框下面的思考强度:平时是一个小按钮,点开浮出一张卡片,在卡片上拖。
//
// 改设置会让整个程序重建、还要写一次硬盘(`main.dart` 最外层盯着设置),拖的时候连着来
// 就卡(用户反馈),所以拖动和选档时只改这里自己的,滑块停稳了才存。

String _thinkingName(String level) => switch (level) {
  'low' => tr('较低'),
  'high' => tr('较高'),
  'xhigh' => tr('极高'),
  _ => tr('中等'),
};

String _thinkingLabel(String level) => tr('思考强度:{0}', [_thinkingName(level)]);

/// 一档的颜色:轨道上从 [from] 渐变到 [to],字用 [ink](白底上要看得清)。
typedef _ThinkingTone = ({Color from, Color to, Color ink});

/// 和 [thinkingLevels] 一一对应,越高越热:青、蓝、紫红、橙红。
const _thinkingLight = <_ThinkingTone>[
  (from: Color(0xFF2DD4BF), to: Color(0xFF38BDF8), ink: Color(0xFF0F8A80)),
  (from: Color(0xFF60A5FA), to: Color(0xFF6366F1), ink: Color(0xFF4F46E5)),
  (from: Color(0xFF8B5CF6), to: Color(0xFFEC4899), ink: Color(0xFFB02BB5)),
  (from: Color(0xFFF59E0B), to: Color(0xFFF43F5E), ink: Color(0xFFE11D48)),
];
const _thinkingDark = <_ThinkingTone>[
  (from: Color(0xFF2DD4BF), to: Color(0xFF38BDF8), ink: Color(0xFF5EEAD4)),
  (from: Color(0xFF60A5FA), to: Color(0xFF818CF8), ink: Color(0xFFA5B4FC)),
  (from: Color(0xFFA78BFA), to: Color(0xFFF472B6), ink: Color(0xFFF0ABFC)),
  (from: Color(0xFFFBBF24), to: Color(0xFFFB7185), ink: Color(0xFFFDA4AF)),
];

List<_ThinkingTone> get _thinkingTones =>
    PennaColors.isDark ? _thinkingDark : _thinkingLight;

/// 滑块在 [at](0 到 1)时的颜色:两档之间慢慢过渡。
_ThinkingTone _thinkingToneAt(double at) {
  final tones = _thinkingTones;
  final scaled = at.clamp(0.0, 1.0) * (tones.length - 1);
  final i = scaled.floor().clamp(0, tones.length - 2);
  final t = scaled - i;
  return (
    from: Color.lerp(tones[i].from, tones[i + 1].from, t)!,
    to: Color.lerp(tones[i].to, tones[i + 1].to, t)!,
    ink: Color.lerp(tones[i].ink, tones[i + 1].ink, t)!,
  );
}

double _thinkingStop(String level) =>
    thinkingLevels.indexOf(level).clamp(0, thinkingLevels.length - 1) /
    (thinkingLevels.length - 1);

/// 圆钮中心离轨道内容两头的距离:在两头时圆钮也要完整露出来。
const _thinkingInset = 14.0;

/// 显示当前强度的按钮,点一下浮出 [_ThinkingCard],点别处收起。
class _ThinkingButton extends StatefulWidget {
  const _ThinkingButton({
    required this.level,
    required this.compact,
    required this.onChanged,
  });

  final String level;

  /// 放不下时只留图标。
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  State<_ThinkingButton> createState() => _ThinkingButtonState();
}

class _ThinkingButtonState extends State<_ThinkingButton>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final _shown = AnimationController(vsync: this);

  static const _cardWidth = 360.0;
  static const _margin = 12.0;
  var _width = _cardWidth;

  /// 对话在窗口最右边:卡片往左挪,不伸出窗口。
  var _shift = 0.0;

  /// 眼前选的档,可能还没存进设置。
  late var _level = widget.level;

  void _preview(String level) {
    if (level != _level) setState(() => _level = level);
  }

  void _commit() {
    if (_level != widget.level) widget.onChanged(_level);
  }

  void _open() {
    // 坐标都按弹窗层算:界面放大时它和窗口坐标不是一回事。
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final me = context.findRenderObject()! as RenderBox;
    final left = me.localToGlobal(Offset.zero, ancestor: overlay).dx;
    final room = overlay.size.width - _margin * 2;
    _width = room < _cardWidth ? room : _cardWidth;
    final over = left + _width + _margin - overlay.size.width;
    _shift = over > 0 ? -over : 0;
    _portal.show();
    _shown.duration = Motion.of(context, Motion.base);
    _shown.forward();
    setState(() {});
  }

  void _close() {
    if (!_portal.isShowing || _shown.status == AnimationStatus.reverse) return;
    _shown.duration = Motion.of(context, Motion.snap);
    _shown.reverse().whenComplete(() {
      if (mounted && _shown.isDismissed) {
        _portal.hide();
        setState(() {});
        // 滑块还没停稳就点走了。
        _commit();
      }
    });
    setState(() {});
  }

  @override
  void didUpdateWidget(_ThinkingButton old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) _level = widget.level;
  }

  @override
  void dispose() {
    _shown.dispose();
    // 拆树时不能通知,放到后面存。
    if (_level != widget.level) {
      final (save, level) = (widget.onChanged, _level);
      scheduleMicrotask(() => save(level));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing && _shown.status != AnimationStatus.reverse;
    final ink = _thinkingToneAt(_thinkingStop(_level)).ink;
    return TapRegion(
      groupId: _link,
      onTapOutside: (_) => _close(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: Offset(_shift, -8),
            child: TapRegion(
              groupId: _link,
              onTapOutside: (_) => _close(),
              child: FadeTransition(
                opacity: _shown,
                child: ScaleTransition(
                  alignment: Alignment.bottomLeft,
                  scale: Tween(begin: 0.94, end: 1.0).animate(
                    CurvedAnimation(parent: _shown, curve: Motion.swift),
                  ),
                  child: _ThinkingCard(
                    width: _width,
                    level: _level,
                    onPreview: _preview,
                    onSettled: _commit,
                    onClose: _close,
                  ),
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: ink),
            duration: Motion.of(context, Motion.base),
            curve: Motion.swift,
            builder: (_, value, _) => PennaButton(
              label: widget.compact ? '' : _thinkingLabel(_level),
              tooltip: widget.compact ? _thinkingLabel(_level) : null,
              icon: Icons.psychology_outlined,
              foreground: value,
              background: open ? PennaColors.slate100 : null,
              onPressed: open ? _close : _open,
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮出来的卡片:标题和当前档位、滑块、四档的名字。
class _ThinkingCard extends StatelessWidget {
  const _ThinkingCard({
    required this.width,
    required this.level,
    required this.onPreview,
    required this.onSettled,
    required this.onClose,
  });

  final double width;
  final String level;
  final ValueChanged<String> onPreview;
  final VoidCallback onSettled;
  final VoidCallback onClose;

  void _step(int by) {
    final next = thinkingLevels.indexOf(level) + by;
    if (next >= 0 && next < thinkingLevels.length) {
      onPreview(thinkingLevels[next]);
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      onClose();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tone = _thinkingToneAt(_thinkingStop(level));
    // AnimatedDefaultTextStyle 是整个换掉默认样式,不是合并:不从主题起步字体就丢了。
    final base = Theme.of(context).textTheme.bodyMedium!;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.sheet),
          curve: Motion.swift,
          width: width,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          decoration: BoxDecoration(
            color: PennaColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PennaColors.border),
            boxShadow: [
              const BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
              // 卡片底下透出一点这一档的颜色。
              BoxShadow(
                color: tone.to.withValues(alpha: 0.22),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('思考强度'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedDefaultTextStyle(
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.swift,
                    style: base.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tone.ink,
                    ),
                    child: Text(_thinkingName(level)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ThinkingTrack(
                level: level,
                onPreview: onPreview,
                onSettled: onSettled,
              ),
              const SizedBox(height: 6),
              // 每个名字正对着它那一档的点。
              SizedBox(
                height: 18,
                child: LayoutBuilder(
                  builder: (_, box) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final (i, l) in thinkingLevels.indexed)
                        Positioned(
                          left:
                              _thinkingInset +
                              (box.maxWidth - _thinkingInset * 2) *
                                  i /
                                  (thinkingLevels.length - 1),
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, 0),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => onPreview(l),
                                child: AnimatedDefaultTextStyle(
                                  duration: Motion.of(context, Motion.base),
                                  curve: Motion.swift,
                                  style: base.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: l == level
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: l == level
                                        ? tone.ink
                                        : PennaColors.slate500,
                                  ),
                                  child: Text(_thinkingName(l)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一粒火星。[x] 是在轨道上的位置(0 到 1),[y] 是离轨道中线多少像素。
class _ThinkingSpark {
  _ThinkingSpark(this.x, this.y, this.vx, this.vy, this.life, this.size)
    : full = life;

  double x;
  double y;
  final double vx;
  final double vy;
  double life;
  final double full;
  final double size;
}

/// 滑块和特效这一帧的样子。每帧只改这里、只重画这一小块,不重建部件,拖得再快也不卡。
class _ThinkingScene extends ChangeNotifier {
  /// 一个强度每秒冒几粒:越高越热闹。
  static const _sparksPerSecond = [4.0, 9.0, 18.0, 36.0];
  static const _maxSparks = 70;

  /// 圆钮追目标的快慢(秒,越小越快):拖的时候紧跟手,松手时滑过去。
  static const _chase = 0.03;
  static const _glide = 0.07;

  _ThinkingScene(this.position) : target = position;

  double position;
  double target;
  double press = 0;
  var dragging = false;

  /// 过了一档时圆钮外扩的那一圈:1 刚开始,0 没有。
  double ring = 0;
  double time = 0;
  int level = 0;
  final sparks = <_ThinkingSpark>[];

  final _random = math.Random();
  double _owed = 0;

  double _between(double a, double b) => a + _random.nextDouble() * (b - a);

  /// 这一帧走 [dt] 秒。圆钮停稳时返回真。
  bool step(double dt) {
    time += dt;
    position += (target - position) * _ease(dt, dragging ? _chase : _glide);
    press += ((dragging ? 1 : 0) - press) * _ease(dt, _chase * 2);
    if (ring > 0) ring = math.max(0, ring - dt / 0.5);

    _owed += _sparksPerSecond[level] * dt;
    for (; _owed >= 1 && sparks.length < _maxSparks; _owed--) {
      // 大多从圆钮附近冒出来,也有一些从走过的那段。
      final behind = _random.nextDouble();
      _spark(position * (1 - behind * behind * behind), _between(-9, 9));
    }
    if (_owed > 1) _owed = 1;

    for (final s in sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt;
    }
    sparks.removeWhere((s) => s.life <= 0);
    notifyListeners();
    return (position - target).abs() < 0.002;
  }

  /// 过了一档:一圈光加一小把火星。
  void burst() {
    ring = 1;
    for (var i = 0; i < 12 && sparks.length < _maxSparks; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = _between(30, 80);
      sparks.add(
        _ThinkingSpark(
          position,
          0,
          math.cos(angle) * speed / 320,
          math.sin(angle) * speed,
          _between(0.35, 0.7),
          _between(1, 2),
        ),
      );
    }
  }

  void _spark(double x, double y) => sparks.add(
    _ThinkingSpark(
      x,
      y,
      _between(-0.015, 0.015),
      _between(-46, -16),
      _between(0.5, 1.1),
      _between(0.7, 1.7),
    ),
  );

  /// 跳到目标(系统设置了减少动画时不跑这一套)。
  void jump() {
    position = target;
    notifyListeners();
  }

  static double _ease(double dt, double tau) => 1 - math.exp(-dt / tau);
}

/// 滑块本体:拖的时候跟着手走、颜色慢慢过渡,松手滑到最近的一档。
/// 不用系统的 Slider:分了档的它只会一格一格跳。
class _ThinkingTrack extends StatefulWidget {
  const _ThinkingTrack({
    required this.level,
    required this.onPreview,
    required this.onSettled,
  });

  final String level;
  final ValueChanged<String> onPreview;

  /// 滑块停稳了,可以存了。
  final VoidCallback onSettled;

  @override
  State<_ThinkingTrack> createState() => _ThinkingTrackState();
}

class _ThinkingTrackState extends State<_ThinkingTrack>
    with SingleTickerProviderStateMixin {
  static const _height = 28.0;

  late final _scene = _ThinkingScene(_thinkingStop(widget.level))
    ..level = thinkingLevels.indexOf(widget.level);
  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  var _still = false;
  var _unsaved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统设置了减少动画:没有特效,滑块直接到位。
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(_ThinkingTrack old) {
    super.didUpdateWidget(old);
    if (old.level == widget.level) return;
    _scene.level = thinkingLevels.indexOf(widget.level);
    if (!_still) _scene.burst();
    // 点了底下的名字、按了方向键:滑过去。拖的时候是手在带着走。
    if (!_scene.dragging) {
      _scene.target = _thinkingStop(widget.level);
      _settleLater();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  void _tick(Duration now) {
    final dt = (now - _last).inMicroseconds / 1e6;
    _last = now;
    final stopped = _scene.step(dt.clamp(0.0, 0.05));
    if (stopped && _unsaved && !_scene.dragging) {
      _unsaved = false;
      widget.onSettled();
    }
  }

  /// 滑块停稳后存。有动画时 [_tick] 看着;没有动画就等这一帧过去。
  void _settleLater() {
    if (!_still) {
      _unsaved = true;
      return;
    }
    _scene.jump();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSettled();
    });
  }

  void _follow(double dx, double width) {
    final at = ((dx - _thinkingInset) / (width - _thinkingInset * 2)).clamp(
      0.0,
      1.0,
    );
    _scene.target = at;
    if (_still) _scene.jump();
    widget.onPreview(
      thinkingLevels[(at * (thinkingLevels.length - 1)).round()],
    );
  }

  void _down(PointerDownEvent e, double width) {
    _scene.dragging = true;
    _follow(e.localPosition.dx, width);
  }

  void _up() {
    if (!_scene.dragging) return;
    _scene.dragging = false;
    _scene.target = _thinkingStop(widget.level);
    _settleLater();
  }

  void _step(int by) {
    final next = thinkingLevels.indexOf(widget.level) + by;
    if (next >= 0 && next < thinkingLevels.length) {
      widget.onPreview(thinkingLevels[next]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = thinkingLevels.indexOf(widget.level);
    final canRaise = i < thinkingLevels.length - 1;
    final canLower = i > 0;
    return Semantics(
      slider: true,
      label: tr('思考强度'),
      value: _thinkingName(widget.level),
      increasedValue: canRaise ? _thinkingName(thinkingLevels[i + 1]) : null,
      decreasedValue: canLower ? _thinkingName(thinkingLevels[i - 1]) : null,
      onIncrease: canRaise ? () => _step(1) : null,
      onDecrease: canLower ? () => _step(-1) : null,
      child: LayoutBuilder(
        builder: (_, box) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Listener(
            onPointerDown: (e) => _down(e, box.maxWidth),
            onPointerMove: (e) => _follow(e.localPosition.dx, box.maxWidth),
            onPointerUp: (_) => _up(),
            onPointerCancel: (_) => _up(),
            // 单独一层:每帧重画只动这一小块。
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(box.maxWidth, _height),
                painter: _ThinkingPainter(
                  scene: _scene,
                  track: PennaColors.slate100,
                  edge: PennaColors.border,
                  tick: PennaColors.slate400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条胶囊轨道,走过的部分是渐变色,上面压一个白色圆钮;档位是轨道里的小点。
/// 特效:走过的部分有光扫过、整条发光、冒火星,过一档外扩一圈;越高越热闹。
class _ThinkingPainter extends CustomPainter {
  _ThinkingPainter({
    required this.scene,
    required this.track,
    required this.edge,
    required this.tick,
  }) : super(repaint: scene);

  final _ThinkingScene scene;
  final Color track;
  final Color edge;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = 24.0;
    const round = Radius.circular(thickness / 2);
    final at = scene.position.clamp(0.0, 1.0);
    final tone = _thinkingToneAt(at);
    final y = size.height / 2;
    const left = _thinkingInset;
    final right = size.width - _thinkingInset;
    double xOf(double t) => left + (right - left) * t;
    final x = xOf(at);
    Rect bar(double to) => Rect.fromLTRB(
      left - thickness / 2,
      y - thickness / 2,
      to,
      y + thickness / 2,
    );
    final whole = RRect.fromRectAndRadius(bar(right + thickness / 2), round);
    final fillRect = bar(x + thickness / 2);
    final fill = RRect.fromRectAndRadius(fillRect, round);

    canvas.drawRRect(whole, Paint()..color = track);
    canvas.drawRRect(
      fill,
      Paint()
        ..color = tone.to.withValues(alpha: 0.3 + 0.25 * at)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = LinearGradient(colors: [tone.from, tone.to])
            .createShader(fillRect),
    );
    _paintSheen(canvas, fill, fillRect, at);
    canvas.drawRRect(
      whole,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    final stops = thinkingLevels.length - 1;
    for (var i = 0; i <= stops; i++) {
      final stop = xOf(i / stops);
      // 被圆钮盖住的不画。
      if ((stop - x).abs() < 15) continue;
      canvas.drawCircle(
        Offset(stop, y),
        2,
        Paint()..color = stop < x ? const Color(0x80FFFFFF) : tick,
      );
    }

    for (final s in scene.sparks) {
      final fade = (s.life / s.full).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(xOf(s.x.clamp(0.0, 1.0)), y + s.y),
        s.size * (0.5 + 0.5 * fade),
        Paint()
          ..color = Color.lerp(
            tone.to,
            Colors.white,
            0.35,
          )!.withValues(alpha: fade * 0.9),
      );
    }

    if (scene.ring > 0) {
      canvas.drawCircle(
        Offset(x, y),
        14 + (1 - scene.ring) * 18,
        Paint()
          ..color = tone.to.withValues(alpha: scene.ring * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * scene.ring + 0.5,
      );
    }

    final radius = 13.0 + scene.press;
    // 圆钮外的光晕,强度高时一呼一吸。
    final breath = 0.5 + 0.5 * math.sin(scene.time * (2 + 3 * at));
    canvas.drawCircle(
      Offset(x, y),
      radius + 2 + 2 * breath * at,
      Paint()
        ..color = tone.to.withValues(alpha: 0.28 + 0.27 * at * breath)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(Offset(x, y), radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()
        ..color = const Color(0x14000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  /// 走过的那段上,一道光从左扫到右,强度越高扫得越快。
  void _paintSheen(Canvas canvas, RRect fill, Rect rect, double at) {
    const width = 70.0;
    final loop = 2.6 - 1.6 * at;
    final phase = (scene.time % loop) / loop;
    final left = rect.left - width + (rect.width + width * 2) * phase;
    final band = Rect.fromLTWH(left, rect.top, width, rect.height);
    canvas.save();
    canvas.clipRRect(fill);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0x47FFFFFF), Color(0x00FFFFFF)],
        ).createShader(band),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThinkingPainter old) =>
      scene != old.scene ||
      track != old.track ||
      edge != old.edge ||
      tick != old.tick;
}
