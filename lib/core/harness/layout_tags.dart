part of 'layout.dart';

// 回复里和布局有关的几种标签:<ask-layout>、<layout>、<layers>。

/// 开始标签上可以带别的属性,name 用单引号也认(有的模型这么写,以前整个标签就不认了)。
final _ask = RegExp(r'<ask-layout(\s[^>]*)?>([\s\S]*?)</ask-layout>');
final _askName = RegExp(r'''name\s*=\s*["']([^"'\n]*)["']''');
const _askOpen = '<ask-layout';

/// 主工作区把排布局的活交给区域控制工作台的 Agent:`<ask-layout name="系列名">任务</ask-layout>`。
/// [asks] 是写完的那几个(任务是空的不算),[prose] 是去掉它们之后给人看的话,
/// 还没写完的那一个先不显示。
({String prose, List<({String name, String brief})> asks}) splitAskLayout(
  String reply,
) {
  final asks = [
    for (final m in _ask.allMatches(reply))
      if (m[2]!.trim().isNotEmpty)
        (
          name: (_askName.firstMatch(m[1] ?? '')?[1] ?? '').trim(),
          brief: m[2]!.trim(),
        ),
  ];
  var prose = reply.replaceAll(_ask, '');
  final half = prose.indexOf(_askOpen);
  if (half >= 0) {
    prose = prose.substring(0, half);
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _askOpen.length - 1; n > 1; n--) {
      if (prose.endsWith(_askOpen.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (prose: prose.trim(), asks: asks);
}

final _block = RegExp(r'<layout(\s[^>]*)?>([\s\S]*?)</layout>');
const _open = '<layout>';

/// 开始标签(可以带属性),后面跟着空白、`>` 或者还没写出来。
final _openTag = RegExp(r'<layout(?=[\s>]|$)');
final _layoutAttr = RegExp(r'([a-z]+)\s*=\s*"([^"\n]*)"');

/// 发给模型的旧回复里,整个 `<layout>…</layout>` 换成一句话:用户之后可能拖过框、改过字,
/// 旧坐标留在上文里,模型会照抄回去。画板现在的样子只看系统提示里的【布局画板】。
/// 这句话不带标签:带着 `<layout>` 的话,模型会照样子把这句话当成布局写回来。
/// [placed] 为假是这条回复里的布局没放上画板(写在查角色库、查标签的那条回复里,
/// 程序不收):照实说,不然模型以为已经放好,下一条就只说话不写布局。
String forgetLayouts(String reply, {bool placed = true}) => reply.replaceAll(
  _block,
  placed
      ? '〔程序注:这里原有一份布局,已放到画板上,内容省略;现在的样子看【布局画板】。这是程序写的记号,不要照抄〕'
      : '〔程序注:这里原有一份布局,写在查资料的回复里,没有放到画板上;要放就重新写完整的布局〕',
);

final _layersTag = RegExp(r'<layers>([\s\S]*?)</layers>');
const _layersOpen = '<layers>';

/// Agent 调图层的一项:把现在第 [from] 块(从 1 数)排到这个位置,
/// [name]、[layer] 不为 null 时顺便改掉。
typedef LayerOp = ({int from, String? name, String? layer});

/// 拆回复里的 `<layers>`(有好几个时取最后一个):[spec] 是里面的内容,
/// [prose] 是去掉它之后给人看的话;还没写完的那一个先不显示,[spec] 为 null。
({String prose, String? spec}) splitLayers(String reply) {
  final done = _layersTag.allMatches(reply).lastOrNull;
  var prose = reply.replaceAll(_layersTag, '');
  var spec = done?[1]!.trim();
  final half = prose.indexOf(_layersOpen);
  if (half >= 0) {
    prose = prose.substring(0, half);
    spec = null;
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _layersOpen.length - 1; n > 1; n--) {
      if (prose.endsWith(_layersOpen.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (prose: prose.trim(), spec: spec);
}

/// 读 `<layers>` 里的 JSON 数组:按从前到后的新顺序一项一块,
/// `[{"from": 2, "name": "维尔汀", "layer": "front"}, {"from": 1}]`。
/// `from` 是这一块现在的序号(从 1 数);`name`、`layer` 要改才写。
/// 读不了、layer 不认得时返回 null。
List<LayerOp>? parseLayers(String spec) {
  final Object? list;
  try {
    // 模型常把 JSON 套进代码块。
    list = jsonDecode(
      spec
          .trim()
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), ''),
    );
  } on FormatException {
    return null;
  }
  if (list is! List || list.isEmpty) return null;
  final ops = <LayerOp>[];
  for (final item in list) {
    if (item is! Map || item['from'] is! num) return null;
    final layer = item['layer'];
    if (layer != null && !layoutLayers.contains(layer)) return null;
    final name = item['name'];
    ops.add((
      from: (item['from'] as num).round(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      layer: layer as String?,
    ));
  }
  return ops;
}

/// 发给模型的旧回复里,整个 `<layers>…</layers>` 换成一句不带标签的话(同 [forgetLayouts])。
String forgetLayers(String reply) =>
    reply.replaceAll(_layersTag, '(这里调过一次图层,已放到画板上,内容省略;现在的样子看【布局画板】)');

/// 把回复里的 `<layout>` 拆出来(有好几个时取最后一个):[json] 是里面的布局,
/// [prose] 是去掉它之后给人看的话;还没写完的那一个先不显示,[complete] 为假。
/// 开始标签上可以带 `page`(写进这个系列的第几页,或 `新系列`)、`name`(页名)、
/// `series`(系列名),同成稿的 `<draft>`。
({
  String prose,
  String? json,
  bool complete,
  String? page,
  String? name,
  String? series,
})
splitLayout(String reply) {
  final done = _block.allMatches(reply).lastOrNull;
  final attrs = {
    for (final a in _layoutAttr.allMatches(done?[1] ?? '')) a[1]!: a[2]!.trim(),
  };
  var prose = reply.replaceAll(_block, '');
  String? json = done?[2]!.trim();
  var complete = done != null;
  final half = _openTag.firstMatch(prose)?.start ?? -1;
  if (half >= 0) {
    // 开始标签的属性可能还没写完:`>` 之后才是布局。
    final body = prose.indexOf('>', half);
    json = body < 0 ? '' : prose.substring(body + 1).trim();
    complete = false;
    prose = prose.substring(0, half);
  } else {
    // 开始标签只到了一半(流式生成中)。
    for (var n = _open.length - 1; n > 1; n--) {
      if (prose.endsWith(_open.substring(0, n))) {
        prose = prose.substring(0, prose.length - n);
        break;
      }
    }
  }
  return (
    prose: prose.trim(),
    json: json,
    complete: complete,
    page: complete ? attrs['page'] : null,
    name: complete ? attrs['name'] : null,
    series: complete ? attrs['series'] : null,
  );
}
