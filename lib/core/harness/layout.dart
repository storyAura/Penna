import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'camera.dart';
import 'lighting.dart';
import 'perspective.dart';

export 'camera.dart';
export 'lighting.dart';
export 'perspective.dart';

part 'layout_cast.dart';
part 'layout_shape.dart';
part 'layout_tags.dart';

/// MOSS-Image 布局提示词(Layout Prompt):画面整体描述 + 一组带位置框的元素,
/// 写成官方的 JSON。框在这里按常规的左上角原点、整数像素存,交出去时才换成
/// `abs_centralized`(画布中心为原点)和 `yxyx`([y_min, x_min, y_max, x_max])。
/// 和 Agent 来回用的是官方的草稿格式(`abs` + `xyxy`,左上角原点):
/// 照官方 enhancer 技能的做法,坐标换算交给程序,不让模型心算。

const layoutLabels = ['object', 'character', 'text'];
const layoutCanvases = ['single', 'multi_panel', 'collage'];

/// 图层:后景、中景、前景。画布上前面的盖住后面的;同一层里后加的在上面。
const layoutLayers = ['back', 'middle', 'front'];
const defaultLayer = 'middle';

const defaultLayoutWidth = 832, defaultLayoutHeight = 1216;

/// 画布边长的范围(像素)。
const minLayoutSide = 64, maxLayoutSide = 4096;

/// 画面里的一个元素:[label] 是类别,[caption] 是这块的描述,
/// [text] 是要画出来的文字(只有 text 类用)。坐标是左上角原点的像素。
/// [name] 是给这一块起的名字,[layer] 是它在哪一层(见 [layoutLayers]),
/// 两样都只在 Penna 里用(用户和 Agent 靠它们说"哪一块"、谁挡着谁),
/// 官方格式不认,交出去的 JSON 里没有。[body] 是它在 3D 视图里的体块(文字块没有)。
/// [hidden] 是在画布上暂时屏蔽(只是不画、点不中,交出去的 JSON 照常带着):
/// null 是没设过,按视图来定(见 [shownIn])。[shape] 是框里的异形(null 是方框,
/// 见 [LayoutShape]),框始终是它的外框。[locked] 是用户锁住了它:画布上点不中、拖不动,
/// 在它占的地方能接着画新框(Agent 照样能改)。
@immutable
class LayoutBox {
  const LayoutBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.label = 'object',
    this.caption = '',
    this.text = '',
    this.name = '',
    this.layer = defaultLayer,
    this.body,
    this.hidden,
    this.shape,
    this.locked = false,
  });

  final int left, top, right, bottom;
  final String label, caption, text, name, layer;
  final Body? body;
  final bool? hidden;
  final LayoutShape? shape;
  final bool locked;

  /// 画布上画不画它:转到镜头外看不见了([offscreen])就算屏蔽着;用户点过眼睛
  /// 就照他的;没点过的,3D 视图里文字块默认屏蔽(文字贴在画面上不跟镜头转,
  /// 在 3D 里只会挡住别的块)。
  bool shownIn({required bool threeD}) =>
      !offscreen && !(hidden ?? (threeD && label == 'text'));

  int get width => right - left;
  int get height => bottom - top;

  /// 转镜头时整个跑到了镜头外面(框缩成了没有面积):交出去的 JSON 里不带它。
  bool get offscreen => width <= 0 || height <= 0;

  Span get span => (
    left: left.toDouble(),
    top: top.toDouble(),
    right: right.toDouble(),
    bottom: bottom.toDouble(),
  );

  LayoutBox copyWith({
    int? left,
    int? top,
    int? right,
    int? bottom,
    String? label,
    String? caption,
    String? text,
    String? name,
    String? layer,
    Body? Function()? body,
    bool? Function()? hidden,
    LayoutShape? Function()? shape,
    bool? locked,
  }) => LayoutBox(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
    label: label ?? this.label,
    caption: caption ?? this.caption,
    text: text ?? this.text,
    name: name ?? this.name,
    layer: layer ?? this.layer,
    body: body == null ? this.body : body(),
    hidden: hidden == null ? this.hidden : hidden(),
    shape: shape == null ? this.shape : shape(),
    locked: locked ?? this.locked,
  );

  /// 按比例缩到另一块画布上(换画布尺寸时用)。
  LayoutBox scaled(double sx, double sy) => copyWith(
    left: (left * sx).round(),
    top: (top * sy).round(),
    right: (right * sx).round(),
    bottom: (bottom * sy).round(),
  );

  Map<String, Object> toJson() => {
    'box': [left, top, right, bottom],
    'label': label,
    'caption': caption,
    'text': text,
    'name': name,
    'layer': layer,
    'body': ?body?.toJson(),
    'hidden': ?hidden,
    'shape': ?shape?.toJson(),
    if (locked) 'locked': true,
  };

  static LayoutBox? fromJson(Object? j) {
    if (j is! Map || j['box'] is! List) return null;
    final b = [for (final v in j['box'] as List) (v as num).round()];
    if (b.length != 4) return null;
    return LayoutBox(
      left: b[0],
      top: b[1],
      right: b[2],
      bottom: b[3],
      label: _pick(j['label'], layoutLabels),
      caption: j['caption'] as String? ?? '',
      text: j['text'] as String? ?? '',
      name: j['name'] as String? ?? '',
      layer: _layer(j['layer']),
      body: Body.fromJson(j['body']),
      hidden: j['hidden'] is bool ? j['hidden'] as bool : null,
      shape: LayoutShape.fromJson(j['shape']),
      locked: j['locked'] == true,
    );
  }
}

/// 一张布局:画布尺寸、整体描述([meta] 是逗号隔开的几个类型词)和各个元素。
/// [style] 是画风(Agent 照参考图或描述反推的一段,同系列沿用),交出去时拼在 caption 前面。
/// [cast] 是本系列的角色卡(名字 → 英文描述,同系列沿用),交出去时接在人物块前面(见 layout_cast.dart)。
@immutable
class Layout {
  const Layout({
    this.width = defaultLayoutWidth,
    this.height = defaultLayoutHeight,
    this.caption = '',
    this.style = '',
    this.cast = const {},
    this.meta = '',
    this.canvas = 'single',
    this.boxes = const [],
    this.perspective,
    this.camera = const Camera(),
    this.lighting = const Lighting(),
  });

  final int width, height;
  final String caption, style, meta, canvas;
  final Map<String, String> cast;
  final List<LayoutBox> boxes;

  /// 透视辅助线;null 是没开。
  final Perspective? perspective;

  /// 3D 视图的摄像机;没转过是默认的(正对着画布)。
  final Camera camera;

  /// 打光辅助(关着是默认的);交出去时写成一句光影接在 summary.caption 后面。
  final Lighting lighting;

  bool get isEmpty => boxes.isEmpty && caption.trim().isEmpty;

  Layout copyWith({
    int? width,
    int? height,
    String? caption,
    String? style,
    Map<String, String>? cast,
    String? meta,
    String? canvas,
    List<LayoutBox>? boxes,
    Perspective? Function()? perspective,
    Camera? camera,
    Lighting? lighting,
  }) => Layout(
    width: width ?? this.width,
    height: height ?? this.height,
    caption: caption ?? this.caption,
    style: style ?? this.style,
    cast: cast == null ? this.cast : Map.unmodifiable(cast),
    meta: meta ?? this.meta,
    canvas: canvas ?? this.canvas,
    boxes: boxes == null ? this.boxes : List.unmodifiable(boxes),
    perspective: perspective == null ? this.perspective : perspective(),
    camera: camera ?? this.camera,
    lighting: lighting ?? this.lighting,
  );

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'caption': caption,
    if (style.isNotEmpty) 'style': style,
    if (cast.isNotEmpty) 'cast': cast,
    'meta': meta,
    'canvas': canvas,
    'boxes': [for (final b in boxes) b.toJson()],
    'perspective': ?perspective?.toJson(),
    if (!camera.isDefault) 'camera': camera.toJson(),
    if (lighting != const Lighting()) 'lighting': lighting.toJson(),
  };

  static Layout fromJson(Map<String, dynamic> j) => Layout(
    width: _side(j['width'], defaultLayoutWidth),
    height: _side(j['height'], defaultLayoutHeight),
    caption: j['caption'] as String? ?? '',
    style: j['style'] as String? ?? '',
    cast: parseCast(j['cast']),
    meta: j['meta'] as String? ?? '',
    canvas: _pick(j['canvas'], layoutCanvases),
    boxes: List.unmodifiable([
      for (final b in j['boxes'] as List? ?? const []) ?LayoutBox.fromJson(b),
    ]),
    perspective: Perspective.fromJson(j['perspective']),
    camera: Camera.fromJson(j['camera']),
    lighting: Lighting.fromJson(j['lighting']),
  );
}

/// 交出去的 summary.caption:质量词、画风、整体描述、这页的角色卡连成一段,
/// 开着打光辅助时最后接上光影。导入过交出去的 JSON 时整体描述里已经带着它们,不再加一遍。
String _fullCaption(Layout l, String quality) {
  final caption = l.caption.trim();
  final cast = _castLine(l);
  return appendLighting(
    [
      for (final s in [quality.trim(), l.style.trim()])
        if (s.isNotEmpty && !caption.contains(s)) _sentence(s),
      caption,
      if (cast.isNotEmpty && !caption.contains(cast)) cast,
    ].where((s) => s.isNotEmpty).join(' '),
    l.lighting,
    l.camera,
  );
}

String _pick(Object? v, List<String> allowed) =>
    v is String && allowed.contains(v.trim()) ? v.trim() : allowed.first;

String _layer(Object? v) =>
    v is String && layoutLayers.contains(v.trim()) ? v.trim() : defaultLayer;

int _side(Object? v, int fallback) =>
    v is num ? v.round().clamp(minLayoutSide, maxLayoutSide) : fallback;

/// 写成 MOSS-Image 的布局 JSON。换算照官方 compile_prompt.py:减去宽高的一半(整除);
/// 画布尺寸不写进去(生成时另设)。summary.caption 依次是 [quality]、画风、整体描述
/// (官方格式没有放画风的字段)。
///
/// [draft] 为真时是给 Agent 看的草稿格式:带画布尺寸,坐标是左上角原点的
/// `[x_min, y_min, x_max, y_max]`,每一块还带上 `name`、`layer` 和体块 `body`
/// (见 [bodyHintJson];官方格式不认,交出去的不带)。转镜头转到镜头外面的块两种都不带。
/// 草稿里 caption 只是整体描述:画风另外告诉 Agent(见 `_layoutPagesPrompt`),质量词它不用管。
String mossLayoutJson(Layout l, {bool draft = false, String quality = ''}) {
  final w2 = l.width ~/ 2, h2 = l.height ~/ 2;
  final view = CameraView(l.camera, l.width, l.height);
  final meta = [
    for (final m in l.meta.split(RegExp('[,,、]')))
      if (m.trim().isNotEmpty) m.trim(),
  ];
  return const JsonEncoder.withIndent('  ').convert({
    if (draft) 'width': l.width,
    if (draft) 'height': l.height,
    'summary': {
      if (meta.isNotEmpty) 'meta': meta,
      'canvas': l.canvas,
      'caption': draft ? l.caption.trim() : _fullCaption(l, quality),
    },
    'items': [
      for (final b in l.boxes)
        if (!b.offscreen)
          {
            if (draft && b.name.trim().isNotEmpty) 'name': b.name.trim(),
            if (draft) 'layer': b.layer,
            if (draft && b.body != null) 'body': bodyHintJson(b.body!, view),
            if (draft) 'shape': ?b.draftShape,
            'label': b.label,
            'caption': draft ? b.caption.trim() : _castCaption(l, b),
            if (b.label == 'text' && b.text.trim().isNotEmpty)
              'text': b.text.trim(),
            'bbox': draft
                ? [b.left, b.top, b.right, b.bottom]
                : [b.top - h2, b.left - w2, b.bottom - h2, b.right - w2],
          },
    ],
    'bbox_coord_space': draft ? 'abs' : 'abs_centralized',
    'bbox_format': draft ? 'xyxy' : 'yxyx',
  });
}

/// 读布局时程序替模型改掉的一处:[item] 是它在 items 里排第几(从 1 数),
/// [clipped] 为真是超出画布、截到了画布里,为假是读不了或没有面积、去掉了。
typedef LayoutFix = ({int item, String name, bool clipped});

/// [readMossLayout] 读出来的:布局、替模型改掉的地方、等比摆入前的宽高、各块的体块提示。
typedef LayoutRead = ({
  Layout layout,
  List<LayoutFix> fixes,
  ({int width, int height})? refit,
  Map<int, BodyHint> hints,
});

/// 读回一份布局 JSON(Agent 写的,或用户贴的),放到 [width]×[height] 的画布上。
/// 框超出画布的截掉,上下、左右写反的摆正,截完没有面积的不要。读不了返回 null。
Layout? parseMossLayout(
  String raw, {
  required int width,
  required int height,
}) => readMossLayout(raw, width: width, height: height)?.layout;

/// 同 [parseMossLayout],另外交回替模型改掉的地方(超出画布截掉的、去掉的块)。
/// `bbox_coord_space` 是 `abs` 时坐标从左上角量(官方草稿格式),否则从画布中心量。
/// [ownSize] 为真时看 JSON 里写的画布宽高(草稿格式带着):框按它读,再缩放到画布上;
/// 它和 [width]×[height] 一横一竖时画布对调(Agent 换横竖构图)。别的比例不认:
/// 画布尺寸由用户定,Agent 照参考图写出 1216×684 这种时,画布还是 1216×832。
LayoutRead? readMossLayout(
  String raw, {
  required int width,
  required int height,
  bool ownSize = false,
}) {
  // 模型常把 JSON 套进代码块。
  final text = raw
      .trim()
      .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '');
  final Object? j;
  try {
    j = jsonDecode(_repairJson(text));
  } on FormatException {
    return null;
  }
  if (j is! Map) return null;
  final root = j;
  final summary = root['summary'] is Map ? root['summary'] as Map : const {};
  // 模型漏写 summary 的右括号时,items 这几项会落进 summary 里:从那里也找。
  Object? field(String key) => root[key] ?? summary[key];
  final own = ownSize ? _ownSize(field('width'), field('height')) : null;
  // 画布只对调,不换比例。
  final flip =
      own != null &&
      own.width != own.height &&
      width != height &&
      (own.width > own.height) != (width > height);
  final tw = flip ? height : width, th = flip ? width : height;
  final xyxy = field('bbox_format') == 'xyxy';
  // 照参考图排时 Agent 在图上量 0–1000 的比例(看图的模型量比例比换算像素准):
  // 写 "ref1000",程序按画布拉伸过去,贴边、出血的照样贴边。
  final ref = field('bbox_coord_space') == 'ref1000';
  final abs = ref || field('bbox_coord_space') == 'abs';
  final items = field('items');
  List<double> bbox(Object? item) => [
    for (final n
        in item is Map && item['bbox'] is List
            ? item['bbox'] as List
            : const [])
      if (n is num) n.toDouble(),
  ];
  final all = [
    for (final item in items is List ? items : const [])
      if (bbox(item).length == 4) bbox(item),
  ];
  // 框按 JSON 里写的宽高读进 w×h,最后再缩放到画布上。
  var w = own?.width ?? tw, h = own?.height ?? th;
  // Gemini 看图时习惯写 0–1000 的比例坐标:有框远远超出写的宽高(多出一成以上),
  // 而所有数都在 0 到 1000 之间,就按 1000×1000 读。
  // 只在它自己写了宽高时这样认(照着参考图写的);没写宽高的出界照常截掉。
  final perMille = ref || abs && own != null && _perMille(all, xyxy, w, h);
  if (perMille) w = h = 1000;
  final dx = abs ? 0 : w ~/ 2, dy = abs ? 0 : h ~/ 2;
  final boxes = <LayoutBox>[];
  final fixes = <LayoutFix>[];
  // Agent 写的体块(按 boxes 里的第几块记),换成画板上的体块要等知道镜头之后。
  final hints = <int, BodyHint>{};
  for (final (i, item) in (items is List ? items : const []).indexed) {
    if (item is! Map) continue;
    final name = item['name'] is String ? item['name'] as String : '';
    final v = bbox(item);
    // 多边形的顶点和 bbox 同一套坐标,一律 [x, y]。框以 bbox 为准、形状拉伸到框里
    // (Agent 挪块时常只改 bbox、照抄原来的顶点);没写 bbox 才拿顶点的外框当框。
    final poly = _pairs(item['shape']);
    if (v.length != 4 && poly == null) {
      fixes.add((item: i + 1, name: name, clipped: false));
      continue;
    }
    final (y0, x0, y1, x1) = v.length == 4
        ? xyxy
              ? (v[1], v[0], v[3], v[2])
              : (v[0], v[1], v[2], v[3])
        : (
            poly!.map((p) => p.$2).reduce(math.min),
            poly.map((p) => p.$1).reduce(math.min),
            poly.map((p) => p.$2).reduce(math.max),
            poly.map((p) => p.$1).reduce(math.max),
          );
    // 超出一个像素以内是取整的误差,不算。
    final out =
        [x0, x1].any((n) => n + dx < -1 || n + dx > w + 1) ||
        [y0, y1].any((n) => n + dy < -1 || n + dy > h + 1);
    int x(double n) => (n + dx).round().clamp(0, w);
    int y(double n) => (n + dy).round().clamp(0, h);
    final rect = LayoutBox(
      left: math.min(x(x0), x(x1)),
      top: math.min(y(y0), y(y1)),
      right: math.max(x(x0), x(x1)),
      bottom: math.max(y(y0), y(y1)),
      label: _pick(item['label'], layoutLabels),
      caption: item['caption'] is String ? item['caption'] as String : '',
      text: item['text'] is String ? item['text'] as String : '',
      name: name,
      layer: _layer(item['layer']),
    );
    final box = rect.copyWith(
      shape: () => switch (item['shape']) {
        'ellipse' => const LayoutShape.ellipse(),
        'rect' => LayoutShape.box,
        _ when poly != null => LayoutShape.polygon(_normalize(poly)),
        _ => null,
      },
    );
    if (box.width > 0 && box.height > 0) {
      if (parseBodyHint(item['body']) case final hint?) {
        hints[boxes.length] = hint;
      }
      boxes.add(box);
      if (out) fixes.add((item: i + 1, name: name, clipped: true));
    } else {
      fixes.add((item: i + 1, name: name, clipped: false));
    }
  }
  final meta = summary['meta'];
  // 写的宽高比例和画布不一样(照着参考图写的):不压扁拉长,见 [_fit]。
  final refit = own != null && !perMille && (w, h) != (tw, th) ? own : null;
  final layout = Layout(
    width: tw,
    height: th,
    caption: summary['caption'] is String ? summary['caption'] as String : '',
    style: summary['style'] is String ? summary['style'] as String : '',
    cast: parseCast(summary['cast']),
    meta: meta is List
        ? meta.whereType<String>().join(', ')
        : meta is String
        ? meta
        : '',
    canvas: _pick(summary['canvas'], layoutCanvases),
    boxes: List.unmodifiable([
      for (final b in boxes)
        tw == w && th == h
            ? b
            : refit != null
            ? _fit(b, w, h, tw, th)
            : b.scaled(tw / w, th / h),
    ]),
  );
  return (
    layout: layout,
    fixes: List.unmodifiable(fixes),
    refit: refit,
    hints: Map.unmodifiable(hints),
  );
}

/// 把 [w]×[h] 上的框摆到 [tw]×[th] 的画布上:等比缩放、放在正中,形状不变;
/// 贴着边的框撑到画布的边(背景、横贯的标题还是铺满)。
LayoutBox _fit(LayoutBox b, int w, int h, int tw, int th) {
  final s = math.min(tw / w, th / h);
  final ox = (tw - w * s) / 2, oy = (th - h * s) / 2;
  return b.copyWith(
    left: b.left <= 0 ? 0 : (b.left * s + ox).round(),
    top: b.top <= 0 ? 0 : (b.top * s + oy).round(),
    right: b.right >= w ? tw : (b.right * s + ox).round(),
    bottom: b.bottom >= h ? th : (b.bottom * s + oy).round(),
  );
}

/// 这些框(左上角原点)是不是 0–1000 的比例坐标:有框在 [w]×[h] 外面多出一成以上,
/// 而所有的数都在 0 到 1000 之间。只是稍微画出界的不算,照常截掉。
bool _perMille(List<List<double>> boxes, bool xyxy, int w, int h) {
  if (boxes.isEmpty || boxes.expand((b) => b).any((n) => n < 0 || n > 1000)) {
    return false;
  }
  return boxes.any((b) {
    final (xs, ys) = xyxy
        ? ([b[0], b[2]], [b[1], b[3]])
        : ([b[1], b[3]], [b[0], b[2]]);
    return xs.any((n) => n > w * 1.1) || ys.any((n) => n > h * 1.1);
  });
}

/// JSON 里写的画布宽高;没写、不是数或超出边长范围时为 null。
({int width, int height})? _ownSize(Object? width, Object? height) {
  bool ok(Object? v) =>
      v is num && v.round() >= minLayoutSide && v.round() <= maxLayoutSide;
  if (!ok(width) || !ok(height)) return null;
  return (width: (width as num).round(), height: (height as num).round());
}

/// 新写的布局 [fresh] 漏了 name、layer 时,从原来的 [old] 里接上;体块和屏蔽
/// (JSON 里没有)也接上原来那块的。
/// 先按名字对号;没写名字的,块数没变时接离它中心最近、还没被认领的那块
/// (Agent 常把先后换了,按下标接会接错)。[keepLayers] 为真时 layer 也照原来的。
List<LayoutBox> inheritNames(
  List<LayoutBox> old,
  List<LayoutBox> fresh, {
  required bool keepLayers,
}) {
  final taken = <int>{};
  final match = List<int?>.filled(fresh.length, null);
  for (final (i, b) in fresh.indexed) {
    final name = b.name.trim();
    if (name.isEmpty) continue;
    final at = old.indexWhere((o) => o.name.trim() == name);
    if (at >= 0 && taken.add(at)) match[i] = at;
  }
  if (old.length == fresh.length) {
    // 两块中心距离的平方(乘 2 的坐标,比大小够用)。
    int gap(LayoutBox a, LayoutBox b) {
      final dx = (a.left + a.right) - (b.left + b.right);
      final dy = (a.top + a.bottom) - (b.top + b.bottom);
      return dx * dx + dy * dy;
    }

    for (final (i, b) in fresh.indexed) {
      if (match[i] != null || b.name.trim().isNotEmpty) continue;
      int? best;
      for (var j = 0; j < old.length; j++) {
        if (taken.contains(j)) continue;
        if (best == null || gap(b, old[j]) < gap(b, old[best])) best = j;
      }
      if (best != null && taken.add(best)) match[i] = best;
    }
  }
  // 形状:没写的照原来那块的,写了 "rect" 的换回方框。
  LayoutShape? shape(LayoutBox b, int? j) => identical(b.shape, LayoutShape.box)
      ? null
      : b.shape ?? (j == null ? null : old[j].shape);
  return [
    for (final (i, b) in fresh.indexed)
      switch (match[i]) {
        null => b.copyWith(shape: () => shape(b, null)),
        final j => b.copyWith(
          name: b.name.trim().isEmpty ? old[j].name : null,
          layer: keepLayers ? old[j].layer : null,
          body: () => old[j].body,
          hidden: () => old[j].hidden,
          shape: () => shape(b, j),
          locked: old[j].locked,
        ),
      },
  ];
}

/// 画布边长取 [step] 的倍数(MOSS-Image 要 16,用户在设置里能改):取最近的一个,
/// 并留在 [minLayoutSide] 到 [max] 之间,贴着两头时也取范围里的倍数。
int snapLayoutSide(int v, int step, {int max = maxLayoutSide}) {
  final lo = (minLayoutSide + step - 1) ~/ step * step;
  final hi = max ~/ step * step;
  return ((v / step).round() * step).clamp(lo, hi);
}

/// 模型写的 JSON 常差一点:从第一个 `{` 开始取,去掉 `}`、`]` 前多余的逗号,
/// 末尾缺的右括号按顺序补上。字符串里的字一个不动。
String _repairJson(String text) {
  final start = text.indexOf('{');
  if (start < 0) return text;
  final out = StringBuffer();
  final open = <String>[];
  var inString = false, escaped = false;
  for (final ch in text.substring(start).split('')) {
    if (inString) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    switch (ch) {
      case '"':
        inString = true;
      case '{':
        open.add('}');
      case '[':
        open.add(']');
      case '}' || ']':
        if (open.isEmpty) return out.toString(); // 多出来的右括号之后不要了
        open.removeLast();
        // 去掉紧挨着的那个多余逗号。
        final kept = out.toString().trimRight();
        if (kept.endsWith(',')) {
          out
            ..clear()
            ..write(kept.substring(0, kept.length - 1));
        }
    }
    out.write(ch);
    if (open.isEmpty && ch == '}') break; // 整份读完了,后面的话不要
  }
  if (inString) out.write('"');
  out.writeAll(open.reversed);
  return out.toString();
}

/// 布局 JSON 里的一个功能区:`summary`(整体,[item] 为 -1)或 `items` 里的第 [item] 块。
/// [start]、[end] 是它那个 `{…}` 在原文里的位置;[label]、[name]、[text] 给标题用。
typedef LayoutRegion = ({
  int start,
  int end,
  int item,
  String label,
  String name,
  String text,
});

/// 把一份布局 JSON 按功能区切出位置,只用来分区显示,原文一个字不动。
/// 不是布局 JSON(读不了、没有 summary 和 items)返回 null。
List<LayoutRegion>? layoutJsonRegions(String source) {
  final Object? j;
  try {
    j = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (j is! Map || j['summary'] is! Map || j['items'] is! List) return null;
  final items = j['items'] as List;
  String field(int i, String key) {
    final item = i < items.length ? items[i] : null;
    final v = item is Map ? item[key] : null;
    return v is String ? v.trim() : '';
  }

  final out = <LayoutRegion>[];
  var depth = 0, keyStart = 0, next = 0;
  var inString = false, escaped = false;
  // 最外层最近读到的那个字符串(值前面的就是键),和正在里面的那个值的键。
  String? key, owner;
  int? open;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
        if (depth == 1) key = source.substring(keyStart + 1, i);
      }
      continue;
    }
    switch (c) {
      case '"':
        inString = true;
        keyStart = i;
      case '{' || '[':
        if (depth == 1) owner = key;
        if (c == '{' &&
            (depth == 1 && owner == 'summary' ||
                depth == 2 && owner == 'items')) {
          open = i;
        }
        depth++;
      case '}' || ']':
        depth--;
        if (c == '}' && open != null && (depth == 1 || depth == 2)) {
          final n = depth == 1 ? -1 : next++;
          out.add((
            start: open,
            end: i + 1,
            item: n,
            label: n < 0 ? '' : field(n, 'label'),
            name: n < 0 ? '' : field(n, 'name'),
            text: n < 0 ? '' : field(n, 'text'),
          ));
          open = null;
        }
    }
  }
  return out;
}
