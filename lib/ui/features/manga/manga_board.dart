import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import '../../../core/harness/chat_peek.dart';
import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_gacha.dart';
import '../../../core/harness/manga/manga_geometry.dart';
import '../../../core/harness/manga/manga_script.dart';
import '../../../core/harness/manga/manga_styles.dart';
import '../../../l10n/l10n.dart';

/// 撤销最多记几步。
const _maxUndo = 100;

/// 最多几个系列(同工作台)。
const mangaMaxSeries = 20;

/// 打字时连着改同一样东西,这么久之内算同一步撤销。
const _typingGap = Duration(seconds: 1);

/// 撤销记的一份:全部系列和眼前是哪一个。
typedef _Snapshot = ({List<MangaProject> shelf, int series});

/// 漫画分镜工作台的状态:几个系列(每个系列是一部作品:设定、角色、几页)、
/// 眼前第几个系列第几页、选中哪一格、撤销重做、抽到的卡和抽卡的设置。
/// 存在「文档\Penna\manga.json」。
class MangaBoard extends ChangeNotifier {
  MangaBoard({this.dir});

  /// 存盘的文件夹;null 时不存(测试用)。
  final Directory? dir;

  List<MangaProject> _shelf = [MangaProject.blank()];
  int _series = 0;
  int _page = 0;
  String? _selected;
  List<_Snapshot> _undo = const [], _redo = const [];
  String? _typing;
  DateTime _typedAt = DateTime(0);

  /// 外面(撤销、Agent、抽卡)改了内容就加一:输入框靠它知道要换成新的字。
  int _revision = 0;

  /// 抽到的分格(没应用);[previewing] 是正在画布上看的那张。
  MangaDraw? _draw;
  int? _previewing;
  String _seed = _newSeed();
  int _shotRolls = 0;

  /// 抽分格的设置:版式(选了现成的就记着名字,调过参数后名字是空的)、
  /// 要不要指定格数、一次抽几张。
  String styleName = '标准';
  MangaStyle style = mangaStyles['标准']!;
  bool fixedCount = false;
  int minPanels = 4, maxPanels = 7;
  int drawCount = 8;

  /// 格里画人偶草图(关了写字)、画阅读动线。
  bool showFigures = true, showFlow = false;

  List<MangaProject> get shelf => List.unmodifiable(_shelf);
  int get seriesIndex => _series;
  MangaProject get project => _shelf[_series];
  int get pageIndex => _page;
  MangaPage get page => project.pages[_page];
  String? get selected => _selected;
  MangaPanel? get selectedPanel =>
      _selected == null ? null : page.panels[_selected];
  int get revision => _revision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  MangaDraw? get draw => _draw;
  int? get previewing => _previewing;
  String get seed => _seed;
  bool get seriesFull => _shelf.length >= mangaMaxSeries;

  /// 系列的名字:作品名,没起名是「系列 N」。
  String seriesName(int i) => _shelf[i].title.trim().isEmpty
      ? tr('系列 {0}', [i + 1])
      : _shelf[i].title.trim();

  /// 第 [i] 张候选套到眼前这页上的样子(内容按阅读顺序接上,不进作品)。
  MangaPage candidatePage(int i) {
    final c = _draw!.found[i];
    return applyLayout(page, c.root, [
          for (var k = 0; k < c.count; k++) '~$k',
        ])?.page ??
        page.copyWith(
          root: c.root,
          panels: {for (final id in leafIds(c.root)) id: MangaPanel(id: id)},
        );
  }

  /// 画布上画的那一页:看着候选时是候选套上去的样子。
  MangaPage get shown =>
      _previewing == null || _draw == null ? page : candidatePage(_previewing!);

  static String _newSeed() =>
      Random().nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0');

  _Snapshot get _now => (shelf: _shelf, series: _series);

  /// 改一步:旧的进撤销栈。[typing] 是打字时改的哪一样,连着打的字合成一步。
  void _commitShelf(List<MangaProject> next, {String? typing}) {
    final now = DateTime.now();
    final merge =
        typing != null &&
        typing == _typing &&
        now.difference(_typedAt) < _typingGap;
    if (!merge) {
      _undo = List.unmodifiable(
        [..._undo, _now].skip(_undo.length + 1 > _maxUndo ? 1 : 0),
      );
    }
    _typing = typing;
    _typedAt = now;
    _redo = const [];
    _shelf = List.unmodifiable(next);
    if (typing == null) _revision++;
    _afterChange();
  }

  void _commit(MangaProject next, {String? typing}) {
    if (identical(next, project)) return;
    _commitShelf([
      ..._shelf.take(_series),
      next,
      ..._shelf.skip(_series + 1),
    ], typing: typing);
  }

  void _afterChange() {
    _series = _series.clamp(0, _shelf.length - 1);
    _page = _page.clamp(0, project.pages.length - 1);
    if (_selected != null && !page.panels.containsKey(_selected)) {
      _selected = null;
    }
    _scheduleSave();
    notifyListeners();
  }

  void _restore(_Snapshot s) {
    _shelf = s.shelf;
    if (s.series != _series) {
      _series = s.series;
      _page = 0;
    }
    _typing = null;
    _revision++;
    _clearDraw();
    _afterChange();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo = List.unmodifiable([..._redo, _now]);
    final last = _undo.last;
    _undo = List.unmodifiable(_undo.take(_undo.length - 1));
    _restore(last);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo = List.unmodifiable([..._undo, _now]);
    final last = _redo.last;
    _redo = List.unmodifiable(_redo.take(_redo.length - 1));
    _restore(last);
  }

  void _setPage(MangaPage p, {String? typing}) =>
      _commit(project.withPage(_page, p), typing: typing);

  // ── 系列和页 ──

  void showSeries(int i) {
    if (i < 0 || i >= _shelf.length || i == _series) return;
    _series = i;
    _page = 0;
    _selected = null;
    _clearDraw();
    _revision++;
    _afterChange();
  }

  /// 加一个系列([project] 不给就是空白的)并换过去;满了返回原因。
  String? addSeries([MangaProject? from]) {
    if (seriesFull) return tr('最多 {0} 个系列,先删掉不用的', [mangaMaxSeries]);
    _commitShelf([..._shelf, from ?? MangaProject.blank()]);
    showSeries(_shelf.length - 1);
    return null;
  }

  /// 删掉第 [i] 个系列;只剩一个时换成空白的。
  void removeSeries(int i) {
    final rest = [..._shelf]..removeAt(i);
    if (_series >= i && _series > 0) _series--;
    _page = 0;
    _clearDraw();
    _commitShelf(rest.isEmpty ? [MangaProject.blank()] : rest);
  }

  void showPage(int i) {
    if (i < 0 || i >= project.pages.length || i == _page) return;
    _page = i;
    _selected = null;
    _clearDraw();
    notifyListeners();
  }

  /// 在眼前这页后面加一张空白页(纸张、方向照眼前这页)并换过去。
  void addPage() {
    final (ids, p) = project.newIds('page', 2);
    final pages = [...p.pages]
      ..insert(_page + 1, blankMangaPage(ids[0], ids[1], like: page));
    _commit(p.copyWith(pages: pages));
    showPage(_page + 1);
  }

  /// 删掉第 [i] 页;只剩一页时不删。
  void removePage(int i) {
    if (project.pages.length <= 1) return;
    final pages = [...project.pages]..removeAt(i);
    if (_page >= i && _page > 0) _page--;
    _clearDraw();
    _commit(project.copyWith(pages: pages));
  }

  void select(String? panel) {
    if (_selected == panel) return;
    _selected = panel;
    notifyListeners();
  }

  // ── 设定 ──

  void setTitle(String v) =>
      _commit(project.copyWith(title: v), typing: 'title');
  void setSetting(String v) =>
      _commit(project.copyWith(setting: v), typing: 'setting');

  void setCharacter(int i, MangaCharacter c, {bool typing = true}) {
    final list = [...project.characters];
    i < list.length ? list[i] = c : list.add(c);
    _commit(
      project.copyWith(characters: list),
      typing: typing ? 'character-$i' : null,
    );
  }

  void removeCharacter(int i) {
    final list = [...project.characters]..removeAt(i);
    _commit(project.copyWith(characters: list));
  }

  // ── 纸张 ──

  void setPaper(int width, int height) {
    _clearDraw();
    _setPage(page.copyWith(width: width, height: height));
  }

  void setNote(String v) => _setPage(page.copyWith(note: v), typing: 'note');

  void setRtl(bool rtl) => _setPage(page.copyWith(rtl: rtl));

  void setBorder(int um) => _setPage(page.copyWith(border: um));

  // ── 格 ──

  /// 改选中那格的内容;[typing] 见 [_commitShelf]。
  void updatePanel(MangaPanel p, {String? typing}) => _setPage(
    page.withPanel(p),
    typing: typing == null ? null : '${p.id}/$typing',
  );

  void setPanelBleed(String id, bool bleed) =>
      _setPage(setBleed(page, id, bleed));

  /// 拖格线时的样子:先只画,不进作品;松手时 [endDrag] 才算一步。
  MangaPage? _dragging;
  MangaPage get canvasPage => _dragging ?? shown;

  void dragTo(String path, int pos) {
    final moved = dragSplit(_dragging ?? page, path, pos);
    if (moved == null) return;
    _dragging = moved;
    notifyListeners();
  }

  void endDrag() {
    final moved = _dragging;
    _dragging = null;
    if (moved != null) _setPage(moved);
  }

  void cancelDrag() {
    _dragging = null;
    notifyListeners();
  }

  /// 把选中那格拆成两格;放不下返回原因。
  String? splitSelected(MangaAxis axis) {
    final id = _selected;
    if (id == null) return null;
    final (ids, p) = project.newIds('panel', 1);
    final next = splitPanel(page, id, axis, ids.first);
    if (next == null) return tr('这一格太小,拆不开');
    _commit(p.withPage(_page, next));
    return null;
  }

  /// 选中那格和兄弟格合并;不能合并返回原因。
  String? mergeSelected() {
    final id = _selected;
    if (id == null) return null;
    final other = mergeableWith(page, id);
    final next = mergePanel(page, id);
    if (next == null) return tr('只能和同一刀切出来的相邻格合并,锁着的格不合并');
    _selected = next.panels.containsKey(id) ? id : other;
    _setPage(next);
    return null;
  }

  void clearSelected() {
    final p = selectedPanel;
    if (p == null || p.locked) return;
    updatePanel(p.cleared());
  }

  // ── 抽卡 ──

  void _clearDraw() {
    _draw = null;
    _previewing = null;
  }

  /// 换一组现成的版式。
  void useStyle(String name) {
    styleName = name;
    style = mangaStyles[name]!;
    _clearDraw();
    notifyListeners();
  }

  /// 自己调版式参数:调过之后不再算哪一种现成的。
  void tuneStyle(MangaStyle next) {
    style = next;
    styleName =
        mangaStyles.entries.where((e) => e.value == next).firstOrNull?.key ??
        '';
    notifyListeners();
  }

  void setDrawOptions({bool? fixed, int? min, int? max, int? count}) {
    fixedCount = fixed ?? fixedCount;
    minPanels = (min ?? minPanels).clamp(1, mangaMaxPanels);
    maxPanels = (max ?? maxPanels).clamp(minPanels, mangaMaxPanels);
    drawCount = count ?? drawCount;
    notifyListeners();
  }

  void setView({bool? figures, bool? flow}) {
    showFigures = figures ?? showFigures;
    showFlow = flow ?? showFlow;
    notifyListeners();
  }

  /// 抽一组分格(换个新种子)。格数至少是有内容的格数,内容不会丢。
  void drawLayout({bool reroll = true}) {
    if (reroll) _seed = _newSeed();
    final filled = page.panels.values.where((p) => !p.isBlank).length;
    final order = readingOrder(page);
    int? atLeast(int? v) => v == null || v >= filled ? v : filled;
    _draw = drawLayouts(
      page,
      seed: _seed,
      style: style,
      minPanels: fixedCount ? atLeast(minPanels) : (filled > 0 ? filled : null),
      maxPanels: fixedCount ? atLeast(maxPanels) : null,
      count: drawCount,
      emphasis: [for (final id in order) page.panels[id]!.emphasis],
    );
    _previewing = _draw!.found.isEmpty ? null : 0;
    notifyListeners();
  }

  void preview(int? i) {
    _previewing = i;
    notifyListeners();
  }

  /// 用正在看的那张候选。
  void applyPreview() {
    final c = _previewing == null ? null : _draw?.found[_previewing!];
    if (c == null) return;
    final (ids, p) = project.newIds('panel', c.count);
    final applied = applyLayout(page, c.root, ids);
    if (applied == null) return;
    _clearDraw();
    _commit(
      p
          .copyWith(nextId: project.nextId + applied.used)
          .withPage(_page, applied.page),
    );
  }

  void closeDraw() {
    _clearDraw();
    notifyListeners();
  }

  /// 给没锁的格抽景别和角度。
  void drawShot() =>
      _setPage(drawShots(page, seed: _seed, attempt: _shotRolls++));

  // ── Agent ──

  /// 给 Agent 看的作品(眼前这个系列)。
  String get agentView => mangaAgentView(project, _page);

  /// 回复里完整的 `<storyboard>` 放进作品,返回记在回复上的一句;没写是 null。
  String? applyReply(String reply) {
    final specs = splitToolTag(reply, storyboardTag).queries;
    if (specs.isEmpty) return null;
    final board = parseStoryboard(specs.last);
    if (board == null) return tr('分镜读不了,没放上');
    final r = applyStoryboard(project, board, current: _page, seed: _seed);
    _clearDraw();
    _commit(r.project);
    return [...r.done, ...r.problems].join(' · ');
  }

  // ── 存盘 ──

  Timer? _saveTimer;

  File? get _file => dir == null
      ? null
      : File('${dir!.path}${Platform.pathSeparator}manga.json');

  void _scheduleSave() {
    if (_file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'shelf': [for (final p in _shelf) p.toJson()],
            'series': _series,
            'page': _page,
          }),
          flush: true,
        )
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('分镜没存上:{0}', [e.message]));
    }
  }

  /// 读回;旧版只有一部作品(`project`),读成一个系列。
  static List<MangaProject>? _read(Map<String, dynamic> j) {
    if (j['shelf'] case final List list) {
      final out = <MangaProject>[];
      for (final p in list.take(mangaMaxSeries)) {
        final read = MangaProject.fromJson(p);
        if (read == null) return null;
        out.add(read);
      }
      return out.isEmpty ? null : out;
    }
    final one = MangaProject.fromJson(j['project']);
    return one == null ? null : [one];
  }

  Future<void> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    List<MangaProject>? read;
    var series = 0, at = 0;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      read = _read(j);
      series = j['series'] is int ? j['series'] as int : 0;
      at = j['page'] is int ? j['page'] as int : 0;
    } on Object {
      read = null;
    }
    if (read == null) {
      // 读不了就从空白开始;文件先改名留底,不让下一次保存把它盖掉。
      try {
        file.renameSync(
          '${file.path}.bad-${DateTime.now().millisecondsSinceEpoch}',
        );
      } on FileSystemException {
        // 留底失败也不拦着程序启动。
      }
      return;
    }
    _shelf = List.unmodifiable(read);
    _series = series.clamp(0, read.length - 1);
    _page = at.clamp(0, project.pages.length - 1);
    _revision++;
    notifyListeners();
  }

  /// 关窗前立即保存。
  void flush() {
    _saveTimer?.cancel();
    _save();
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
