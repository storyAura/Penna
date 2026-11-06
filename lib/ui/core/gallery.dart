import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/harness/attachment.dart';
import '../../l10n/l10n.dart';
import 'theme.dart';
import 'widgets.dart';
import 'motion.dart';
import 'native_drop.dart';

// 档案库、角色库共用的零件:列表 / 大缩略图两种看法、拖着换顺序、
// 把图片拖上来当预览图(转成 WebP)。

/// 读一张图片文件,转成预览用的 WebP;不是图片、太大或读不了时提示一句,返回 null。
Future<Uint8List?> readPreview(BuildContext context, String path) async {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  String? problem;
  Uint8List? webp;
  if (!imageMimes.containsKey(ext)) {
    problem = tr('只能放图片(png、jpg、webp、gif)');
  } else {
    try {
      final file = File(path);
      if (await file.length() > maxRawImageBytes) {
        problem = tr('图片超过 {0}', [maxRawImageLabel]);
      } else {
        webp = await toPreviewWebP(await file.readAsBytes());
        if (webp == null) problem = tr('读不了这张图');
      }
    } on FileSystemException {
      problem = tr('读不了这张图');
    }
  }
  if (problem != null && context.mounted) {
    showToast(context, problem, warn: true);
  }
  return webp;
}

/// 让用户选一张图,转成预览用的 WebP;没选或读不了返回 null。
Future<Uint8List?> pickPreview(BuildContext context) async {
  final picked = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(label: tr('图片'), extensions: imageMimes.keys.toList()),
    ],
  );
  if (picked == null || !context.mounted) return null;
  return readPreview(context, picked.path);
}

/// 「列表」「大缩略图」两种看法的切换。
class ViewSwitch extends StatelessWidget {
  const ViewSwitch({super.key, required this.grid, required this.onChanged});

  final bool grid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(bool g, IconData icon, String tip) => IconButton(
      tooltip: tip,
      iconSize: 17,
      visualDensity: VisualDensity.compact,
      color: grid == g ? PennaColors.primary : PennaColors.slate400,
      icon: Icon(icon),
      onPressed: () => onChanged(g),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(false, Icons.view_agenda_outlined, tr('列表')),
        button(true, Icons.grid_view, tr('大缩略图')),
      ],
    );
  }
}

/// 预览图;路径是空的、或读不了时显示 [blank](不给就什么都不画)。
class PreviewImage extends StatelessWidget {
  const PreviewImage({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    this.blank,
  });

  final String path;
  final double width, height;
  final Widget? blank;

  @override
  Widget build(BuildContext context) {
    final empty = blank ?? const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: path.isEmpty
            ? empty
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                // 只按显示的大小解码,大图不占内存。
                cacheWidth: (width * 2).round(),
                errorBuilder: (_, _, _) => empty,
              ),
      ),
    );
  }
}

/// 档案库、角色库里的一格:按住拖到别的格子上换顺序(放到它前面),
/// 把图片文件拖上来就换成它的预览图。
class GalleryItem extends StatefulWidget {
  const GalleryItem({
    super.key,
    required this.id,
    required this.onMove,
    required this.onImage,
    required this.child,
  });

  final String id;

  /// 别的格子([dragged] 是它的 id)拖到了这一格上:放到这一格前面。
  final ValueChanged<String> onMove;

  /// 拖上来了一个文件(路径)。
  final ValueChanged<String> onImage;
  final Widget child;

  @override
  State<GalleryItem> createState() => _GalleryItemState();
}

class _GalleryItemState extends State<GalleryItem> {
  /// 有文件正悬在这一格上。
  var _fileOver = false;

  @override
  Widget build(BuildContext context) {
    return PennaDropTarget(
      onDragEntered: (_) => setState(() => _fileOver = true),
      onDragExited: (_) => setState(() => _fileOver = false),
      onDragDone: (d) {
        setState(() => _fileOver = false);
        if (d.files.isNotEmpty) widget.onImage(d.files.first.path);
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != widget.id,
        onAcceptWithDetails: (d) => widget.onMove(d.data),
        builder: (context, over, _) => LayoutBuilder(
          builder: (context, box) {
            final lit = _fileOver || over.isNotEmpty;
            return Draggable<String>(
              data: widget.id,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.85,
                  child: SizedBox(width: box.maxWidth, child: widget.child),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: widget.child),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.snap),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: lit ? PennaColors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: widget.child,
              ),
            );
          },
        ),
      ),
    );
  }
}
