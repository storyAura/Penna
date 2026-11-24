import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/harness/comfyui.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'comfy_runner.dart';
import '../../../core/harness/lora_library.dart';

/// 右侧面板里的「Lora Manager 库」:搜索、排序、文件夹、只看收藏，
/// 卡片带预览图、底模和触发词，点一下加进工作流或从工作流里去掉。
///
/// 数据来自 ComfyUI 的 Lora Manager 插件(`/api/lm/loras/list`)，
/// 没装这个插件时显示一句提示，不影响面板其它部分。
class LoraGallery extends StatefulWidget {
  const LoraGallery({
    super.key,
    required this.runner,
    required this.added,
    required this.onTap,
  });

  final ComfyRunner runner;

  /// 已经在用的 LoRA(比较键见 [loraKey])，用来标「已添加」和决定点一下是加还是删。
  final Set<String> added;

  /// 点一张卡片:外面决定是加进工作流还是从工作流里去掉。
  final void Function(LoraEntry entry) onTap;

  @override
  State<LoraGallery> createState() => _LoraGalleryState();
}

const _pageSize = 24;
const _sorts = [
  (value: 'name', label: '名称'),
  (value: 'date', label: '时间'),
  (value: 'usage', label: '常用'),
  (value: 'recent', label: '最近'),
];

// 侧栏是按需建的列表:滚出去会被拆掉、回来重读,高度一缩整个面板就弹回顶上
// (2026-11-25 用户反馈),所以留着它。
class _LoraGalleryState extends State<LoraGallery>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _search = TextEditingController();
  Timer? _typing;

  List<LoraEntry> _entries = const [];
  List<String> _folders = const [];
  String _sort = 'name';
  String _folder = '';
  bool _favorites = false;

  /// 文件夹树展开着没有，以及树里哪些层展开了。
  bool _treeOpen = false;
  final Set<String> _expanded = {};

  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  bool _loading = false;
  bool _missing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onTyping);
    unawaited(_loadFolders());
    unawaited(_load(1));
  }

  @override
  void dispose() {
    _typing?.cancel();
    _search.removeListener(_onTyping);
    _search.dispose();
    super.dispose();
  }

  void _onTyping() {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 350), () => _load(1));
  }

  Future<void> _loadFolders() async {
    try {
      final json = await widget.runner.client.loraFolders();
      if (!mounted) return;
      setState(() => _folders = parseLoraFolders(json));
    } on Object {
      // 没有这个接口就是没装插件，列表那边会说明。
    }
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await widget.runner.client.loraLibrary(
        page: page,
        pageSize: _pageSize,
        search: _search.text,
        sortBy: _sort,
        folder: _folder,
        favoritesOnly: _favorites,
      );
      final got = parseLoraPage(json);
      if (!mounted) return;
      setState(() {
        _missing = false;
        _page = got.page;
        _totalPages = got.totalPages;
        _total = got.total;
        _entries = [if (page > 1) ..._entries, ...got.entries];
      });
    } on ComfyException catch (e) {
      if (!mounted) return;
      setState(() {
        _missing = true;
        _error = e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = tr('读不到 Lora Manager:{0}', ['$e']));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 这条在不在当前工作流里(名字去掉目录和后缀比)。
  bool _added(LoraEntry e) =>
      widget.added.contains(loraKey(e.stem)) ||
      widget.added.contains(loraKey(e.file));

  /// 右键一张卡片:收藏或取消收藏(写回 Lora Manager)。
  Future<void> _menu(LoraEntry e, Offset at) async {
    final label = e.favorite ? tr('取消收藏') : tr('收藏');
    final picked = await popMenu(context, at, [label]);
    if (picked == null || !mounted) return;
    try {
      await widget.runner.client.setLoraFavorite(e.path, !e.favorite);
      if (!mounted) return;
      setState(() {
        _entries = [
          for (final x in _entries)
            if (x.path == e.path)
              (
                name: x.name,
                file: x.file,
                path: x.path,
                stem: x.stem,
                folder: x.folder,
                baseModel: x.baseModel,
                preview: x.preview,
                triggers: x.triggers,
                favorite: !x.favorite,
                usage: x.usage,
              )
            else
              x,
        ];
      });
    } on ComfyException catch (err) {
      if (mounted) showToast(context, err.message, warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchBox(),
        const SizedBox(height: 6),
        _filters(),
        if (_missing)
          _hint(tr('没连上 Lora Manager 插件'))
        else if (_error != null)
          _hint(_error!)
        else if (!_loading && _entries.isEmpty)
          _hint(tr('没有匹配的 LoRA')),
        if (_entries.isNotEmpty) ...[
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _entries.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              // 三列方格(2026-11-25 用户嫌两列竖卡太长)。
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, i) {
              final e = _entries[i];
              return _card(e, added: _added(e));
            },
          ),
          if (_page < _totalPages)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: PennaButton(
                label: _loading
                    ? tr('加载中…')
                    : tr('加载更多 {0}/{1}', [_entries.length, _total]),
                foreground: PennaColors.primary,
                onPressed: _loading ? null : () => _load(_page + 1),
              ),
            ),
        ],
      ],
    );
  }

  Widget _searchBox() => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: PennaColors.editorBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: PennaColors.border),
    ),
    child: Row(
      children: [
        Icon(Icons.search, size: 14, color: PennaColors.slate400),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _search,
            style: TextStyle(fontSize: 12, color: PennaColors.text),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: tr('搜名字、触发词'),
              hintStyle: TextStyle(fontSize: 12, color: PennaColors.slate400),
            ),
          ),
        ),
        if (_search.text.isNotEmpty)
          GestureDetector(
            onTap: () {
              _search.clear();
              _load(1);
            },
            child: Icon(Icons.close, size: 13, color: PennaColors.slate400),
          ),
      ],
    ),
  );

  Widget _filters() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: _dropdown(
              icon: Icons.sort,
              value: _sort,
              items: [
                for (final s in _sorts) (value: s.value, label: tr(s.label)),
              ],
              onChanged: (v) {
                setState(() => _sort = v);
                _load(1);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _folderButton()),
          const SizedBox(width: 4),
          Tooltip(
            message: tr('只看收藏'),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                setState(() => _favorites = !_favorites);
                _load(1);
              },
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _favorites ? PennaColors.amber : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: PennaColors.border),
                ),
                child: Icon(
                  _favorites ? Icons.star : Icons.star_border,
                  size: 15,
                  color: _favorites ? Colors.white : PennaColors.slate500,
                ),
              ),
            ),
          ),
        ],
      ),
      // 文件夹树:Lora Manager 里就是一层层的目录，这里照它的层级展开。
      if (_treeOpen) ...[const SizedBox(height: 6), _folderTree()],
    ],
  );

  Widget _folderButton() => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: () => setState(() => _treeOpen = !_treeOpen),
    child: Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _treeOpen ? PennaColors.primary : PennaColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 13, color: PennaColors.slate400),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _folder.isEmpty ? tr('全部文件夹') : _folder.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: PennaColors.slate700),
            ),
          ),
          Icon(
            _treeOpen ? Icons.expand_less : Icons.expand_more,
            size: 15,
            color: PennaColors.slate400,
          ),
        ],
      ),
    ),
  );

  Widget _folderTree() {
    final root = _buildTree();
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: PennaColors.editorBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PennaColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _folderRow(path: '', name: tr('全部 LoRA'), depth: 0),
            for (final child in root.children) ..._folderBranch(child, 0),
          ],
        ),
      ),
    );
  }

  List<Widget> _folderBranch(_FolderNode node, int depth) {
    final open = _expanded.contains(node.path);
    return [
      _folderRow(
        path: node.path,
        name: node.name,
        depth: depth,
        open: open,
        hasChildren: node.children.isNotEmpty,
      ),
      if (open)
        for (final child in node.children) ..._folderBranch(child, depth + 1),
    ];
  }

  Widget _folderRow({
    required String path,
    required String name,
    required int depth,
    bool open = false,
    bool hasChildren = false,
  }) {
    final selected = _folder == path;
    return InkWell(
      onTap: () {
        setState(() {
          _folder = path;
          _treeOpen = false;
          if (hasChildren) _expanded.add(path);
        });
        _load(1);
      },
      child: Container(
        height: 24,
        padding: EdgeInsets.only(left: 4 + depth * 12, right: 6),
        color: selected ? PennaColors.primaryBg : null,
        child: Row(
          children: [
            if (hasChildren)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  open ? _expanded.remove(path) : _expanded.add(path);
                }),
                child: Icon(
                  open ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 15,
                  color: PennaColors.slate400,
                ),
              )
            else
              const SizedBox(width: 15),
            const SizedBox(width: 2),
            Icon(
              path.isEmpty ? Icons.folder_open : Icons.folder_outlined,
              size: 12,
              color: selected ? PennaColors.primary : PennaColors.slate400,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: selected ? PennaColors.primary : PennaColors.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 把 `/api/lm/loras/folders` 那种“一层一层斜杠连起来”的路径拼成树。
  _FolderNode _buildTree() {
    final root = _FolderNode('', '');
    final byPath = <String, _FolderNode>{'': root};
    for (final raw in _folders) {
      final folder = raw.trim();
      if (folder.isEmpty) continue;
      var parent = root;
      var path = '';
      for (final part in folder.split('/')) {
        if (part.isEmpty) continue;
        path = path.isEmpty ? part : '$path/$part';
        final node = byPath.putIfAbsent(path, () => _FolderNode(part, path));
        if (!parent.children.contains(node)) parent.children.add(node);
        parent = node;
      }
    }
    void sortDeep(_FolderNode n) {
      n.children.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      n.children.forEach(sortDeep);
    }

    sortDeep(root);
    return root;
  }

  Widget _dropdown({
    required IconData icon,
    required String value,
    required List<({String value, String label})> items,
    required void Function(String) onChanged,
  }) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: PennaColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, size: 13, color: PennaColors.slate400),
        const SizedBox(width: 4),
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: '',
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final it in items)
                PopupMenuItem(
                  value: it.value,
                  height: 32,
                  child: Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: PennaColors.text),
                  ),
                ),
            ],
            child: Text(
              items
                      .where((it) => it.value == value)
                      .map((it) => it.label)
                      .firstOrNull ??
                  value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: PennaColors.slate700),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, height: 1.4, color: PennaColors.slate500),
    ),
  );

  Widget _card(LoraEntry e, {required bool added}) {
    final preview = widget.runner.client.absolute(e.preview);
    return Tooltip(
      message: [
        e.name,
        if (e.folder.isNotEmpty) e.folder,
        if (e.baseModel.isNotEmpty) e.baseModel,
        if (e.triggers.isNotEmpty) e.triggers.join(', '),
      ].join('\n'),
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onTap(e),
        onSecondaryTapDown: (d) => _menu(e, d.globalPosition),
        child: Container(
          decoration: BoxDecoration(
            color: PennaColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: added ? PennaColors.primary : PennaColors.border,
              width: added ? 1.4 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview.isEmpty)
                _placeholder()
              else
                Image.network(
                  preview,
                  headers: widget.runner.client.headers,
                  fit: BoxFit.cover,
                  cacheWidth: 320,
                  errorBuilder: (_, _, _) => _placeholder(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : _placeholder(),
                ),
              // 底部渐变，名字压在上面才看得清。
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 5,
                child: Text(
                  e.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              // 底模不明的不标(以前满屏 Unknown)。
              if (e.baseModel.isNotEmpty &&
                  e.baseModel.toLowerCase() != 'unknown')
                // 右边让出「+」的位置,长的底模名截断。
                Positioned(
                  left: 4,
                  top: 4,
                  right: 26,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _badge(e.baseModel),
                  ),
                ),
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: added
                        ? PennaColors.primary
                        : Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    added ? Icons.check : Icons.add,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
              if (e.favorite)
                const Positioned(
                  right: 4,
                  top: 25,
                  child: Icon(Icons.star, size: 13, color: Colors.amber),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: PennaColors.editorBg,
    alignment: Alignment.center,
    child: Icon(Icons.image_outlined, size: 20, color: PennaColors.slate400),
  );

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 9, color: Colors.white),
    ),
  );
}

/// 文件夹树上的一个节点。
class _FolderNode {
  _FolderNode(this.name, this.path);

  final String name;
  final String path;
  final List<_FolderNode> children = [];
}
