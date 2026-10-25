import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/characters/character_dict.dart';
import '../../../data/services/character_store.dart';
import '../../core/gallery.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'character_cards.dart';
part 'character_dialog.dart';

/// 添加或修改角色的窗口交回来的内容;[image] 为 null 表示图没动。
typedef _Draft = ({
  String name,
  String alias,
  String intro,
  String prompt,
  List<CharacterOutfit> outfits,
  CharacterImage? image,
});

/// 内置角色一次最多列出几个。
const _maxBuiltin = 30;

/// 先摆出来的系列有几个(角色最多的那些)。
const _maxSeries = 80;

/// 搜索时最多列出几个名字对得上的系列。
const _maxSeriesHits = 10;

/// 系列的格子至少这么宽,窗口窄了就少排几列;格子之间隔这么远。
const _seriesTileWidth = 220.0;
const _seriesGap = 10.0;

/// 「我的」大缩略图的格子至少这么宽。
const _mineTileWidth = 180.0;

/// 角色库的三页:用户自己存的、内置的、收藏的内置系列和角色。
enum _Tab { mine, builtin, favorites }

/// 角色库:用户自己存的角色(名字、图、提示词)、内置的 Danbooru 角色、收藏,各占一页。
class CharactersPage extends StatefulWidget {
  const CharactersPage({super.key, required this.store, required this.dict});

  final CharacterStore store;

  /// 内置的角色;没有就只有用户自己的那部分(测试用)。
  final CharacterDict? dict;

  @override
  State<CharactersPage> createState() => _CharactersPageState();
}

class _CharactersPageState extends State<CharactersPage> {
  var _query = '';

  /// 搜索框:点了搜出来的系列要把它清空。
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  var _tab = _Tab.mine;

  /// 打开一个系列看它名下的角色;从搜索结果、收藏点进来的,先把搜索清掉、切到内置。
  void _openSeries(String name) {
    _search.clear();
    setState(() {
      _query = '';
      _series = name;
      _tab = _Tab.builtin;
    });
  }

  Widget _builtinCard(CharacterHit hit) => _BuiltinCard(
    hit: hit,
    onSave: () => _edit(null, hit),
    favorite: widget.store.isFavoriteCharacter(hit.name),
    onFavorite: () => widget.store.toggleCharacter(hit.name),
  );

  /// 收藏页:收藏的系列在上,角色在下,新收藏的在前。
  Widget _favorites(CharacterDict dict) {
    final store = widget.store;
    final series = [
      for (final s in store.favoriteSeries) (name: s, count: dict.countOf(s)),
    ];
    final hits = [for (final n in store.favoriteCharacters) ?dict.byName(n)];
    if (series.isEmpty && hits.isEmpty) {
      return _Empty(tr('还没有收藏 · 在内置里点星标'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (series.isNotEmpty) ...[
          _Heading(tr('系列'), tr('{0} 个', [series.length])),
          const SizedBox(height: 8),
          _seriesGrid(series),
          const SizedBox(height: 18),
        ],
        if (hits.isNotEmpty) ...[
          _Heading(tr('角色'), tr('{0} 个', [hits.length])),
          for (final hit in hits) ...[
            const SizedBox(height: 8),
            _builtinCard(hit),
          ],
        ],
      ],
    );
  }

  /// 正在看哪个系列里的内置角色;null 是在看各个系列。
  String? _series;

  /// 「我的」按大缩略图(看图)还是列表看。
  var _grid = false;

  /// 换图:[source] 是选的或拖上来的图转成的 WebP。
  Future<void> _setImage(CharacterCard card, Future<Uint8List?> source) async {
    final webp = await source;
    if (webp != null && mounted) widget.store.setImage(card.id, webp);
  }

  Widget _mine(CharacterCard card) {
    final actions = (
      onEdit: () => _edit(card),
      onDelete: () => _delete(card),
      onUpload: () => _setImage(card, pickPreview(context)),
    );
    return GalleryItem(
      key: ValueKey(card.id),
      id: card.id,
      onMove: (dragged) => widget.store.move(dragged, card.id),
      onImage: (path) => _setImage(card, readPreview(context, path)),
      child: _grid
          ? _MineTile(card: card, actions: actions)
          : _MineCard(card: card, actions: actions),
    );
  }

  /// 大缩略图:一样大的格子排成几列。
  Widget _mineGrid(List<CharacterCard> cards) => LayoutBuilder(
    builder: (context, box) {
      final columns = (box.maxWidth / _mineTileWidth).floor().clamp(2, 8);
      final width = ((box.maxWidth - _seriesGap * (columns - 1)) / columns)
          .floorToDouble();
      return Wrap(
        spacing: _seriesGap,
        runSpacing: _seriesGap,
        children: [
          for (final c in cards) SizedBox(width: width, child: _mine(c)),
        ],
      );
    },
  );

  Future<void> _edit([CharacterCard? card, CharacterHit? from]) async {
    final draft = await showDialog<_Draft>(
      context: context,
      builder: (_) => _CharacterDialog(
        name: card?.name ?? from?.name ?? '',
        alias: card?.alias ?? from?.alias ?? '',
        intro: card?.intro ?? '',
        prompt: card?.prompt ?? (from == null ? '' : _fullPrompt(from)),
        outfits: card?.outfits ?? const [],
        image: card?.image ?? '',
        editing: card != null,
      ),
    );
    if (draft == null || !mounted) return;
    // 新选的图转成 WebP 存;转不了就原样存。
    final picked = draft.image;
    final webp = picked == null
        ? null
        : await toPreviewWebP(Uint8List.fromList(picked.bytes));
    if (!mounted) return;
    final saved = widget.store.put(
      id: card?.id,
      name: draft.name,
      alias: draft.alias,
      intro: draft.intro,
      prompt: draft.prompt,
      outfits: draft.outfits,
      image: webp == null ? picked : (bytes: webp, ext: 'webp'),
    );
    if (saved != null) showToast(context, tr('已存进角色库'));
  }

  Future<void> _delete(CharacterCard card) async {
    if (await confirmDelete(
      context,
      tr('删除角色「{0}」?', [card.name]),
      tr('删掉后找不回来。'),
    )) {
      widget.store.remove(card.id);
    }
  }

  /// 一格一个系列,格子一样大,排成整齐的几列(宽的时候 5 列)。
  Widget _seriesGrid(Iterable<({String name, int count})> series) =>
      LayoutBuilder(
        builder: (context, box) {
          final columns = (box.maxWidth / _seriesTileWidth).floor().clamp(2, 5);
          final width = (box.maxWidth - _seriesGap * (columns - 1)) / columns;
          return Wrap(
            spacing: _seriesGap,
            runSpacing: _seriesGap,
            children: [
              for (final s in series)
                SizedBox(
                  // 留一点余量:算出来的小数宽度加起来不能超过一行。
                  width: width.floorToDouble(),
                  child: _SeriesTile(
                    name: s.name,
                    count: s.count,
                    onTap: () => _openSeries(s.name),
                    favorite: widget.store.isFavoriteSeries(s.name),
                    onFavorite: () => widget.store.toggleSeries(s.name),
                  ),
                ),
            ],
          );
        },
      );

  /// 「内置」那一块:在查就是结果(名字对得上的系列在前,再是角色);没在查时先列
  /// 各个系列(角色多的在前),点一个系列看它名下的角色(图多的在前)。
  Widget _builtin(CharacterDict dict, String q, List<CharacterHit> found) {
    final series = _series;
    final hits = q.isNotEmpty
        ? found
        : series == null
        ? const <CharacterHit>[]
        : dict.inSeries(series);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (q.isNotEmpty) ...[
          if (dict.searchSeries(q, limit: _maxSeriesHits) case final hits
              when hits.isNotEmpty) ...[
            _Heading(tr('系列'), tr('{0} 个', [hits.length])),
            const SizedBox(height: 8),
            _seriesGrid(hits),
            const SizedBox(height: 14),
          ],
          _Heading(tr('内置'), tr('{0} 个', [found.length])),
        ] else if (series == null) ...[
          _Heading(tr('内置'), tr('{0} 个系列', [dict.series.length])),
          const SizedBox(height: 8),
          _seriesGrid(dict.series.take(_maxSeries)),
        ] else
          Row(
            children: [
              PennaButton(
                label: tr('全部系列'),
                icon: Icons.arrow_back,
                borderColor: PennaColors.border,
                onPressed: () => setState(() => _series = null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Heading(series, tr('前 {0} 个 · 图多的在前', [hits.length])),
              ),
              _star(
                widget.store.isFavoriteSeries(series),
                () => widget.store.toggleSeries(series),
              ),
            ],
          ),
        if (q.isNotEmpty && hits.isEmpty) _Empty(tr('没有找到')),
        for (final hit in hits) ...[
          const SizedBox(height: 8),
          _builtinCard(hit),
        ],
      ],
    );
  }

  /// 内置那一页的三种样子:查名字的结果、各个系列、某个系列里的角色。
  /// 换的时候旧的淡出、新的滑进来,高度跟着顺过去。
  Widget _builtinAnimated(CharacterDict dict, String q) => AnimatedSize(
    duration: Motion.sheet,
    curve: Motion.swift,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: Motion.sheet,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(q.isNotEmpty ? tr('查') : _series ?? tr('系列')),
        child: _builtin(
          dict,
          q,
          q.isEmpty ? const [] : dict.search(q, limit: _maxBuiltin),
        ),
      ),
    ),
  );

  /// 「我的」那一页:列表或大缩略图,拖着排顺序。
  List<Widget> _minePage(List<CharacterCard> mine, String q) => [
    if (mine.isEmpty)
      _Empty(q.isEmpty ? tr('还没有角色 · 点「添加角色」,或让 Agent 存') : tr('没有找到'))
    else if (_grid)
      _mineGrid(mine)
    else
      for (final card in mine) ...[_mine(card), const SizedBox(height: 8)],
  ];

  Widget _searchBox() => PennaCard(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: TextField(
      contextMenuBuilder: pennaTextMenu,
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        icon: Icon(Icons.search, size: 17, color: PennaColors.slate400),
        hintText: _tab == _Tab.mine
            ? tr('按名字找')
            : tr('按名字或系列找:初音未来、甘雨、genshin impact'),
        hintStyle: TextStyle(fontSize: 12.5, color: PennaColors.slate400),
        border: InputBorder.none,
        isDense: true,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final dict = widget.dict;
        // 没有内置数据(测试)时只有「我的」。
        final tab = dict == null ? _Tab.mine : _tab;
        final q = _query.trim();
        final mine = q.isEmpty ? store.cards : store.find(q);
        final count = switch (tab) {
          _Tab.mine => store.cards.length,
          _Tab.builtin => dict!.length,
          _Tab.favorites =>
            store.favoriteSeries.length + store.favoriteCharacters.length,
        };
        return ColoredBox(
          color: PennaColors.editorBg,
          child: Column(
            children: [
              PennaBar(
                color: PennaColors.card,
                children: [
                  Icon(
                    Icons.face_retouching_natural_outlined,
                    size: 15,
                    color: PennaColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tr('角色库'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 24),
                  if (dict != null)
                    for (final (t, label) in [
                      (_Tab.mine, tr('我的')),
                      (_Tab.builtin, tr('内置')),
                      (_Tab.favorites, tr('收藏')),
                    ]) ...[
                      PennaChip(
                        label: label,
                        selected: tab == t,
                        onTap: () => setState(() => _tab = t),
                      ),
                      const SizedBox(width: 6),
                    ],
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tr('{0} 个', [count]),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                  if (tab == _Tab.mine) ...[
                    ViewSwitch(
                      grid: _grid,
                      onChanged: (g) => setState(() => _grid = g),
                    ),
                    const SizedBox(width: 8),
                    PennaButton(
                      label: tr('添加角色'),
                      icon: Icons.add,
                      background: PennaColors.primary,
                      foreground: Colors.white,
                      onPressed: _edit,
                    ),
                  ],
                ],
              ),
              Expanded(
                child: SmoothScroller(
                  builder: (controller) => ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (tab != _Tab.favorites) ...[
                        _searchBox(),
                        const SizedBox(height: 14),
                      ],
                      ...switch (tab) {
                        _Tab.mine => _minePage(mine, q),
                        _Tab.builtin => [_builtinAnimated(dict!, q)],
                        _Tab.favorites => [_favorites(dict!)],
                      },
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 内置角色的整条提示词:触发词、外貌、服装。
String _fullPrompt(CharacterHit c) => [
  characterTrigger(c),
  c.looks,
  c.outfit,
].where((s) => s.isNotEmpty).join(', ');
