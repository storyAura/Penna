part of 'chat_message_view.dart';

const _bodyStyle = TextStyle(fontSize: 14, height: 1.6);

/// 等第一个字出来时的三个小点:慢慢地依次亮起、浮起再暗下去,安静不抢眼。
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.since});

  /// 从什么时候开始等的;给了就在小点后面写「已等 n 秒」。
  final DateTime? since;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Row(
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (_) {
                  // 三个点依次亮起:每个点比前一个晚 150ms(一圈 1.9 秒)。
                  final t = (_controller.value - i * 0.08) % 1;
                  // 前一半里亮起再暗下(0→1→0,缓入缓出),后一半歇着。
                  final up = t < 0.5
                      ? Curves.easeInOut.transform(1 - (t / 0.25 - 1).abs())
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 3.5),
                    child: Transform.translate(
                      offset: Offset(0, -2 * up),
                      child: CircleAvatar(
                        radius: 1.5 + 0.5 * up,
                        backgroundColor: Color.lerp(
                          PennaColors.slate400,
                          PennaColors.primary,
                          up,
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (widget.since case final since?) ...[
              const SizedBox(width: 6),
              Elapsed(since: since, waiting: true),
            ],
          ],
        ),
      ),
    );
  }
}

/// 用了多久的写法:不到一分钟写秒,往上写「1 分 05 秒」。
String elapsedLabel(Duration d) {
  final s = d.inSeconds;
  return s < 60
      ? tr('{0} 秒', [s])
      : tr('{0} 分 {1} 秒', [s ~/ 60, '${s % 60}'.padLeft(2, '0')]);
}

/// 从 [since] 到现在过了多久,一秒一跳。[waiting] 时写成「已等 n 秒」。
class Elapsed extends StatefulWidget {
  const Elapsed({super.key, required this.since, this.waiting = false});

  final DateTime since;
  final bool waiting;

  @override
  State<Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<Elapsed> {
  late final Timer _tick = Timer.periodic(
    const Duration(seconds: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    final label = elapsedLabel(d.isNegative ? Duration.zero : d);
    return Text(
      widget.waiting ? tr('已等 {0}', [label]) : label,
      style: TextStyle(fontSize: 11, color: PennaColors.slate400),
    );
  }
}

/// 这条回复出自哪个模型。
class _ModelTag extends StatelessWidget {
  const _ModelTag({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate100,
      borderColor: PennaColors.slate100,
      radius: 4,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        name,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
    );
  }
}
