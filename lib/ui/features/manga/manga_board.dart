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
import '../../../l10n/l10n.dart';

/// 撤销最多记几步。
const _maxUndo = 100;

/// 打字时连着改同一样东西,这么久之内算同一步撤销。
const _typingGap = Duration(seconds: 1);

/// 漫画分镜工作台的状态:作品、眼前第几页、选中哪一格、撤销重做、抽到的卡。
/// 存在「文档\Penna\manga.json」。
class MangaBoard extends ChangeNotifier {
  MangaBoard({this.dir});

  /// 存盘的文件夹;null 时不存(测试用)。
  final Directory? dir;

  MangaProject _project = MangaProject.blank();
  int _page = 0;
  String? _selected;
  List<MangaProject> _undo = const [], _redo = const [];
  String? _typing;
  DateTime _typedAt = DateTime(0);

  /// 外面(撤销、Agent、抽卡)改了内容就加一:输入框靠它知道要换成新的字。
  int _revision = 0;

  /// 抽到的分格(没应用);[previewing] 是正在画布上看的那张。
  MangaDraw? _draw;
  int? _previewing;
  String _seed = _newSeed();
  int minPanels = 3, maxPanels = 6;
  int _shotRolls = 0;

  MangaProject get project => _project;
  int get pageIndex => _page;
  MangaPage get page => _project.pages[_page];
  String? get selected => _selected;
  MangaPanel? get selectedPanel =>
      _selected == null ? null : page.panels[_selected];
  int get revision => _revision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  MangaDraw? get draw => _draw;
  int? get previewing => _previewing;
  String get seed => _seed;

  /// 画布上画的那一页:看着候选时是候选套上去的样子(不进作品)。
  MangaPage get shown {
    final c = _previewing == null ? null : _draw?.found[_previewing!];
    if (c == null) return page;
    return applyLayout(page, c.root, [
          for (var i = 0; i < c.count; i++) '~$i',
        ])?.page ??
        page;
  }

  static String _newSeed() =>
      Random().nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0');

  /// 改一步:旧的进撤销栈。[typing] 是打字时改的哪一样,连着打的字合成一步。
  void _commit(MangaProject next, {String? typing}) {
    if (identical(next, _project)) return;
    final now = DateTime.now();
    final merge =
        typing != null &&
        typing == _typing &&
        now.difference(_typedAt) < _typingGap;
    if (!merge) {
      _undo = List.unmodifiable(
        [..._undo, _project].skip(_undo.length + 1 > _maxUndo ? 1 : 0),
      );
    }
    _typing = typing;
    _typedAt = now;
    _redo = const [];
    _project = next;
    if (typing == null) _revision++;
    _afterChange();
  }

  void _afterChange() {
    if (_page >= _project.pages.length) _page = _project.pages.length - 1;
    if (_selected != null && !page.panels.containsKey(_selected)) {
      _selected = null;
    }
    _scheduleSave();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo = List.unmodifiable([..._redo, _project]);
    _project = _undo.last;
    _undo = List.unmodifiable(_undo.take(_undo.length - 1));
    _typing = null;
    _revision++;
    _afterChange();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo = List.unmodifiable([..._undo, _project]);
    _project = _redo.last;
    _redo = List.unmodifiable(_redo.take(_redo.length - 1));
    _typing = null;
    _revision++;
    _afterChange();
  }

  void _setPage(MangaPage p, {String? typing}) =>
      _commit(_project.withPage(_page, p), typing: typing);

  // ── 页 ──

  void showPage(int i) {
    if (i < 0 || i >= _project.pages.length || i == _page) return;
    _page = i;
    _selected = null;
    _clearDraw();
    notifyListeners();
  }

  /// 在眼前这页后面加一张空白页(纸张、方向照眼前这页)并换过去。
  void addPage() {
    final (ids, p) = _project.newIds('page', 2);
    final pages = [...p.pages]
      ..insert(_page + 1, blankMangaPage(ids[0], ids[1], like: page));
    _commit(p.copyWith(pages: pages));
    showPage(_page + 1);
  }

  /// 删掉第 [i] 页;只剩一页时不删。
  void removePage(int i) {
    if (_project.pages.length <= 1) return;
    final pages = [..._project.pages]..removeAt(i);
    if (_page >= i && _page > 0) _page--;
    _clearDraw();
    _commit(_project.copyWith(pages: pages));
  }

  void select(String? panel) {
    if (_selected == panel) return;
    _selected = panel;
    notifyListeners();
  }

  // ── 设定 ──

  void setTitle(String v) =>
      _commit(_project.copyWith(title: v), typing: 'title');
  void setSetting(String v) =>
      _commit(_project.copyWith(setting: v), typing: 'setting');

  void setCharacter(int i, MangaCharacter c) {
    final list = [..._project.characters];
    i < list.length ? list[i] = c : list.add(c);
    _commit(_project.copyWith(characters: list), typing: 'character-$i');
  }

  void removeCharacter(int i) {
    final list = [..._project.characters]..removeAt(i);
    _commit(_project.copyWith(characters: list));
  }

  // ── 纸张 ──

  void setPaper(int width, int height) {
    _clearDraw();
    _setPage(page.copyWith(width: width, height: height));
  }

  void setNote(String v) => _setPage(page.copyWith(note: v), typing: 'note');

  void setRtl(bool rtl) => _setPage(page.copyWith(rtl: rtl));

  // ── 格 ──

  /// 改选中那格的内容;[typing] 见 [_commit]。
  void updatePanel(MangaPanel p, {String? typing}) => _setPage(
    page.withPanel(p),
    typing: typing == null ? null : '${p.id}/$typing',
  );

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
    final (ids, p) = _project.newIds('panel', 1);
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

  /// 抽一组分格(换个新种子);格数不少于有内容的格。
  void drawLayout({bool reroll = true}) {
    if (reroll) _seed = _newSeed();
    final filled = page.panels.values.where((p) => !p.isBlank).length;
    final order = readingOrder(page);
    _draw = drawLayouts(
      page,
      seed: _seed,
      minPanels: minPanels > filled ? minPanels : filled,
      maxPanels: maxPanels > filled ? maxPanels : filled,
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
    final (ids, p) = _project.newIds('panel', c.count);
    final applied = applyLayout(page, c.root, ids);
    if (applied == null) return;
    _clearDraw();
    _commit(
      p
          .copyWith(nextId: _project.nextId + applied.used)
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

  /// 给 Agent 看的作品。
  String get agentView => mangaAgentView(_project, _page);

  /// 回复里完整的 `<storyboard>` 放进作品,返回记在回复上的一句;没写是 null。
  String? applyReply(String reply) {
    final specs = splitToolTag(reply, storyboardTag).queries;
    if (specs.isEmpty) return null;
    final board = parseStoryboard(specs.last);
    if (board == null) return tr('分镜读不了,没放上');
    final r = applyStoryboard(_project, board, current: _page, seed: _seed);
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
          jsonEncode({'project': _project.toJson(), 'page': _page}),
          flush: true,
        )
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('分镜没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = _file;
    if (file == null || !file.existsSync()) return;
    MangaProject? read;
    var at = 0;
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      read = MangaProject.fromJson(j['project']);
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
    _project = read;
    _page = at.clamp(0, read.pages.length - 1);
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
