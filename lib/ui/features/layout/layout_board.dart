import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../core/harness/layout.dart';
import '../../../core/harness/layout_3d.dart';
import '../../../core/harness/layout_relations.dart';
import '../../../l10n/l10n.dart';

part 'layout_board_agent.dart';
part 'layout_board_lighting.dart';

/// 存下来的一个画布尺寸。
typedef LayoutSize = ({int width, int height});

const _defaultSizes = <LayoutSize>[
  (width: defaultLayoutWidth, height: defaultLayoutHeight),
];

/// 布局画板:当前这张布局、选中的框、用户存的几个画布尺寸。存在 layout.json。
/// Agent 写的 `<layout>` 也放到这里(见 `studio_chat.dart` 的 `_deliverLayout`)。
class LayoutBoard extends ChangeNotifier {
  /// [dir] 为 null 时不存盘(测试用)。
  LayoutBoard({this.dir, this.quality});

  final Directory? dir;

  /// 交出去的 JSON 开头加的质量词(读设置里的 `layoutQuality`);null 是不加。
  final String Function()? quality;

  Layout _layout = const Layout();
  List<LayoutSize> _sizes = List.unmodifiable(_defaultSizes);
  int? _selected;

  /// 框的文字被整个换掉(Agent 放进来、删了框)时加一:输入框靠它重建。
  int _revision = 0;
  Timer? _saveTimer;

  /// 3D 视图开着没有(默认是平面视图,不存盘)。体块和摄像机两种视图下都留着。
  bool _threeD = false;

  /// 自由镜头开着没有(3D 视图里才有,不存盘):开着时画布上拖动是转头、WASD 走动。
  bool _freeCam = false;

  /// 这一趟自由镜头还没记进操作记录(第一次挪动时记一笔)。
  bool _freeUnlogged = false;

  /// 描述是照哪个镜头写的:Agent 放上布局、换页时记下。镜头转过之后和它不一样,
  /// 界面上就给出「按视角改描述」。
  Camera _described = const Camera();

  /// 下一次改动算哪一步操作(记进操作记录);见 [mark]。
  String? _action;

  Layout get layout => _layout;
  List<LayoutSize> get sizes => _sizes;
  int? get selected => _selected;
  int get revision => _revision;
  String get json => exportJson(_layout);

  /// [l] 交出去的样子:官方坐标,caption 前面带上质量词和画风。
  String exportJson(Layout l) =>
      mossLayoutJson(l, quality: quality?.call() ?? '');
  bool get threeD => _threeD;

  /// 光影预览:3D 视图里开着灯光时,按灯光给体块和画布上明暗(灯光面板里切换,不存盘)。
  final shadePreview = ValueNotifier(true);
  bool get freeCam => _freeCam;

  /// 第 [i] 块眼下在画布上画不画(见 [LayoutBox.shownIn])。
  bool shown(int i) => _layout.boxes[i].shownIn(threeD: _threeD);

  /// 镜头转过了,描述还是照原来的镜头写的。
  bool get cameraMoved => _layout.camera != _described;

  /// 有体块是程序猜的,还没让 Agent 估过。
  bool get guessedBodies => _layout.boxes.any((b) => b.body?.guessed ?? false);

  /// 记下接下来这次改动算哪一步(画布开始拖、开始转镜头时),[text] 为 null 是作废。
  /// 拖动时每一帧都在改,只有第一帧记一笔。
  void mark(String? text) => _action = text;

  /// 取走要记的那一步(区域控制那场对话收到改动时记进操作记录)。
  String? takeAction() {
    final a = _action;
    _action = null;
    return a;
  }

  /// 告诉模型画布尺寸和现有的布局,它写 `<layout>` 时坐标才对得上。
  String get prompt {
    final l = _layout;
    String pct(int v, int side) => '${(v * 100 / side).round()}%';
    // 换成占画布的几成,模型不用自己算坐标也知道每块在哪、多大、和谁挨着。
    final where = [
      for (final (i, b) in l.boxes.indexed)
        '${i + 1}. ${b.name.isEmpty ? '(没起名)' : b.name}'
            '(${b.label},${_layerNames[b.layer]}):'
            '${b.offscreen ? '转到镜头外了,不在 JSON 里,不用管它' : '横向 ${pct(b.left, l.width)}–${pct(b.right, l.width)},'
                      '纵向 ${pct(b.top, l.height)}–${pct(b.bottom, l.height)}'}',
    ].join('\n');
    final shape = l.width > l.height
        ? '横构图'
        : l.width < l.height
        ? '竖构图'
        : '方图';
    return '【布局画板】画布 ${l.width}×${l.height}(宽×高,$shape)。'
        'bbox 从左上角量,写成 [x_min, y_min, x_max, y_max],'
        'x 从 0 到 ${l.width},y 从 0 到 ${l.height};换成官方坐标由程序来做。'
        'bbox 是这块画布上的像素,不要写成 0–1000 的比例坐标。'
        '<layout> 的 width / height 只有两种写法:照抄 ${l.width}×${l.height};'
        '用户要横竖对调(说了横构图、竖构图,或参考图和画布一横一竖)时写 ${l.height}×${l.width},'
        '程序会把画布对调,bbox 按对调后的尺寸写。别的尺寸和比例不要写,画布尺寸由用户在顶栏定;'
        '参考图只参考画面内容和横竖,不照它的比例改画布。'
        '${_fixesNote()}'
        '${l.isEmpty ? '现在是空的。' : '下面是画板此刻的样子:用户可能刚拖过框、改过字或类别,'
                  '一切以这里为准,上文对话里的旧布局不算数'
                  '(你以前写的布局在上文里已省略,只留了一句说明)。'
                  '这次要改布局,就照这里的样子改好,把完整的 JSON 写进 <layout>。'
                  '没让你动的框,bbox 照这里原样抄,label、meta、canvas 也照抄;'
                  '画风(summary.style)定了就不用写,程序沿用;用户要换画风时才写新的。'
                  'name 是用户给这一块起的名字,他说"把某某挪到……"指的就是它;'
                  '你写的时候照样带着 name,新加的块也起一个两到六个字的中文名。\n'
                  '各块按前后排:1 在最前面,越往后越靠后,重叠时前面的盖住后面的;'
                  'items 也照这个先后写(前景、中景、后景依次),要调前后就换它们的先后;'
                  '只换前后、改名字、换前中后景时写 <layers> 就够了。'
                  '各块在画布上的范围(从左上角量,0% 是左边或顶上):\n$where\n'
                  '<current-layout>\n${mossLayoutJson(l, draft: true)}\n</current-layout>'}'
        '\n\n${l.perspective?.describe(l.width, l.height) ?? '【透视辅助】现在关着。'}'
        '\n\n${describeCamera(l, threeD: _threeD)}'
        '\n\n${describeLighting(l.lighting, l.camera)}'
        '${switch (describeShapes(l)) {
          '' => '',
          final s => '\n\n$s',
        }}'
        '${[_drawnNote(l), _castNote(l)].where((s) => s.isNotEmpty).map((s) => '\n\n$s').join()}'
        // 3D 视图开着时,用户在 3D 里摆的就是构图:关系按 3D 场景算,不按 2D 的框。
        '${l.isEmpty ? '' : '\n\n${_threeD ? sceneRelations(l) : layoutRelations(l)}'}';
  }

  /// 换成 [layout]:框先按前后排好(见 [stacked])。[follow] 是要跟着选中的那一块
  /// (排序后它的位置可能变了)。框的先后变了时输入框要重建,和 [rebuild] 一样。
  void _set(
    Layout layout, {
    bool rebuild = false,
    LayoutBox? follow,
    String? action,
  }) {
    if (action != null) _action = action;
    _fixes = const [];
    _refit = null;
    final boxes = stacked(layout.boxes);
    final reordered = [
      for (final (i, b) in boxes.indexed) identical(b, layout.boxes[i]),
    ].contains(false);
    _layout = layout.copyWith(boxes: boxes);
    if (rebuild || reordered) _revision++;
    if (follow != null) {
      final at = boxes.indexWhere((b) => identical(b, follow));
      _selected = at < 0 ? null : at;
    } else if (_selected != null && _selected! >= boxes.length) {
      _selected = null;
    }
    notifyListeners();
    _scheduleSave();
  }

  void select(int? i) {
    if (_selected == i) return;
    _selected = i;
    notifyListeners();
  }

  /// 换画布尺寸,框按比例跟着缩放。尺寸不在范围内就不换,返回 false。
  bool setSize(int width, int height) {
    if (!_validSide(width) || !_validSide(height)) return false;
    final l = _layout;
    if (width == l.width && height == l.height) return true;
    final sx = width / l.width, sy = height / l.height;
    final next = l.copyWith(
      width: width,
      height: height,
      boxes: [for (final b in l.boxes) b.scaled(sx, sy)],
      perspective: () => l.perspective?.scaled(sx, sy),
    );
    _set(
      next.copyWith(boxes: [for (final b in next.boxes) refitBody(b, next)]),
      action: tr('画布换成 {0}×{1}', [width, height]),
    );
    return true;
  }

  /// 开 / 关透视辅助线;[points] 是几点透视(1 到 3),换的时候从默认的样子开始。
  /// 3D 视图里透视线就是镜头:照镜头算出来,不能另画(见 [perspectiveFromCamera])。
  void setPerspective(int? points) => _set(
    _layout.copyWith(
      perspective: () => points == null
          ? null
          : _threeD
          ? perspectiveFromCamera(
              _layout.camera,
              _layout.width,
              _layout.height,
              points,
            )
          : Perspective.preset(points, _layout.width, _layout.height),
    ),
    action: tr('切换透视辅助'),
  );

  /// 拖动透视线(平面视图里画布上拖消失点时用)。
  void movePerspective(Perspective p) =>
      _set(_layout.copyWith(perspective: () => p));

  /// 把第 [i] 个消失点拖到画布上的 ([x], [y])(可以在画面外)。平面视图里只挪透视线;
  /// 3D 视图里透视线就是镜头,拖它就是转镜头(fSpy 的做法,见
  /// [cameraFromPerspective]):地平线上的点上下拖改俯仰、左右拖改环绕,
  /// 两点透视时连视角一起定;一点、两点透视镜头保持水平、用移轴放地平线,三点透视
  /// 由三个消失点的垂心定俯仰和移轴(都见 [cameraFromPerspective])。
  void moveVanishing(int i, double x, double y) {
    final per = _layout.perspective;
    if (per == null) return;
    final moved = i < per.xs.length
        ? per.copyWith(
            horizon: y.round(),
            xs: [
              for (final (j, old) in per.xs.indexed) j == i ? x.round() : old,
            ],
          )
        : per.copyWith(third: (x: x.round(), y: y.round()));
    if (!_threeD) return movePerspective(moved);
    final l = _layout;
    setCamera(cameraFromPerspective(moved, l.camera, l.width, l.height));
  }

  /// 照 Agent 写的 `<layers>` 调图层(见 [parseLayers]):按给的先后排,顺便改名字和
  /// 前中后景;框的位置和描述一点不动。没写到的块按原来的先后接在后面。
  /// 序号对不上或重复时返回 false,画板不动。
  bool applyLayers(List<LayerOp> ops) {
    final old = _layout.boxes;
    final listed = <int>{};
    for (final op in ops) {
      if (op.from < 1 || op.from > old.length || !listed.add(op.from)) {
        return false;
      }
    }
    _selected = null;
    _set(
      _layout.copyWith(
        boxes: [
          for (final op in ops)
            old[op.from - 1].copyWith(name: op.name, layer: op.layer),
          for (final (i, b) in old.indexed)
            if (!listed.contains(i + 1)) b,
        ],
      ),
      rebuild: true,
      action: tr('Agent 调整图层'),
    );
    return true;
  }

  /// 照 Agent 写的 `<perspective>` 改透视线(见 [parsePerspective])。
  /// 读不了返回 false,画板不动。
  bool applyPerspective(String spec) {
    final parsed = parsePerspective(spec, _layout.width, _layout.height);
    if (parsed == null) return false;
    // 3D 视图里透视线就是镜头:照 Agent 写的透视定镜头,透视线再跟着镜头算。
    final want = parsed.value;
    if (_threeD && want != null) {
      final l = _layout;
      _reproject(
        l.copyWith(
          camera: cameraFromPerspective(want, l.camera, l.width, l.height),
          perspective: () => want,
        ),
        action: tr('Agent 调整透视'),
      );
      return true;
    }
    _set(
      _layout.copyWith(perspective: () => parsed.value),
      action: tr('Agent 调整透视'),
    );
    return true;
  }

  /// 宽高对调(横竖切换)。
  void swap() => setSize(_layout.height, _layout.width);

  /// 参考图和画布一横一竖时,对调后的画布尺寸;图是方的、画布是方的、
  /// 本来就对得上或者图读不了时为 null。
  Future<LayoutSize?> swapFor(Uint8List image) async {
    final size = await _imageSize(image);
    final l = _layout;
    if (size == null || size.width == size.height || l.width == l.height) {
      return null;
    }
    if ((size.width > size.height) == (l.width > l.height)) return null;
    return (width: l.height, height: l.width);
  }

  /// 存下眼下的画布尺寸;已经存满 [maxSizes] 个时不存,返回 false。
  bool saveSize() {
    final size = (width: _layout.width, height: _layout.height);
    if (_sizes.contains(size)) return true;
    if (_sizes.length >= maxSizes) return false;
    _sizes = List.unmodifiable([..._sizes, size]);
    notifyListeners();
    _scheduleSave();
    return true;
  }

  /// 最多存几个常用的画布尺寸(分辨率面板里两排)。
  static const maxSizes = 8;

  void removeSize(LayoutSize size) {
    _sizes = List.unmodifiable(_sizes.where((s) => s != size));
    notifyListeners();
    _scheduleSave();
  }

  void setSummary({
    String? caption,
    String? style,
    String? meta,
    String? canvas,
  }) => _set(
    _layout.copyWith(
      caption: caption,
      style: style,
      meta: meta,
      canvas: canvas,
    ),
  );

  /// 换掉本系列的角色卡(属性栏里改、同系列新开一页时接上)。
  void setCast(Map<String, String> cast) => _set(_layout.copyWith(cast: cast));

  /// 开 / 关 3D 视图。打开时还没有体块的块先按图层猜一个(之后可以让 Agent 估)。
  ///
  /// 平面转 3D:开着透视辅助、镜头还没转过时,先照透视线定出镜头(俯仰、环绕、视角,
  /// 见 [cameraFromPerspective]),已有的体块按原来的远近、厚度、朝向在新镜头下重新立起来,
  /// 框一点不动;之后透视线跟着镜头走。描述本来就是照这个透视写的,不算转过镜头。
  void setThreeD(bool on) {
    _threeD = on;
    if (!on) {
      _freeCam = false;
      return notifyListeners();
    }
    var l = _layout;
    final per = l.perspective;
    if (per != null && l.camera.isDefault) {
      final before = CameraView(l.camera, l.width, l.height);
      final next = l.copyWith(
        camera: cameraFromPerspective(per, l.camera, l.width, l.height),
      );
      l = next.copyWith(
        boxes: [
          for (final b in l.boxes)
            b.body == null || b.label == 'text'
                ? b
                : liftBox(b, next, hintOf(b.body!, before)),
        ],
      );
      _described = l.camera;
    }
    l = l.copyWith(boxes: liftMissing(l));
    if (per != null) {
      l = l.copyWith(
        perspective: () =>
            perspectiveFromCamera(l.camera, l.width, l.height, per.points),
      );
    }
    _set(l);
  }

  /// 开 / 关自由镜头(只在 3D 视图里)。
  void setFreeCam(bool on) {
    if (on == _freeCam || on && !_threeD) return;
    _freeCam = on;
    _freeUnlogged = on;
    notifyListeners();
  }

  /// 自由镜头里转头、走动:一趟只在第一次挪动时记一笔操作。
  void moveFree(Camera camera) {
    if (camera == _layout.camera) return;
    setCamera(camera, action: _freeUnlogged ? tr('自由镜头') : null);
    _freeUnlogged = false;
  }

  /// 在画布上屏蔽 / 显示第 [i] 块(交出去的 JSON 不受影响)。
  void setHidden(int i, bool hidden) {
    if (i < 0 || i >= _layout.boxes.length) return;
    final b = _layout.boxes[i];
    if (hidden && _selected == i) _selected = null;
    _set(
      _layout.copyWith(
        boxes: [
          for (final (j, x) in _layout.boxes.indexed)
            j == i ? x.copyWith(hidden: () => hidden) : x,
        ],
      ),
      action: hidden
          ? tr('屏蔽「{0}」', [boxName(b, i)])
          : tr('显示「{0}」', [boxName(b, i)]),
    );
  }

  /// 换镜头:有体块的框照新镜头重新算,前后跟着远近排(见 [reprojectBoxes])。
  void setCamera(Camera camera, {String? action}) {
    if (camera == _layout.camera) return;
    _reproject(_layout.copyWith(camera: camera), action: action);
  }

  /// 手动改第 [i] 块的体块(摄像机栏里的位置、宽高厚、朝向):框照新的体块重新投出来,
  /// 不再算"猜的"。
  void setBody(int i, Body body, {String? action}) {
    if (i < 0 || i >= _layout.boxes.length) return;
    _reproject(
      _layout.copyWith(
        boxes: [
          for (final (j, b) in _layout.boxes.indexed)
            j == i ? b.copyWith(body: () => body.copyWith(guessed: false)) : b,
        ],
      ),
      action: action,
    );
  }

  /// 换成 [l],有体块的框照它的镜头重新投(见 [reprojectBoxes]),选中的跟着那一块走。
  void _reproject(Layout l, {String? action}) {
    // 3D 视图里透视线就是镜头:镜头一变,跟着重新算。
    final per = l.perspective;
    if (_threeD && per != null) {
      l = l.copyWith(
        perspective: () =>
            perspectiveFromCamera(l.camera, l.width, l.height, per.points),
      );
    }
    final moved = reprojectBoxes(l);
    final sel = _selected;
    _set(
      l.copyWith(boxes: [for (final m in moved) m.$2]),
      rebuild: [for (final (i, m) in moved.indexed) m.$1 != i].contains(true),
      follow: sel == null ? null : moved.firstWhere((m) => m.$1 == sel).$2,
      action: action,
    );
  }

  /// 加一个框并选中它:放在它那一层的最前面(像 PS 新建的图层在最上面)。
  /// 先按图层给它猜一个体块,3D 视图里马上就有。
  void addBox(LayoutBox box) {
    box = liftBox(box, _layout);
    final at = _layout.boxes.indexWhere(
      (b) => _rank(b.layer) <= _rank(box.layer),
    );
    final boxes = [..._layout.boxes]
      ..insert(at < 0 ? _layout.boxes.length : at, box);
    _set(
      _layout.copyWith(boxes: boxes),
      follow: box,
      action: tr('画了一个框'),
    );
  }

  /// 换掉第 [i] 块。位置或大小变了时体块跟着调(见 [refitBody])。
  void updateBox(int i, LayoutBox box) {
    if (i < 0 || i >= _layout.boxes.length) return;
    final old = _layout.boxes[i];
    if ((box.left, box.top, box.right, box.bottom) !=
        (old.left, old.top, old.right, old.bottom)) {
      box = refitBody(box, _layout);
    }
    _set(
      _layout.copyWith(
        boxes: [for (final (j, b) in _layout.boxes.indexed) j == i ? box : b],
      ),
      // 改了前中后景时它会挪到别处,选中的跟着它走。
      follow: _selected == i ? box : null,
    );
  }

  /// 拖着换前后:把第 [from] 块挪到第 [to] 个位置(按挪走之后的列表数)。
  /// 前、中、后景跟着落点变:夹在两个前景之间的就成了前景,拖到前景和中景之间的
  /// 尽量保持原来那一层。
  void move(int from, int to) {
    final boxes = [..._layout.boxes];
    if (from < 0 || from >= boxes.length) return;
    final b = boxes.removeAt(from);
    final at = to.clamp(0, boxes.length);
    final above = at > 0 ? _rank(boxes[at - 1].layer) : layoutLayers.length - 1;
    final below = at < boxes.length ? _rank(boxes[at].layer) : 0;
    final moved = b.copyWith(
      layer: layoutLayers[_rank(b.layer).clamp(below, above)],
    );
    boxes.insert(at, moved);
    _set(
      _layout.copyWith(boxes: boxes),
      rebuild: true,
      follow: moved,
      action: tr('调整「{0}」的前后', [boxName(b, from)]),
    );
  }

  void removeBox(int i) {
    if (i < 0 || i >= _layout.boxes.length) return;
    _selected = null;
    _set(
      _layout.copyWith(
        boxes: [
          for (final (j, b) in _layout.boxes.indexed)
            if (j != i) b,
        ],
      ),
      rebuild: true,
      action: tr('删除「{0}」', [boxName(_layout.boxes[i], i)]),
    );
  }

  /// 清掉描述和所有的框,画布尺寸和镜头留着。
  void clear() {
    _selected = null;
    _set(
      Layout(
        width: _layout.width,
        height: _layout.height,
        camera: _layout.camera,
      ),
      rebuild: true,
      action: tr('清空画板'),
    );
  }

  /// 只收 Agent 写的描述,和程序猜的那几块的体块([LayoutKeep.describe];
  /// 用户调过、Agent 估过的体块不动,免得每交一次就漂一点):
  /// 按名字对上每一块(没名字按先后),框、形状、图层、名字、画布都照旧。
  bool _applyOnly(LayoutRead read, LayoutKeep keep) {
    final old = _layout;
    final got = read.layout.boxes;
    final visible = [
      for (final (i, b) in old.boxes.indexed)
        if (!b.offscreen) i,
    ];
    int? match(LayoutBox b, int k) {
      final byName = b.name.isEmpty
          ? -1
          : got.indexWhere((g) => g.name.trim() == b.name);
      return byName >= 0 ? byName : (k < got.length ? k : null);
    }

    final boxes = [...old.boxes];
    for (final (k, i) in visible.indexed) {
      final b = old.boxes[i];
      final j = match(b, k);
      if (j == null) continue;
      final hint = read.hints[j];
      final described = b.copyWith(
        caption: got[j].caption.trim().isEmpty ? null : got[j].caption,
        text: got[j].text.trim().isEmpty ? null : got[j].text,
      );
      boxes[i] = hint != null && b.label != 'text' && (b.body?.guessed ?? true)
          ? liftBox(described, old, hint)
          : described;
    }
    final caption = read.layout.caption.trim();
    _selected = null;
    _set(
      old.copyWith(boxes: boxes, caption: caption.isNotEmpty ? caption : null),
      rebuild: true,
      action: tr('Agent 放上布局'),
    );
    _fixes = const [];
    _refit = null;
    return true;
  }

  /// 整个换成 [layout](换页、回滚、从档案库放回来的),画布尺寸和镜头也跟着换。
  void replace(Layout layout) {
    _selected = null;
    _described = layout.camera;
    _set(layout, rebuild: true);
  }

  /// 换成一份布局 JSON(Agent 写的)。JSON 里写了画布宽高就换成它的
  /// (Agent 换横竖构图时),没写用当前的画布尺寸。读不了返回 false。
  /// [keep] 不是 none 时只收描述或体块,见 [_applyOnly]。
  bool apply(String json, {LayoutKeep keep = LayoutKeep.none}) {
    final read = readMossLayout(
      json,
      width: _layout.width,
      height: _layout.height,
      ownSize: true,
    );
    if (read == null) return false;
    final old = _layout;
    if (keep != LayoutKeep.none) return _applyOnly(read, keep);
    // 镜头是用户转的,JSON 里没有它:留着,Agent 写的框就是从这个镜头看到的。
    // 画风定了之后 Agent 不再写(要换画风才写),没写就沿用。
    final parsed = read.layout.copyWith(
      camera: old.camera,
      style: read.layout.style.trim().isEmpty ? old.style : null,
      // 角色卡同理;Agent 只写新加的或改的那几张,盖在原来的上面。
      cast: {...old.cast, ...read.layout.cast},
      lighting: old.lighting,
    );
    final sx = parsed.width / old.width, sy = parsed.height / old.height;
    // Agent 常把 name、layer 漏掉:按名字或位置把原来的接上(见 inheritNames)。
    // 转到镜头外的块 Agent 看不到,不参与对号,原样留在最后。
    final inherited = inheritNames(
      [
        for (final b in old.boxes)
          if (!b.offscreen) b.scaled(sx, sy),
      ],
      parsed.boxes,
      keepLayers: !json.contains('"layer"'),
    );
    // 体块:Agent 写了照它立;没写的沿用原来那块的(调到新框上);都没有就猜一个。
    final boxes = [
      for (final (i, b) in inherited.indexed)
        switch (read.hints[i]) {
          final hint? => liftBox(b, parsed, hint),
          null when b.body != null && b.label != 'text' => refitBody(b, parsed),
          null => liftBox(b, parsed),
        },
      for (final b in old.boxes)
        if (b.offscreen) b,
    ];
    _selected = null;
    _described = old.camera;
    // 透视线是用户拉的,JSON 里没有它:留着,画布换了尺寸就跟着缩放。
    _set(
      parsed.copyWith(
        boxes: boxes,
        perspective: () => old.perspective?.scaled(sx, sy),
      ),
      rebuild: true,
      action: tr('Agent 放上布局'),
    );
    _fixes = read.fixes;
    _refit = read.refit;
    return true;
  }

  /// 告诉 Agent 它上次写的布局被改了哪几处(发给模型的话,不翻译),下次照画布范围写对。
  String _fixesNote() {
    final l = _layout, size = _refit;
    final refit = size == null
        ? ''
        : '\n你上次写的 width / height 是 ${size.width}×${size.height},'
              '和画布 ${l.width}×${l.height} 对不上(大概是照着参考图的比例写的):'
              '程序把整份布局等比摆进了画布正中,贴边的框撑到画布边。'
              '参考图只看内容和横竖,下次直接按 ${l.width}×${l.height} 排。\n';
    if (_fixes.isEmpty) return refit;
    String who(LayoutFix f) =>
        '第 ${f.item} 项${f.name.isEmpty ? '' : '「${f.name}」'}';
    final clipped = [
      for (final f in _fixes)
        if (f.clipped) who(f),
    ];
    final dropped = [
      for (final f in _fixes)
        if (!f.clipped) who(f),
    ];
    return '\n你上次写的布局放到画板时,程序改了几处:'
        '${clipped.isEmpty ? '' : '${clipped.join('、')}超出画布,已截到画布里;'}'
        '${dropped.isEmpty ? '' : '${dropped.join('、')}的 bbox 读不了或没有面积,已去掉;'}'
        '用户要接着改这些块时,照上面的范围重写。\n$refit';
  }

  /// 最近一次 [apply] 时 Agent 写的画布宽高:比例和画布对不上、等比摆进来的;
  /// 对得上是 null。画板再有别的改动就清空。
  ({int width, int height})? get refit => _refit;
  ({int width, int height})? _refit;

  /// 最近一次 [apply] 时替 Agent 改掉的地方;画板再有别的改动就清空。
  List<LayoutFix> get fixes => _fixes;
  List<LayoutFix> _fixes = const [];

  File? get _file => dir == null
      ? null
      : File('${dir!.path}${Platform.pathSeparator}layout.json');

  void _scheduleSave() {
    if (_file == null) return;
    // 拖框时每一帧都在变:停下来一会儿再存。
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'layout': _layout.toJson(),
            'sizes': [
              for (final s in _sizes) [s.width, s.height],
            ],
          }),
          flush: true,
        )
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('布局没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final loaded = Layout.fromJson(j['layout'] as Map<String, dynamic>);
      _layout = loaded.copyWith(boxes: stacked(loaded.boxes));
      _described = loaded.camera;
      _sizes = List.unmodifiable([
        for (final s in j['sizes'] as List? ?? const [])
          if (s is List &&
              s.length == 2 &&
              _validSide(s[0]) &&
              _validSide(s[1]))
            (width: s[0] as int, height: s[1] as int),
      ]);
      _revision++;
      notifyListeners();
    } on Object {
      // 读不了就从默认的空画板开始;文件先改名留个底,不让下一次保存把它盖掉。
      try {
        file.renameSync(
          '${file.path}.bad-${DateTime.now().millisecondsSinceEpoch}',
        );
      } on FileSystemException {
        // 留底失败也不拦着程序启动。
      }
    }
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _save();
    }
    super.dispose();
  }
}

/// 只读图片的宽高,不解出整张图。读不了返回 null。
Future<({int width, int height})?> _imageSize(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final d = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: d.width, height: d.height);
    d.dispose();
    buffer.dispose();
    return size;
  } on Object {
    return null;
  }
}

int _rank(String layer) => layoutLayers.indexOf(layer);

/// 按前后排好:第 0 个在最前面,前景、中景、后景依次往后,同一层里保持原来的先后
/// (`mergeSort` 是稳定排序)。画布倒着画,后画的盖住先画的。
List<LayoutBox> stacked(List<LayoutBox> boxes) {
  final out = [...boxes];
  mergeSort(out, compare: (a, b) => _rank(b.layer) - _rank(a.layer));
  return out;
}

/// 记操作时怎么叫第 [i] 块:有名字用名字。
String boxName(LayoutBox b, int i) =>
    b.name.trim().isEmpty ? tr('第 {0} 块', [i + 1]) : b.name.trim();

/// 说给模型听的图层名。
const _layerNames = {'back': '后景', 'middle': '中景', 'front': '前景'};

bool _validSide(Object? v) =>
    v is int && v >= minLayoutSide && v <= maxLayoutSide;
