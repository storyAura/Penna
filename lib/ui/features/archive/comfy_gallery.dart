import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/comfyui.dart';
import '../../../l10n/l10n.dart';
import '../../core/gallery.dart';
import '../../core/motion.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../studio/image_viewer.dart';
import '../studio/studio_view_model.dart';

const _tileWidth = 200.0;
const _gap = 10.0;

/// 一次最多读多少单(每单可能出好几张)。
const _maxRuns = 300;

/// 一次显示多少张,「显示更多」再加这么多。
const _page = 300;

/// 文件夹下拉里「全部」的值(文件夹名不会是它)。
const _allFolders = '\u0000';

/// 本机地址:这些地址的 ComfyUI 能直接读硬盘上的输出文件夹。
const _localHosts = {'127.0.0.1', 'localhost', '::1'};

/// 档案库的「图片」分区:读 ComfyUI 的输出文件夹,再用出图历史(`/history`)补上提示词和时刻,
/// 在 ComfyUI 里跑的也算。本机的 ComfyUI 直接读硬盘(连子文件夹,照启动参数找文件夹,
/// 也能手动选;2026-11-09 用户要求),别的只能用 `/internal/files/output` 列最外层。
/// 能按文件夹筛(output 最外层单独一项);点开看原图;右键复制图片、复制当时的提示词、放回成稿。
// ponytail: 云端的 ComfyUI 读不到子文件夹,历史没记着的也没有时刻(归在「更早」);
// 硬盘上一次最多列 2 万张(新改的在前),界面一次显示 300 张。
class ComfyGallery extends StatefulWidget {
  const ComfyGallery({super.key, required this.vm, required this.onOpenStudio});

  final StudioViewModel vm;

  /// 放回成稿之后回到工作台。
  final VoidCallback onOpenStudio;

  @override
  State<ComfyGallery> createState() => _ComfyGalleryState();
}

class _ComfyGalleryState extends State<ComfyGallery> {
  List<ComfyShot>? _shots;
  String? _error;
  bool _loading = false;

  /// 读的是硬盘上的哪个输出文件夹;读不了硬盘时是 null。
  String? _dir;

  /// 只看哪个文件夹(`''` 是 output 最外层);null 是全部。
  String? _folder;

  /// 眼前最多显示几张。
  int _limit = _page;

  /// 正在打开大图的那张(打开要读原图,大图慢一点,先转个圈)。
  ComfyShot? _opening;

  /// 上次读的时候 Penna 出过几张:又出了新的就重读。
  int _seen = 0;

  /// 大缩略图还是列表(2026-11-08 用户要求两种看法)。
  bool _grid = true;

  /// 收起来的日子(`dayKey`)。
  final _collapsed = <String>{};

  ComfyRunner get runner => widget.vm.comfy;

  @override
  void initState() {
    super.initState();
    runner.addListener(_onRunner);
    unawaited(_load());
  }

  @override
  void dispose() {
    runner.removeListener(_onRunner);
    super.dispose();
  }

  void _onRunner() {
    if (runner.images.length != _seen) unawaited(_load());
  }

  /// 输出文件夹:设置里选过的;没选过时本机的 ComfyUI 照启动参数找。找不到是 null。
  Future<String?> _outputDir() async {
    final comfy = runner.config.config.comfy;
    final picked = comfy.outputDirs[comfy.server.id];
    if (picked != null) return picked;
    final host = Uri.tryParse(comfy.server.url)?.host ?? '';
    if (!_localHosts.contains(host)) return null;
    try {
      final dir = await runner.client.outputDir();
      return dir != null && Directory(dir).existsSync() ? dir : null;
    } on Object {
      return null;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    _seen = runner.images.length;
    final client = runner.client;
    var history = const <ComfyShot>[];
    String? error;
    try {
      history = await client.history(max: _maxRuns);
    } on ComfyException catch (e) {
      error = e.message;
    } on Object catch (e) {
      error = tr('读取失败({0})', [e.runtimeType]);
    }
    final dir = await _outputDir();
    var files = const <ComfyShot>[];
    try {
      if (dir != null) {
        files = await listOutputFolder(dir);
      } else if (error == null) {
        // 老版本没有列文件的接口:那就只有历史里的。
        files = shotsOfFiles(
          await client.outputFiles().catchError(
            (Object _) => const <Map<String, Object?>>[],
          ),
        );
      }
    } on FileSystemException catch (e) {
      error ??= tr('输出文件夹读不了:{0}', [e.message]);
    }
    if (!mounted) return;
    final shots = mergeShots(history, files);
    setState(() {
      _loading = false;
      _dir = dir;
      // ComfyUI 没开、硬盘上也没读到时才只报错。
      _shots = shots.isEmpty && error != null ? _shots : shots;
      _error = error;
    });
  }

  /// 选一个输出文件夹记进设置(按眼前这台);[reset] 时去掉,回到自动找。
  Future<void> _pickDir({bool reset = false}) async {
    final config = runner.config;
    final comfy = config.config.comfy;
    String? path;
    if (!reset) {
      path = await getDirectoryPath(
        initialDirectory: _dir,
        confirmButtonText: tr('选择'),
      );
      if (path == null) return;
    }
    final dirs = {...comfy.outputDirs}..remove(comfy.server.id);
    if (path != null) dirs[comfy.server.id] = path;
    config.update(
      config.config.copyWith(comfy: comfy.copyWith(outputDirs: dirs)),
    );
    setState(() {
      _folder = null;
      _limit = _page;
    });
    await _load();
  }

  /// 原图,当成图片附件(看大图、复制都用它):硬盘上的直接读,别的从 ComfyUI 下载。
  Future<Attachment?> _full(ComfyShot shot) async {
    final name = '${shot.file['filename']}';
    final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    final mime = imageMimes[ext] ?? 'image/png';
    final path = shot.path;
    if (path != null) {
      if (File(path).existsSync()) {
        return Attachment.saved(name: name, file: path, mime: mime);
      }
      if (mounted) showToast(context, tr('这张图的文件不在了'), warn: true);
      return null;
    }
    try {
      final bytes = await runner.client.download(shot.file);
      return Attachment.image(name: name, mime: mime, bytes: bytes);
    } on ComfyException catch (e) {
      if (mounted) showToast(context, e.message, warn: true);
    } on Object catch (e) {
      if (mounted) {
        showToast(context, tr('读取失败({0})', [e.runtimeType]), warn: true);
      }
    }
    return null;
  }

  Future<void> _open(ComfyShot shot) async {
    if (_opening != null) return;
    setState(() => _opening = shot);
    final image = await _full(shot);
    if (!mounted) return;
    setState(() => _opening = null);
    if (image != null) await showImageViewer(context, image);
  }

  Future<void> _menu(ComfyShot shot, Offset at) async {
    final copyPicture = tr('复制图片'),
        copyPrompt = tr('复制提示词'),
        restore = tr('放回成稿'),
        reveal = tr('在文件夹中显示'),
        delete = tr('删除');
    final path = shot.path;
    final picked = await popMenu(context, at, [
      copyPicture,
      if (shot.prompt.isNotEmpty) ...[copyPrompt, restore],
      if (path != null && Platform.isWindows) reveal,
      // 只在输出文件夹里、历史没记着的没法删(ComfyUI 没有删文件的接口)。
      if (shot.id.isNotEmpty) delete,
    ]);
    if (!mounted) return;
    if (picked == delete) return _delete(shot);
    if (picked == reveal) {
      await Process.run('explorer', ['/select,', path!]);
    } else if (picked == copyPicture) {
      final image = await _full(shot);
      if (image == null) return;
      final problem = await copyImage(image);
      if (mounted) {
        showToast(context, problem ?? tr('已复制'), warn: problem != null);
      }
    } else if (picked == copyPrompt) {
      copyWithToast(context, shot.prompt, tr('已复制'));
    } else if (picked == restore) {
      final problem = widget.vm.restorePrompt((
        time: shot.time ?? DateTime.now(),
        text: shot.prompt,
      ), title: tr('档案库'));
      if (problem != null) return showToast(context, problem, warn: true);
      widget.onOpenStudio();
    }
  }

  /// 从 ComfyUI 的历史里去掉这一单(同一单出的几张一起去掉),再重读。
  Future<void> _delete(ComfyShot shot) async {
    final same = _shots?.where((s) => s.id == shot.id).length ?? 1;
    if (!await confirmDelete(
      context,
      same > 1 ? tr('删除这一单的 {0} 张图?', [same]) : tr('删除这张图?'),
      tr('从 ComfyUI 的出图历史里去掉;ComfyUI 输出文件夹里的原图不会删。'),
    )) {
      return;
    }
    try {
      await runner.client.forget([shot.id]);
    } on ComfyException catch (e) {
      if (mounted) showToast(context, e.message, warn: true);
      return;
    }
    // 先从眼前去掉,不等重读。
    if (mounted) {
      setState(() => _shots = [...?_shots?.where((s) => s.id != shot.id)]);
    }
    await _load();
  }

  String _folderName(String? folder) => folder == null
      ? tr('全部文件夹')
      : folder.isEmpty
      ? tr('output 根目录')
      : folder;

  /// 按文件夹筛的下拉:全部、output 最外层、各个子文件夹,后面带张数。
  Widget _folders(List<ComfyShot> shots) {
    final counts = <String, int>{};
    for (final s in shots) {
      counts.update(shotFolder(s), (n) => n + 1, ifAbsent: () => 1);
    }
    final subs = counts.keys.where((f) => f.isNotEmpty).toList()..sort();
    PopupMenuItem<String> item(String? folder, int n) => CheckedPopupMenuItem(
      value: folder ?? _allFolders,
      checked: folder == _folder,
      height: 34,
      child: Text(
        '${_folderName(folder)}  ·  $n',
        style: const TextStyle(fontSize: 12.5),
      ),
    );
    return PopupMenuButton<String>(
      popUpAnimationStyle: Motion.menu(context),
      tooltip: tr('按文件夹看'),
      position: PopupMenuPosition.under,
      onSelected: (v) => setState(() {
        _folder = v == _allFolders ? null : v;
        _limit = _page;
      }),
      itemBuilder: (_) => [
        item(null, shots.length),
        item('', counts[''] ?? 0),
        for (final f in subs) item(f, counts[f]!),
      ],
      child: PennaChip(
        label: _folderName(_folder),
        selected: _folder != null,
        onTap: null,
      ),
    );
  }

  /// 输出文件夹:选一个,或回到自动找(选过时)。
  Widget _dirButton() {
    final comfy = runner.config.config.comfy;
    final picked = comfy.outputDirs.containsKey(comfy.server.id);
    return PopupMenuButton<bool>(
      popUpAnimationStyle: Motion.menu(context),
      tooltip: _dir == null ? tr('选择输出文件夹') : tr('输出文件夹:{0}', [_dir]),
      position: PopupMenuPosition.under,
      onSelected: (reset) => _pickDir(reset: reset),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: false,
          height: 34,
          child: Text(tr('选择输出文件夹…'), style: const TextStyle(fontSize: 12.5)),
        ),
        if (picked)
          PopupMenuItem(
            value: true,
            height: 34,
            child: Text(tr('自动查找'), style: const TextStyle(fontSize: 12.5)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          Icons.drive_folder_upload_outlined,
          size: 18,
          color: PennaColors.slate500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shots = _shots;
    final note = TextStyle(fontSize: 12, color: PennaColors.slate400);
    final visible = shots == null || _folder == null
        ? shots
        : [
            for (final s in shots)
              if (shotFolder(s) == _folder) s,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              if (shots != null && shots.isNotEmpty) ...[
                _folders(shots),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  visible == null
                      ? ''
                      : [
                          tr('{0} 张 · 读自 {1}', [
                            visible.length,
                            _dir ?? runner.config.config.comfy.server.url,
                          ]),
                          if (_error != null && shots!.isNotEmpty)
                            tr('出图历史读不了,没有提示词'),
                        ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                ),
              ),
              _dirButton(),
              const SizedBox(width: 4),
              ViewSwitch(
                grid: _grid,
                onChanged: (g) => setState(() => _grid = g),
              ),
              const SizedBox(width: 6),
              PennaButton(
                label: tr('刷新'),
                icon: Icons.refresh,
                borderColor: PennaColors.border,
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
        Expanded(
          child: switch ((visible, _error)) {
            (null, null) => const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            (null, final error?) => Center(child: Text(error, style: note)),
            (final list?, _) when list.isEmpty => Center(
              child: Text(tr('ComfyUI 里还没有出过的图'), style: note),
            ),
            (final list?, _) => _days(list),
          },
        ),
      ],
    );
  }

  /// 按日子分组(新的在前),每组一个能点着收起、展开的标题;多了先显示 [_limit] 张。
  Widget _days(List<ComfyShot> all) {
    final shots = all.take(_limit).toList();
    final more = all.length - shots.length;
    final days = <String, List<ComfyShot>>{};
    for (final s in shots) {
      (days[dayKey(s.time)] ??= []).add(s);
    }
    return SmoothScroller(
      builder: (controller) => LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth - 32;
          final columns = (width / _tileWidth).floor().clamp(2, 8);
          final tile = ((width - _gap * (columns - 1)) / columns)
              .floorToDouble();
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final MapEntry(key: day, value: list) in days.entries) ...[
                _DayHeader(
                  label: dayLabel(day),
                  count: list.length,
                  open: !_collapsed.contains(day),
                  onTap: () => setState(
                    () => _collapsed.contains(day)
                        ? _collapsed.remove(day)
                        : _collapsed.add(day),
                  ),
                ),
                if (!_collapsed.contains(day))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _grid
                        ? Wrap(
                            spacing: _gap,
                            runSpacing: _gap,
                            children: [
                              for (final s in list)
                                SizedBox(width: tile, child: _tile(s)),
                            ],
                          )
                        : Column(
                            children: [
                              for (final s in list)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _tile(s, row: true),
                                ),
                            ],
                          ),
                  ),
              ],
              if (more > 0)
                Center(
                  child: PennaButton(
                    label: tr('显示更多(还有 {0} 张)', [more]),
                    icon: Icons.expand_more,
                    borderColor: PennaColors.border,
                    onPressed: () => setState(() => _limit += _page),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(ComfyShot s, {bool row = false}) => _Tile(
    shot: s,
    row: row,
    busy: s == _opening,
    url: runner.client.viewUrl(s.file, preview: true),
    headers: runner.client.headers,
    onTap: () => _open(s),
    onMenu: (at) => _menu(s, at),
  );
}

String _two(int n) => '$n'.padLeft(2, '0');

/// 分组用的日子:`2026-11-08`;没有时刻的是空串。
String dayKey(DateTime? t) =>
    t == null ? '' : '${t.year}-${_two(t.month)}-${_two(t.day)}';

/// 组标题:今天、昨天,别的写日期。
String dayLabel(String key) {
  if (key.isEmpty) return tr('更早');
  final now = DateTime.now();
  if (key == dayKey(now)) return tr('今天');
  if (key == dayKey(now.subtract(const Duration(days: 1)))) return tr('昨天');
  return key;
}

/// 一天的标题行:箭头、日子、张数,点了收起或展开。
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: Motion.of(context, Motion.snap),
            curve: Motion.swift,
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: PennaColors.slate500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            tr('{0} 张', [count]),
            style: TextStyle(fontSize: 11, color: PennaColors.slate400),
          ),
        ],
      ),
    ),
  );
}

/// 一张图:方形缩略图,下面是时刻和提示词开头;悬停看整条提示词。
class _Tile extends StatelessWidget {
  const _Tile({
    required this.shot,
    required this.url,
    required this.headers,
    required this.onTap,
    required this.onMenu,
    this.row = false,
    this.busy = false,
  });

  /// 正在读原图(点开大图之前)。
  final bool busy;

  /// 列表里的一行:左边小缩略图,右边时刻和整条提示词。
  final bool row;
  final ComfyShot shot;
  final String url;
  final Map<String, String> headers;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final time = shot.time;
    return Tooltip(
      message: shot.prompt.isEmpty ? '${shot.file['filename']}' : shot.prompt,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapUp: (d) => onMenu(d.globalPosition),
          child: row
              ? _row()
              : PennaCard(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(aspectRatio: 1, child: _image(400)),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (time != null) shortTime(time),
                          if (shot.prompt.isNotEmpty) shot.prompt,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: PennaColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// 缩略图:硬盘上的直接读文件(ComfyUI 没开也看得到),别的让 ComfyUI 压成 WebP 再给。
  Widget _image(int cacheWidth) {
    Widget broken(BuildContext _, Object _, StackTrace? _) =>
        Icon(Icons.broken_image_outlined, color: PennaColors.slate400);
    final path = shot.path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (path != null)
            Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: broken,
            )
          else
            Image.network(
              url,
              headers: headers,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: broken,
            ),
          if (busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row() {
    final time = shot.time;
    return PennaCard(
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 64, child: _image(160)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (time != null)
                  Text(
                    shortTime(time),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                const SizedBox(height: 2),
                Text(
                  shot.prompt.isEmpty
                      ? '${shot.file['filename']}'
                      : shot.prompt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: PennaColors.slate700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
