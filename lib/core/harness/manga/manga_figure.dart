// 格里一个人偶的手动设定:用户拖过的位置、选的姿势、朝向、正侧背、大小。
// 都没设过的就是自动的(按景别和人数排,姿势从动作文字里认)。

/// 一个人偶的设定。[x]、[y] 是千分比,相对格里那块正的矩形:全身的是脚底的位置,
/// 半身的是头顶的位置;null 是自动排。[pose] 是姿势名(见 manga_poses.dart),
/// 空串是从动作里认。[facing] 1 朝右、-1 朝左、0 自动。[view] 是「正面」「斜侧」
/// 「侧面」「背面」,空串按镜头角度定。[scale] 是百分比。
class MangaFigure {
  const MangaFigure({
    this.x,
    this.y,
    this.pose = '',
    this.facing = 0,
    this.view = '',
    this.scale = 100,
  });

  final int? x, y;
  final String pose, view;
  final int facing, scale;

  /// 正、斜侧、侧、背几种朝向(存中文原文,显示时翻译)。
  static const views = ['正面', '斜侧', '侧面', '背面'];

  bool get isAuto =>
      x == null &&
      y == null &&
      pose.isEmpty &&
      facing == 0 &&
      view.isEmpty &&
      scale == 100;

  MangaFigure copyWith({
    int? x,
    int? y,
    String? pose,
    int? facing,
    String? view,
    int? scale,
  }) => MangaFigure(
    x: (x ?? this.x)?.clamp(-200, 1200),
    y: (y ?? this.y)?.clamp(-200, 1200),
    pose: pose ?? this.pose,
    facing: (facing ?? this.facing).clamp(-1, 1),
    view: view ?? this.view,
    scale: (scale ?? this.scale).clamp(30, 300),
  );

  /// 位置回到自动(姿势这些留着)。
  MangaFigure unplaced() =>
      MangaFigure(pose: pose, facing: facing, view: view, scale: scale);

  Map<String, Object?> toJson() => {
    'x': ?x,
    'y': ?y,
    if (pose.isNotEmpty) 'pose': pose,
    if (facing != 0) 'facing': facing,
    if (view.isNotEmpty) 'view': view,
    if (scale != 100) 'scale': scale,
  };

  static MangaFigure fromJson(Object? j) {
    if (j is! Map) return const MangaFigure();
    int? n(String k) => j[k] is int ? j[k] as int : null;
    return const MangaFigure().copyWith(
      x: n('x'),
      y: n('y'),
      pose: j['pose'] is String ? j['pose'] as String : '',
      facing: n('facing') ?? 0,
      view: j['view'] is String && views.contains(j['view'])
          ? j['view'] as String
          : '',
      scale: n('scale') ?? 100,
    );
  }
}
