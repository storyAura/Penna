import 'dart:async';

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

/// 档案库的「图片」分区:直接读 ComfyUI 出过的图(`/history`),在 ComfyUI 里跑的也算。
/// 点开看原图;右键复制图片、复制当时的提示词、放回成稿。
// ponytail: ComfyUI 重启后它的历史就清空了,这里也跟着没了(Penna 出的图另存在图片位置里);
// 要长期留着就把读到的记进本地。
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

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    _seen = runner.images.length;
    List<ComfyShot>? shots;
    String? error;
    try {
      shots = await runner.client.history(max: _maxRuns);
    } on ComfyException catch (e) {
      error = e.message;
    } on Object catch (e) {
      error = tr('读取失败({0})', [e.runtimeType]);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _shots = shots ?? _shots;
      _error = error;
    });
  }

  /// 下载原图,当成图片附件(看大图、复制都用它)。
  Future<Attachment?> _full(ComfyShot shot) async {
    try {
      final bytes = await runner.client.download(shot.file);
      final name = '${shot.file['filename']}';
      final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
      return Attachment.image(
        name: name,
        mime: imageMimes[ext] ?? 'image/png',
        bytes: bytes,
      );
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
    final image = await _full(shot);
    if (image != null && mounted) await showImageViewer(context, image);
  }

  Future<void> _menu(ComfyShot shot, Offset at) async {
    final copyPicture = tr('复制图片'),
        copyPrompt = tr('复制提示词'),
        restore = tr('放回成稿'),
        delete = tr('删除');
    final picked = await popMenu(context, at, [
      copyPicture,
      if (shot.prompt.isNotEmpty) ...[copyPrompt, restore],
      delete,
    ]);
    if (!mounted) return;
    if (picked == delete) return _delete(shot);
    if (picked == copyPicture) {
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

  @override
  Widget build(BuildContext context) {
    final shots = _shots;
    final note = TextStyle(fontSize: 12, color: PennaColors.slate400);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  shots == null
                      ? ''
                      : tr('{0} 张 · 读自 {1}', [
                          shots.length,
                          runner.config.config.comfy.server.url,
                        ]),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                ),
              ),
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
          child: switch ((shots, _error)) {
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

  /// 按日子分组(新的在前),每组一个能点着收起、展开的标题。
  Widget _days(List<ComfyShot> shots) {
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
            ],
          );
        },
      ),
    );
  }

  Widget _tile(ComfyShot s, {bool row = false}) => _Tile(
    shot: s,
    row: row,
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
  if (key.isEmpty) return tr('未知日期');
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
  });

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

  Widget _image(int cacheWidth) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.network(
      url,
      headers: headers,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) =>
          Icon(Icons.broken_image_outlined, color: PennaColors.slate400),
    ),
  );

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
