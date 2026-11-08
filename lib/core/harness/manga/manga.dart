// 漫画分镜工作台的文档(纯数据,不依赖 Flutter)。
//
// 长度一律是微米整数(1 mm = 1000),页面坐标原点在成品框左上,x 向右、y 向下。
// 一页的分格是一棵矩形切分树([MangaNode]):叶子是一格,切分节点把父区域按
// [MangaSplit.ratio](百万分比)切成左右(x)或上下(y)两块,中间扣一次沟宽。
// 各格的矩形由树算出来(manga_geometry.dart),不另存一份。

/// 文件结构版本;读到更高的版本只读、不覆写。
const mangaSchema = 1;

/// 一格最短边(15 mm)。
const mangaMinSide = 15000;

/// 纸张预设(mm)。
const mangaPapers = <String, (int, int)>{
  'A5': (148, 210),
  'B5': (182, 257),
  'A4': (210, 297),
};

int mmToUm(num mm) => (mm * 1000).round();

/// 矩形(微米)。
typedef MangaRect = ({int x, int y, int w, int h});

/// x 是左右分,y 是上下分;first 永远是左或上,和阅读方向无关。
enum MangaAxis { x, y }

sealed class MangaNode {
  const MangaNode();

  Map<String, Object?> toJson();

  /// 读不了(缺字段、比例越界、太深)返回 null。
  static MangaNode? fromJson(Object? j, [int depth = 0]) {
    if (j is! Map || depth > 40) return null;
    if (j['panel'] case final String id when id.isNotEmpty) {
      return MangaLeaf(id);
    }
    final axis = switch (j['axis']) {
      'x' => MangaAxis.x,
      'y' => MangaAxis.y,
      _ => null,
    };
    final ratio = j['ratio'];
    final first = fromJson(j['first'], depth + 1);
    final second = fromJson(j['second'], depth + 1);
    if (axis == null ||
        ratio is! int ||
        ratio < 1 ||
        ratio > 999999 ||
        first == null ||
        second == null) {
      return null;
    }
    return MangaSplit(axis: axis, ratio: ratio, first: first, second: second);
  }
}

final class MangaLeaf extends MangaNode {
  const MangaLeaf(this.panel);

  final String panel;

  @override
  Map<String, Object?> toJson() => {'panel': panel};
}

final class MangaSplit extends MangaNode {
  const MangaSplit({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });

  final MangaAxis axis;

  /// 第一块占可用长度的百万分之几(1..999999)。
  final int ratio;
  final MangaNode first, second;

  MangaSplit copyWith({int? ratio, MangaNode? first, MangaNode? second}) =>
      MangaSplit(
        axis: axis,
        ratio: ratio ?? this.ratio,
        first: first ?? this.first,
        second: second ?? this.second,
      );

  @override
  Map<String, Object?> toJson() => {
    'axis': axis.name,
    'ratio': ratio,
    'first': first.toJson(),
    'second': second.toJson(),
  };
}

/// 一句台词;旁白的 [speaker] 写「旁白」。
typedef MangaLine = ({String speaker, String text});

/// 一格的内容:景别、角度、出场角色、动作、台词、分量(0–100,越大越该是大格)。
/// [locked] 是内容锁:抽镜头、Agent 写分镜都不改它。
class MangaPanel {
  const MangaPanel({
    required this.id,
    this.framing = '',
    this.angle = '',
    this.cast = const [],
    this.action = '',
    this.lines = const [],
    this.emphasis = 50,
    this.locked = false,
  });

  final String id;
  final String framing, angle, action;
  final List<String> cast;
  final List<MangaLine> lines;
  final int emphasis;
  final bool locked;

  bool get isBlank =>
      framing.isEmpty &&
      angle.isEmpty &&
      cast.isEmpty &&
      action.isEmpty &&
      lines.isEmpty;

  MangaPanel copyWith({
    String? framing,
    String? angle,
    List<String>? cast,
    String? action,
    List<MangaLine>? lines,
    int? emphasis,
    bool? locked,
  }) => MangaPanel(
    id: id,
    framing: framing ?? this.framing,
    angle: angle ?? this.angle,
    cast: List.unmodifiable(cast ?? this.cast),
    action: action ?? this.action,
    lines: List.unmodifiable(lines ?? this.lines),
    emphasis: (emphasis ?? this.emphasis).clamp(0, 100),
    locked: locked ?? this.locked,
  );

  /// 清空成留白(锁照旧)。
  MangaPanel cleared() => MangaPanel(id: id, locked: locked);

  Map<String, Object?> toJson() => {
    'id': id,
    if (framing.isNotEmpty) 'framing': framing,
    if (angle.isNotEmpty) 'angle': angle,
    if (cast.isNotEmpty) 'cast': cast,
    if (action.isNotEmpty) 'action': action,
    if (lines.isNotEmpty)
      'lines': [
        for (final l in lines) {'speaker': l.speaker, 'text': l.text},
      ],
    'emphasis': emphasis,
    if (locked) 'locked': true,
  };

  static MangaPanel? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return MangaPanel(id: j['id'] as String).copyWith(
      framing: s('framing'),
      angle: s('angle'),
      cast: [
        for (final c in j['cast'] as List? ?? const [])
          if (c is String) c,
      ],
      action: s('action'),
      lines: [
        for (final l in j['lines'] as List? ?? const [])
          if (l is Map && l['text'] is String)
            (
              speaker: l['speaker'] is String ? l['speaker'] as String : '',
              text: l['text'] as String,
            ),
      ],
      emphasis: j['emphasis'] is int ? j['emphasis'] as int : 50,
      locked: j['locked'] == true,
    );
  }
}

/// 一页:成品尺寸、四边留白、沟宽、阅读方向、分格树和各格内容。
class MangaPage {
  const MangaPage({
    required this.id,
    required this.root,
    required this.panels,
    this.width = 148000,
    this.height = 210000,
    this.margin = 10000,
    this.gap = 4000,
    this.rtl = true,
    this.note = '',
  });

  final String id;
  final int width, height, margin, gap;

  /// 日式从右往左读;false 是从左往右。
  final bool rtl;
  final MangaNode root;
  final Map<String, MangaPanel> panels;

  /// 这一页讲什么(给 Agent 看的一句)。
  final String note;

  /// 分格的根区域:成品框四边各扣 [margin]。
  MangaRect get content =>
      (x: margin, y: margin, w: width - 2 * margin, h: height - 2 * margin);

  MangaPage copyWith({
    int? width,
    int? height,
    int? gap,
    bool? rtl,
    MangaNode? root,
    Map<String, MangaPanel>? panels,
    String? note,
  }) => MangaPage(
    id: id,
    width: width ?? this.width,
    height: height ?? this.height,
    margin: margin,
    gap: gap ?? this.gap,
    rtl: rtl ?? this.rtl,
    root: root ?? this.root,
    panels: Map.unmodifiable(panels ?? this.panels),
    note: note ?? this.note,
  );

  /// 换掉一格的内容。
  MangaPage withPanel(MangaPanel p) => copyWith(panels: {...panels, p.id: p});

  Map<String, Object?> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'margin': margin,
    'gap': gap,
    'rtl': rtl,
    if (note.isNotEmpty) 'note': note,
    'root': root.toJson(),
    'panels': [for (final p in panels.values) p.toJson()],
  };

  /// 读不了、树和格对不上(每格恰好一片叶子)时返回 null。
  static MangaPage? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final root = MangaNode.fromJson(j['root']);
    if (root == null) return null;
    final read = [
      for (final p in j['panels'] as List? ?? const []) ?MangaPanel.fromJson(p),
    ];
    final panels = {for (final p in read) p.id: p};
    final leaves = leafIds(root);
    if (leaves.length != leaves.toSet().length ||
        leaves.length != panels.length ||
        !leaves.every(panels.containsKey)) {
      return null;
    }
    int side(String k, int lo, int hi, int fallback) =>
        j[k] is int ? (j[k] as int).clamp(lo, hi) : fallback;
    final page = MangaPage(
      id: j['id'] as String,
      root: root,
      panels: Map.unmodifiable(panels),
      width: side('width', 50000, 600000, 148000),
      height: side('height', 50000, 600000, 210000),
      margin: side('margin', 0, 40000, 10000),
      gap: side('gap', 0, 20000, 4000),
      rtl: j['rtl'] != false,
      note: j['note'] is String ? j['note'] as String : '',
    );
    return page;
  }
}

/// 树里的格 id,按树的先后(先 first 后 second)。
List<String> leafIds(MangaNode n) => switch (n) {
  MangaLeaf(:final panel) => [panel],
  MangaSplit(:final first, :final second) => [
    ...leafIds(first),
    ...leafIds(second),
  ],
};

/// 设定里的一个角色:名字和外貌(发型发色、瞳色、服装、标志物)。
class MangaCharacter {
  const MangaCharacter({required this.name, this.look = ''});

  final String name, look;

  Map<String, Object?> toJson() => {'name': name, 'look': look};
}

/// 一部作品:名字、世界观与画风、角色、各页。[nextId] 单调递增,删掉的 id 不再用。
class MangaProject {
  const MangaProject({
    required this.pages,
    this.title = '',
    this.setting = '',
    this.characters = const [],
    this.nextId = 1,
  });

  /// 一张空白页、一格。
  factory MangaProject.blank() =>
      MangaProject(pages: [blankMangaPage('page-1', 'panel-1')], nextId: 2);

  final String title, setting;
  final List<MangaCharacter> characters;
  final List<MangaPage> pages;
  final int nextId;

  MangaProject copyWith({
    String? title,
    String? setting,
    List<MangaCharacter>? characters,
    List<MangaPage>? pages,
    int? nextId,
  }) => MangaProject(
    title: title ?? this.title,
    setting: setting ?? this.setting,
    characters: List.unmodifiable(characters ?? this.characters),
    pages: List.unmodifiable(pages ?? this.pages),
    nextId: nextId ?? this.nextId,
  );

  /// 换掉第 [i] 页。
  MangaProject withPage(int i, MangaPage page) =>
      copyWith(pages: [...pages.take(i), page, ...pages.skip(i + 1)]);

  /// 发 [count] 个新 id(`<kind>-<n>`),返回它们和用掉编号后的作品。
  (List<String>, MangaProject) newIds(String kind, int count) => (
    [for (var i = 0; i < count; i++) '$kind-${nextId + i}'],
    copyWith(nextId: nextId + count),
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': mangaSchema,
    'title': title,
    'setting': setting,
    'characters': [for (final c in characters) c.toJson()],
    'nextId': nextId,
    'pages': [for (final p in pages) p.toJson()],
  };

  /// 读不了(结构不对、哪一页坏了、版本比现在新)返回 null;不悄悄丢掉坏的页。
  static MangaProject? fromJson(Object? j) {
    if (j is! Map || j['schemaVersion'] != mangaSchema) return null;
    final pages = <MangaPage>[];
    for (final p in j['pages'] as List? ?? const []) {
      final page = MangaPage.fromJson(p);
      if (page == null) return null;
      pages.add(page);
    }
    if (pages.isEmpty) return null;
    return MangaProject(
      pages: List.unmodifiable(pages),
      title: j['title'] is String ? j['title'] as String : '',
      setting: j['setting'] is String ? j['setting'] as String : '',
      characters: List.unmodifiable([
        for (final c in j['characters'] as List? ?? const [])
          if (c is Map && c['name'] is String)
            MangaCharacter(
              name: c['name'] as String,
              look: c['look'] is String ? c['look'] as String : '',
            ),
      ]),
      nextId: j['nextId'] is int ? j['nextId'] as int : 1,
    );
  }
}

/// 一张只有一格的空白页(默认 A5、日式阅读)。
MangaPage blankMangaPage(String id, String panelId, {MangaPage? like}) =>
    MangaPage(
      id: id,
      root: MangaLeaf(panelId),
      panels: {panelId: MangaPanel(id: panelId)},
      width: like?.width ?? 148000,
      height: like?.height ?? 210000,
      gap: like?.gap ?? 4000,
      rtl: like?.rtl ?? true,
    );
