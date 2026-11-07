import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart' show confirmDelete;
import 'pose_library.dart';

/// 分类的名字(按 id 翻译;认不出的照原样)。
String poseCategory(String id) => switch (id) {
  'standing' => tr('站姿'),
  'sitting' => tr('坐姿'),
  'kneel_squat' => tr('跪姿 / 蹲姿'),
  'lying' => tr('卧姿'),
  'inverted_acrobatic' => tr('倒立 / 高难度'),
  'duo_mixed_level' => tr('双人高低组合'),
  'upper_body_gesture' => tr('半身手势'),
  _ => id,
};

String poseAngle(String angle) => switch (angle) {
  'front' => tr('正面'),
  'diag' => tr('斜侧'),
  'side' => tr('侧面'),
  'above' => tr('俯视'),
  'below' => tr('仰视'),
  _ => angle,
};

/// 「站姿 001」:分类名 + id 末尾的编号。
String poseName(Pose p) =>
    '${poseCategory(p.category)} ${p.id.split('-').last}';

/// 交给 Agent 的那句话(发给模型的,不翻译)。
const _angleZh = {
  'front': '正面',
  'diag': '斜侧',
  'side': '侧面',
  'above': '俯视',
  'below': '仰视',
};

/// 姿势图库:无脸人偶的线稿,按分类看,点开换视角、附到对话里给 Agent 参考。
class PosesPage extends StatefulWidget {
  const PosesPage({super.key, required this.library, required this.onSend});

  final PoseLibrary library;

  /// 把一张姿势图和一句说明交给工作台的对话。
  final void Function(Attachment image, String text) onSend;

  @override
  State<PosesPage> createState() => _PosesPageState();
}

class _PosesPageState extends State<PosesPage> {
  /// 选中的分类;null 是全部。
  String? _category;

  /// 显示作者标出的性感系列(默认藏起来)。
  bool _suggestive = false;

  /// 从哪下载。
  PoseSource _source = PoseSource.githubAccel;

  PoseLibrary get lib => widget.library;

  Future<void> _import() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: 'ZIP', extensions: const ['zip']),
      ],
    );
    if (picked == null) return;
    _report(await lib.importZip(picked.path));
  }

  Future<void> _download() async => _report(await lib.download(_source));

  void _report(String? problem) {
    if (!mounted) return;
    showToast(
      context,
      problem ?? tr('已装好 · {0} 个姿势', [lib.poses.length]),
      warn: problem != null,
    );
  }

  Future<void> _remove() async {
    if (await confirmDelete(context, tr('删除姿势图库?'), tr('要用时再下载或导入。'))) {
      await lib.remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) => ColoredBox(
        color: PennaColors.bg,
        child: Column(
          children: [
            PennaBar(
              color: PennaColors.card,
              children: [
                Icon(
                  Icons.accessibility_new,
                  size: 15,
                  color: PennaColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  tr('姿势图库'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (lib.installed) ...[
                  PennaButton(
                    label: tr('重新导入'),
                    icon: Icons.file_open_outlined,
                    borderColor: PennaColors.border,
                    onPressed: lib.busy ? null : _import,
                  ),
                  const SizedBox(width: 6),
                  PennaButton(
                    label: '',
                    icon: Icons.delete_outline,
                    tooltip: tr('删除图集'),
                    borderColor: PennaColors.border,
                    onPressed: lib.busy ? null : _remove,
                  ),
                ],
              ],
            ),
            Expanded(child: lib.installed ? _gallery() : _empty()),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.accessibility_new, size: 40, color: PennaColors.slate400),
        const SizedBox(height: 12),
        Text(
          tr('姿势图库'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          tr('无脸人偶线稿 · 7 类 · 5 个视角'),
          style: TextStyle(fontSize: 12, color: PennaColors.slate500),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          children: [
            for (final (s, label) in [
              (PoseSource.githubAccel, tr('GitHub 加速')),
              (PoseSource.github, 'GitHub'),
              (PoseSource.modelscope, tr('魔搭 · 不含 NSFW')),
            ])
              PennaChip(
                label: label,
                selected: _source == s,
                onTap: lib.busy ? null : () => setState(() => _source = s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (lib.busy)
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(value: lib.progress),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PennaButton(
                label: tr('下载'),
                icon: Icons.download_outlined,
                background: PennaColors.primary,
                foreground: Colors.white,
                onPressed: _download,
              ),
              const SizedBox(width: 8),
              PennaButton(
                label: tr('导入 ZIP'),
                icon: Icons.file_open_outlined,
                borderColor: PennaColors.border,
                onPressed: _import,
              ),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          'Shisei · CC0 1.0',
          style: TextStyle(fontSize: 11, color: PennaColors.slate400),
        ),
      ],
    ),
  );

  Widget _gallery() {
    final categories = {for (final p in lib.poses) p.category}.toList();
    final shown = [
      for (final p in lib.poses)
        if ((_suggestive || !isSuggestive(p)) &&
            (_category == null || p.category == _category))
          p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PennaChip(
                label: tr('全部'),
                selected: _category == null,
                onTap: () => setState(() => _category = null),
              ),
              for (final c in categories)
                PennaChip(
                  label: poseCategory(c),
                  selected: _category == c,
                  onTap: () => setState(() => _category = c),
                ),
              const SizedBox(width: 12),
              PennaChip(
                label: tr('性感系列'),
                selected: _suggestive,
                onTap: () => setState(() => _suggestive = !_suggestive),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) =>
                _PoseTile(pose: shown[i], onTap: () => _open(shown[i])),
          ),
        ),
      ],
    );
  }

  void _open(Pose pose) => showDialog<void>(
    context: context,
    builder: (_) => _PoseDialog(pose: pose, onSend: widget.onSend),
  );
}

class _PoseTile extends StatelessWidget {
  const _PoseTile({required this.pose, required this.onTap});

  final Pose pose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Bouncy(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: PennaColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PennaColors.border),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Expanded(child: _PoseImage(pose.views.first.path, width: 320)),
                const SizedBox(height: 4),
                Text(
                  poseName(pose),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: PennaColors.slate700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 线稿是白底黑线:放在白底上,深色模式里也看得清。
class _PoseImage extends StatelessWidget {
  const _PoseImage(this.path, {super.key, required this.width});

  final String path;
  final int width;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: Image.file(
          File(path),
          cacheWidth: width,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Icon(Icons.broken_image_outlined, color: PennaColors.slate400),
        ),
      ),
    ),
  );
}

/// 点开一个姿势:换视角,附到对话里。
class _PoseDialog extends StatefulWidget {
  const _PoseDialog({required this.pose, required this.onSend});

  final Pose pose;
  final void Function(Attachment image, String text) onSend;

  @override
  State<_PoseDialog> createState() => _PoseDialogState();
}

class _PoseDialogState extends State<_PoseDialog> {
  late PoseView _view = widget.pose.views.first;

  void _send() {
    final Attachment image;
    try {
      image = Attachment.image(
        name: '${widget.pose.id}_${_view.angle}.webp',
        mime: 'image/webp',
        bytes: File(_view.path).readAsBytesSync(),
      );
    } on FileSystemException {
      showToast(context, tr('读不了这张图'), warn: true);
      return;
    }
    Navigator.pop(context);
    widget.onSend(
      image,
      '姿势参考图(${_angleZh[_view.angle] ?? _view.angle}):'
      '只参考人物的体态和肢体朝向,不照搬图里人偶的样子。',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PennaColors.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                poseName(widget.pose),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in widget.pose.views)
                    PennaChip(
                      label: poseAngle(v.angle),
                      selected: v == _view,
                      onTap: () => setState(() => _view = v),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.snap),
                    child: _PoseImage(
                      _view.path,
                      key: ValueKey(_view.path),
                      width: 1000,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  PennaButton(
                    label: tr('关闭'),
                    borderColor: PennaColors.border,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  PennaButton(
                    label: tr('附到对话'),
                    icon: Icons.attach_file,
                    background: PennaColors.primary,
                    foreground: Colors.white,
                    onPressed: _send,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
