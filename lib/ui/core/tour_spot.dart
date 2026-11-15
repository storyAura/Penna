import 'package:flutter/widgets.dart';

final _keys = <String, GlobalKey>{};

/// 教程要高亮的那一块:每个 id 一把固定的 key,同一个 id 只能包一处。
GlobalKey tourKey(String id) =>
    _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tour:$id'));

/// 把 [child] 标成教程里的一块([id] 写在 `tour_steps.dart` 里)。
class TourSpot extends StatelessWidget {
  const TourSpot(this.id, {super.key, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: tourKey(id), child: child);
}

/// 召唤出来的吉祥物坐在输入区上沿时,快捷操作那一排在最左边给她让出 [width] 宽,
/// 她垂下来的腿和长袖落在这块空地上,不盖住按钮。没坐着时为 0。
/// [overhang] 是她探出输入区上沿的高度(连说话的气泡):消息列表底下多留这么高,
/// 最后一条滚到底时露在她头顶上面,不被挡住(2026-11-16 用户反馈:还是会挡)。
class MascotRoom extends InheritedWidget {
  const MascotRoom({
    super.key,
    required this.width,
    this.overhang = 0,
    required super.child,
  });

  final double width;
  final double overhang;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotRoom>()?.width ?? 0;

  static double overhangOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotRoom>()?.overhang ?? 0;

  @override
  bool updateShouldNotify(MascotRoom old) =>
      old.width != width || old.overhang != overhang;
}
