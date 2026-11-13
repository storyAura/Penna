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
class MascotRoom extends InheritedWidget {
  const MascotRoom({super.key, required this.width, required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MascotRoom>()?.width ?? 0;

  @override
  bool updateShouldNotify(MascotRoom old) => old.width != width;
}
