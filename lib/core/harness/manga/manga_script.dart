// 分镜和外面来回:Agent 写的 `<storyboard>` 读进作品,作品写成给 Agent 看的文字,
// 一页分镜交给区域控制工作台(带格子的布局)或主工作台(逐格写提示词)。

import 'dart:convert';

import '../../../l10n/l10n.dart';
import '../layout.dart';
import 'manga.dart';
import 'manga_gacha.dart';
import 'manga_geometry.dart';
import 'manga_poses.dart';
import 'manga_styles.dart';

/// Agent 写分镜用的标签。
const storyboardTag = 'storyboard';

/// Agent 写的一格。[emphasis] 没写是 null(照旧)。
typedef StoryPanel = ({
  String framing,
  String angle,
  List<String> cast,
  String action,
  List<MangaLine> lines,
  int? emphasis,
  Map<String, String> poses,
});

/// Agent 写的一页:[page] 是第几页(从 1 数),没写是 null。
typedef StoryPage = ({int? page, String? note, List<StoryPanel> panels});

/// Agent 写的一份分镜:要改的几页,和顺手补的设定(没写是 null)。
typedef Storyboard = ({
  List<StoryPage> pages,
  String? title,
  String? setting,
  List<MangaCharacter> characters,
});

/// 外来数据的上限:页数、每页格数、每格台词、字数。
const _maxPages = 20, _maxLines = 8, _maxText = 600;

String _text(Object? v) {
  if (v is! String) return '';
  final t = v.trim();
  return t.length > _maxText ? t.substring(0, _maxText) : t;
}

/// 读 `<storyboard>` 里的 JSON。只收白名单里的字段;结构不对、太大返回 null,
/// 不拼残片。
Storyboard? parseStoryboard(String raw) {
  final Object? j;
  try {
    j = jsonDecode(
      raw
          .trim()
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), ''),
    );
  } on FormatException {
    return null;
  }
  final root = j is List ? {'pages': j} : j;
  if (root is! Map || root['pages'] is! List) return null;
  final pages = <StoryPage>[];
  for (final p in (root['pages'] as List).take(_maxPages)) {
    if (p is! Map || p['panels'] is! List) return null;
    final panels = <StoryPanel>[
      for (final c in (p['panels'] as List).take(mangaMaxPanels))
        if (c is Map)
          (
            framing: _text(c['framing']),
            angle: _text(c['angle']),
            cast: [
              for (final n in c['cast'] as List? ?? const [])
                if (_text(n).isNotEmpty) _text(n),
            ],
            action: _text(c['action']),
            lines: [
              for (final l in (c['lines'] as List? ?? const []).take(_maxLines))
                if (l is Map && _text(l['text']).isNotEmpty)
                  (speaker: _text(l['speaker']), text: _text(l['text'])),
            ],
            emphasis: c['emphasis'] is num
                ? (c['emphasis'] as num).round().clamp(0, 100)
                : null,
            // 只收认得的姿势名。
            poses: {
              if (c['poses'] case final Map m)
                for (final MapEntry(:key, :value) in m.entries)
                  if (key is String &&
                      value is String &&
                      poseNamed(value) != null)
                    key: value,
            },
          ),
    ];
    if (panels.isEmpty) return null;
    pages.add((
      page: p['page'] is int ? p['page'] as int : null,
      note: p['note'] is String ? _text(p['note']) : null,
      panels: panels,
    ));
  }
  return (
    pages: pages,
    title: root['title'] is String ? _text(root['title']) : null,
    setting: root['setting'] is String ? _text(root['setting']) : null,
    characters: [
      for (final c in root['characters'] as List? ?? const [])
        if (c is Map && _text(c['name']).isNotEmpty)
          MangaCharacter(name: _text(c['name']), look: _text(c['look'])),
    ],
  );
}

/// 把分镜放进作品:每页按阅读顺序一格一格换内容,锁着的格不动。
/// 格数和那页现在的不一样时按分量重新抽一张分格(种子用 [seed]);
/// 那页有锁着的格就不重排,记一条问题。写到还没有的页就加页。
/// 没写页码的从 [current] 起往后排。返回新作品、做了什么、没做成的。
({MangaProject project, List<String> done, List<String> problems})
applyStoryboard(
  MangaProject project,
  Storyboard board, {
  required int current,
  required String seed,
}) {
  var p = project;
  final done = <String>[];
  final problems = <String>[];
  // 设定:作品名、世界观只在写了时换;角色按名字补上或换外貌,不删。
  if (board.title case final t? when t.isNotEmpty) p = p.copyWith(title: t);
  if (board.setting case final s? when s.isNotEmpty) {
    p = p.copyWith(setting: s);
  }
  if (board.characters.isNotEmpty) {
    final byName = {for (final c in p.characters) c.name: c};
    for (final c in board.characters) {
      byName[c.name] = c.look.isEmpty && byName[c.name] != null
          ? byName[c.name]!
          : c;
    }
    p = p.copyWith(characters: byName.values.toList());
    done.add(tr('设定里有 {0} 个角色', [byName.length]));
  }
  var next = current;
  for (final story in board.pages) {
    final at = (story.page ?? next + 1) - 1;
    next = at + 1;
    if (at < 0 || at > p.pages.length || at >= 50) {
      problems.add(tr('没有第 {0} 页', [at + 1]));
      continue;
    }
    if (at == p.pages.length) {
      final (ids, q) = p.newIds('page', 2);
      p = q.copyWith(
        pages: [
          ...q.pages,
          blankMangaPage(ids[0], ids[1], like: q.pages.last),
        ],
      );
    }
    final placed = _placePage(p, at, story, seed);
    p = placed.project;
    if (placed.problem != null) {
      problems.add(tr('第 {0} 页:{1}', [at + 1, placed.problem!]));
    } else {
      done.add(tr('第 {0} 页 · {1} 格', [at + 1, story.panels.length]));
    }
  }
  return (project: p, done: done, problems: problems);
}

({MangaProject project, String? problem}) _placePage(
  MangaProject project,
  int at,
  StoryPage story,
  String seed,
) {
  var p = project;
  var page = p.pages[at];
  final want = story.panels.length;
  if (readingOrder(page).length != want) {
    if (page.panels.values.any((x) => x.locked)) {
      return (project: p, problem: tr('有锁着的格,格数对不上,没有重排'));
    }
    final emphasis = [for (final s in story.panels) s.emphasis ?? 50];
    final draw = drawLayouts(
      page,
      seed: '$seed/${page.id}',
      style: mangaStyles['标准'],
      minPanels: want,
      maxPanels: want,
      count: 1,
      emphasis: emphasis,
    );
    if (draw.found.isEmpty) return (project: p, problem: draw.problem);
    final (ids, q) = p.newIds('panel', want);
    // 内容马上整页换掉,原来的格不用留:先清成留白再接到新格上。
    final blanked = page.copyWith(
      panels: {for (final x in page.panels.values) x.id: x.cleared()},
    );
    final applied = applyLayout(blanked, draw.found.first.root, ids)!;
    p = q;
    page = applied.page;
  }
  final order = readingOrder(page);
  var panels = page.panels;
  for (final (i, id) in order.indexed) {
    final old = panels[id]!;
    if (old.locked) continue;
    final s = story.panels[i];
    panels = {
      ...panels,
      id: old.copyWith(
        framing: s.framing,
        angle: s.angle,
        cast: s.cast,
        action: s.action,
        lines: s.lines,
        emphasis: s.emphasis,
        figures: {
          ...old.figures,
          for (final MapEntry(:key, :value) in s.poses.entries)
            key: old.figureOf(key).copyWith(pose: value),
        },
      ),
    };
  }
  page = page.copyWith(panels: panels, note: story.note);
  return (project: p.withPage(at, page), problem: null);
}

/// 整部作品的分镜文字(档案库复制用):设定、角色、每页每格。
String mangaOutline(MangaProject p) => [
  if (p.title.isNotEmpty) p.title,
  if (p.setting.isNotEmpty) p.setting,
  if (p.characters.isNotEmpty)
    p.characters.map((c) => '${c.name}:${c.look}').join('\n'),
  for (final (i, page) in p.pages.indexed)
    [
      '第 ${i + 1} 页${page.note.isEmpty ? '' : ':${page.note}'}',
      for (final (n, id) in readingOrder(page).indexed)
        '${n + 1}. ${panelLine(page.panels[id]!)}',
    ].join('\n'),
].join('\n\n');

/// 一格写成一行字:景别·角度|出场|动作|台词。
String panelLine(MangaPanel p) => [
  [p.framing, p.angle].where((s) => s.isNotEmpty).join('·'),
  if (p.cast.isNotEmpty) '出场:${p.cast.join('、')}',
  if (p.action.isNotEmpty) '动作:${p.action}',
  if (p.figures.entries.where((e) => e.value.pose.isNotEmpty) case final set
      when set.isNotEmpty)
    '姿势:${set.map((e) => '${e.key}=${e.value.pose}').join('、')}',
  for (final l in p.lines)
    l.speaker.isEmpty ? '「${l.text}」' : '${l.speaker}「${l.text}」',
].where((s) => s.isNotEmpty).join(';');

/// 给 Agent 看的整部作品:设定、角色、每页每格(按阅读顺序,锁着的标出来)。
String mangaAgentView(MangaProject p, int current) {
  final out = StringBuffer()
    ..writeln('【作品】${p.title.isEmpty ? '(还没起名)' : p.title}')
    ..writeln('【设定】${p.setting.isEmpty ? '(空)' : p.setting}')
    ..writeln(
      '【角色】${p.characters.isEmpty ? '(空)' : p.characters.map((c) => '${c.name}:${c.look}').join(';')}',
    )
    ..writeln('【分镜】共 ${p.pages.length} 页,用户眼前是第 ${current + 1} 页');
  for (final (i, page) in p.pages.indexed) {
    final order = readingOrder(page);
    out.writeln(
      '第 ${i + 1} 页(${order.length} 格,${page.rtl ? '日式从右往左' : '从左往右'})'
      '${page.note.isEmpty ? '' : ':${page.note}'}',
    );
    for (final (n, id) in order.indexed) {
      final panel = page.panels[id]!;
      out.writeln(
        '  第 ${n + 1} 格${panel.locked ? '(locked)' : ''}:'
        '${panel.isBlank ? '(留白)' : panelLine(panel)}',
      );
    }
  }
  return out.toString().trimRight();
}

/// 这一页的分镜:设定、角色(带身高)、这一页讲什么、按阅读顺序每一格。
List<String> _pageFacts(MangaProject p, int at) {
  final page = p.pages[at];
  return [
    if (p.setting.isNotEmpty) '【设定】${p.setting}',
    if (p.characters.isNotEmpty)
      '【角色】\n${p.characters.map((c) => '${c.name}(${c.height} cm):${c.look}').join('\n')}',
    if (page.note.isNotEmpty) '【这一页】${page.note}',
    [
      for (final (n, id) in readingOrder(page).indexed)
        '第 ${n + 1} 格:${panelLine(page.panels[id]!)}',
    ].join('\n'),
  ];
}

/// 一页的名字:作品名加第几页。
String mangaPageName(MangaProject p, int at) => [
  if (p.title.isNotEmpty) p.title,
  tr('第 {0} 页', [at + 1]),
].join(' ');

/// 交给主工作台的话:按这页分镜逐格写提示词,一格一页放进一个新系列。
/// [image] 时附了这页的人偶参考图。
String mangaBrief(MangaProject p, int at, {bool image = false}) => [
  tr(
    '按这页漫画分镜写提示词:每一格写成一页,放进新系列「{0}」。'
    '每格都带上出场角色的外貌,用词前后一致;景别和角度照分镜。',
    [mangaPageName(p, at)],
  ),
  if (image) tr('附图是这页的人偶参考,人物的站位、朝向和取景照它写。'),
  ..._pageFacts(p, at),
].join('\n\n');

/// 交给区域控制之后请那边的 Agent 润色的话:格框照旧,人物和气泡摆合理,
/// 描述写成英文,补角色卡和整体描述。[image] 时附了人偶参考图。
String mangaLayoutRequest(MangaProject p, int at, {bool image = false}) => [
  tr(
    '这页漫画分镜从漫画分镜工作台交过来,画板上已经按分镜摆好:每格一个框(back,名字「第N格」),'
    '格里的人物(middle,「名字·格号」)和台词(text,front)各一块。照「漫画分格」技能把这页排好、写完整:'
    '格框的位置和形状不动,不增删格;人物、气泡照分镜摆合理(人物不跨格,气泡贴着说话的人、不挡脸);'
    '每块的描述改写成英文,格框写景别、场景、背景和光线,人物写表情、动作和视线;'
    '角色卡(cast)照设定写成英文,整体描述写清画风和这一页讲什么。写完给出完整的 <layout>。',
  ),
  if (image) tr('附图是这页的人偶参考:人物的站位、朝向、景别和气泡位置照它。'),
  ..._pageFacts(p, at),
].join('\n\n');

const _framingEn = {
  '远景': 'extreme wide shot',
  '全景': 'full shot',
  '中景': 'medium shot',
  '近景': 'close-up',
  '特写': 'extreme close-up',
};
const _angleEn = {
  '平视': 'eye level',
  '俯视': 'high angle',
  '仰视': 'low angle',
  '侧面': 'side view',
  '背影': 'from behind',
  '过肩': 'over-the-shoulder',
};

/// 区域控制的布局最多几个元素(同「漫画分格」技能)。
const _maxBoxes = 16;

/// 一页分镜换成区域控制的布局:画布按纸张比例(长边 [longSide]、取 [step] 的倍数),
/// 每格一块(back),格里的人一人一块(middle,name 写「名字·格号」;特写格不放),
/// 台词一句一块(text,front,放在格的上沿)。元素超过 16 个时先保格,再台词,再人物。
Layout mangaToLayout(
  MangaProject p,
  int at, {
  int longSide = 1216,
  int step = 16,
}) {
  final page = p.pages[at];
  final tall = page.height >= page.width;
  final w = snapLayoutSide(
    tall ? longSide * page.width ~/ page.height : longSide,
    step,
  );
  final h = snapLayoutSide(
    tall ? longSide : longSide * page.height ~/ page.width,
    step,
  );
  int px(int um) => (um * w ~/ page.width).clamp(0, w);
  int py(int um) => (um * h ~/ page.height).clamp(0, h);
  final quads = panelQuads(page);
  final outer = panelQuads(page, bleed: true);
  final order = readingOrder(page);
  final frames = <LayoutBox>[];
  final talk = <LayoutBox>[];
  final people = <LayoutBox>[];
  for (final (i, id) in order.indexed) {
    final n = i + 1;
    final panel = page.panels[id]!;
    // 格框:出血格铺到画布边;斜的格写成多边形。
    final frame = [for (final q in outer[id]!) (x: px(q.x), y: py(q.y))];
    final fb = boundsOf(frame);
    final slanted =
        frame[0].x != frame[3].x ||
        frame[1].x != frame[2].x ||
        frame[0].y != frame[1].y ||
        frame[3].y != frame[2].y;
    // 人物和台词放在格里面那块正的矩形里,不压到斜边。
    final q = quads[id]!;
    final l = px(q[0].x > q[3].x ? q[0].x : q[3].x);
    final rr = px(q[1].x < q[2].x ? q[1].x : q[2].x);
    final t = py(q[0].y > q[1].y ? q[0].y : q[1].y);
    final b = py(q[3].y < q[2].y ? q[3].y : q[2].y);
    final shot = [
      _framingEn[panel.framing] ?? panel.framing,
      _angleEn[panel.angle] ?? panel.angle,
    ].where((s) => s.isNotEmpty).join(', ');
    frames.add(
      LayoutBox(
        left: fb.x,
        top: fb.y,
        right: fb.x + fb.w,
        bottom: fb.y + fb.h,
        shape: slanted && fb.w > 0 && fb.h > 0
            ? LayoutShape.polygon([
                for (final v in frame)
                  ((v.x - fb.x) / fb.w, (v.y - fb.y) / fb.h),
              ])
            : null,
        name: '第$n格',
        layer: 'back',
        caption: [
          'Panel $n of ${order.length}${shot.isEmpty ? '' : ', $shot'}:',
          if (panel.action.isNotEmpty) panel.action,
        ].join(' '),
      ),
    );
    final pw = rr - l, ph = b - t;
    // 台词:格的上沿一排,日式从右往左排。
    final lines = panel.lines;
    for (final (k, line) in lines.indexed) {
      final slot = page.rtl ? lines.length - 1 - k : k;
      final cw = pw * 84 ~/ 100 ~/ lines.length;
      final x0 = l + pw * 8 ~/ 100 + slot * cw;
      final narration = line.speaker.isEmpty || line.speaker == '旁白';
      talk.add(
        LayoutBox(
          left: x0,
          top: t + ph * 4 ~/ 100,
          right: x0 + cw * 9 ~/ 10,
          bottom: t + ph * 24 ~/ 100,
          label: 'text',
          layer: 'front',
          text: line.text,
          name: '台词·$n',
          caption: narration
              ? 'a sharp-cornered rectangular caption box with no tail'
              : 'a rounded oval speech bubble with its tail pointing to ${line.speaker}',
        ),
      );
    }
    // 人物:格的下面七成,一人一块,中间留空。特写格只画局部,不放人物块
    // (「漫画分格」技能:放了模型会在里面多画一个头)。
    final cast = panel.framing == '特写' ? const <String>[] : panel.cast;
    for (final (k, name) in cast.indexed) {
      final cw = pw * 88 ~/ 100 ~/ cast.length;
      // 用户拖过人偶就照拖到的地方(人偶的脚底或头顶在格宽的千分之几)。
      final dragged = panel.figureOf(name).x;
      final x0 = dragged == null
          ? l + pw * 6 ~/ 100 + k * cw
          : (l + pw * dragged ~/ 1000 - cw ~/ 2).clamp(l, rr - cw);
      people.add(
        LayoutBox(
          left: x0 + cw * 6 ~/ 100,
          top: t + ph * 28 ~/ 100,
          right: x0 + cw * 94 ~/ 100,
          bottom: b - ph * 4 ~/ 100,
          label: 'character',
          layer: 'middle',
          name: '$name·$n',
          caption: 'In panel $n, $name.',
        ),
      );
    }
  }
  final boxes = [...frames, ...talk, ...people].take(_maxBoxes).toList();
  final cast = {
    for (final c in p.characters)
      if (c.look.isNotEmpty) c.name: c.look,
  };
  return Layout(
    width: w,
    height: h,
    canvas: 'multi_panel',
    meta: 'comic',
    cast: cast,
    caption: [
      'A ${order.length}-panel manga page, read ${page.rtl ? 'right to left' : 'left to right'} '
          'and top to bottom, thin black panel borders with white gutters.',
      if (page.note.isNotEmpty) page.note,
    ].join(' '),
    boxes: boxes,
  );
}
