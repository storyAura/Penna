import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/local/caption_catalog.dart';
import '../../../core/harness/local/download.dart';
import '../../../core/harness/local/florence.dart';
import '../../../core/harness/local/model_scan.dart';
import '../../../core/harness/local/tagger.dart';
import '../../../core/harness/providers/llm_http.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/image_drop.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../studio/studio_view_model.dart';
import 'local_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'local_llm_tab.dart';
part 'local_nl_tab.dart';
part 'local_tag_tab.dart';

/// 本地反推:左边放一张图,右边给它反推。
/// 「Tag 反推」用 ONNX 打标模型出 Danbooru 标签,「NL 反推」用本机的看图模型写描述,
/// 「LLM 反推」用「API 管理」里的模型(可以同时两个)写提示词。
class LocalPage extends StatefulWidget {
  const LocalPage({
    super.key,
    required this.model,
    required this.config,
    required this.vm,
    required this.onOpenStudio,
    required this.onSendToAgent,
  });

  final LocalModel model;
  final ConfigService config;
  final StudioViewModel vm;

  /// 放到成稿后切去工作台。
  final VoidCallback onOpenStudio;

  /// 把结果交给 Agent:填进工作台的聊天输入框。
  final ValueChanged<String> onSendToAgent;

  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage> {
  int _tab = 0;
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  tr('本地反推'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 16),
                for (final (i, label) in [
                  tr('Tag 反推'),
                  tr('NL 反推'),
                  tr('LLM 反推'),
                ].indexed) ...[
                  PennaChip(
                    label: label,
                    selected: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: ImageDrop(
                      image: model.image,
                      onChanged: model.setImage,
                      hint: tr('点击或拖入要反推的图片'),
                      compress: widget.config.config.compressImages,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: PopIn(
                        key: ValueKey(_tab),
                        child: switch (_tab) {
                          0 => _TagTab(
                            model: model,
                            onToDraft: (text) => _toDraft(context, text),
                            onSend: widget.onSendToAgent,
                          ),
                          1 => _NlTab(
                            model: model,
                            config: widget.config,
                            onToDraft: (text) => _toDraft(context, text),
                            onSend: widget.onSendToAgent,
                          ),
                          _ => _LlmTab(
                            model: model,
                            config: widget.config,
                            vm: widget.vm,
                            onToDraft: (text) => _toDraft(context, text),
                            onSend: widget.onSendToAgent,
                          ),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 结果放进当前页的成稿:成稿空着直接填,有内容时是待确认的改动。
  void _toDraft(BuildContext context, String text) {
    final problem = widget.vm.restorePrompt((
      time: DateTime.now(),
      text: text,
    ), title: tr('本地反推'));
    if (problem != null) return showToast(context, problem, warn: true);
    widget.onOpenStudio();
  }
}

/// 一块带标题的卡片。
class _Block extends StatelessWidget {
  const _Block({required this.title, this.trailing, required this.child});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PennaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: titleStyle)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 「模型」那一栏右上角:加一个放着已有模型的文件夹,扫完说一声找到了什么。
class _AddFolder extends StatelessWidget {
  const _AddFolder({required this.model});

  final LocalModel model;

  Future<void> _add(BuildContext context) async {
    final path = await getDirectoryPath();
    if (path == null) return;
    await model.addFolder(path);
    if (context.mounted) showToast(context, model.foundSummary);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tr('添加已有模型的文件夹'),
    iconSize: 16,
    visualDensity: VisualDensity.compact,
    color: PennaColors.slate500,
    icon: const Icon(Icons.create_new_folder_outlined),
    onPressed: model.scanning ? null : () => _add(context),
  );
}

/// 一行可下载的东西:名字、说明,右边是下载 / 进度 / 删除。
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.model,
    required this.keyName,
    required this.name,
    required this.note,
    required this.files,
    required this.onDownload,
    this.selected = false,
    this.onSelect,
    this.done,
    this.foundAt,
    this.below,
    this.onRemove,
  });

  /// 说明下面再放的东西,比如量化档。
  final Widget? below;

  /// 删除下载好的文件;不给就删 [files]。
  final Future<String?> Function()? onRemove;

  final LocalModel model;

  /// 在模型文件夹里找到时是它所在的位置:直接能用,不显示下载,也不给删(那是别的程序的文件)。
  final String? foundAt;

  /// 下好了没有;不给就看 [files] 在不在。
  final bool? done;

  /// 进度记在哪个名字下。
  final String keyName;
  final String name;
  final String note;
  final List<RemoteFile> files;
  final Future<String?> Function() onDownload;
  final bool selected;

  /// 点这一行选中它;为 null 时这一行不能选。
  final VoidCallback? onSelect;

  Future<void> _download(BuildContext context) async {
    final problem = await onDownload();
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  Future<void> _remove(BuildContext context) async {
    if (!await confirmDelete(
      context,
      tr('删除「{0}」?', [name]),
      tr('下载好的文件会从本机删掉。'),
    )) {
      return;
    }
    final problem = await (onRemove ?? () => model.remove(files))();
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = model.progressOf(keyName);
    final ready = done ?? model.ready(files);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: Motion.snap,
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? PennaColors.primaryBg : PennaColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? PennaColors.primaryBorder : PennaColors.border,
          ),
        ),
        child: Row(
          children: [
            if (onSelect != null) ...[
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: selected ? PennaColors.primary : PennaColors.slate400,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Tooltip(
                    message: note,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
                  if (below case final extra?) ...[
                    const SizedBox(height: 4),
                    extra,
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress.total == null
                          ? null
                          : progress.received / progress.total!,
                      minHeight: 3,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progress.total == null
                          ? _size(progress.received)
                          : '${_size(progress.received)} / '
                                '${_size(progress.total!)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (progress == null && foundAt != null)
              Tooltip(message: foundAt!, child: _Badge(tr('本机')))
            else if (progress != null)
              PennaButton(
                label: tr('停止'),
                icon: Icons.stop_circle_outlined,
                background: PennaColors.slate100,
                onPressed: () => model.cancelDownload(keyName),
              )
            else if (ready)
              IconButton(
                tooltip: tr('删除'),
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate500,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(context),
              )
            else
              PennaButton(
                label: tr('下载'),
                icon: Icons.download,
                background: PennaColors.primaryBg,
                foreground: PennaColors.primary,
                onPressed: model.dir == null ? null : () => _download(context),
              ),
          ],
        ),
      ),
    );
  }
}

/// 模型列表最多这么高,再多就在框里滚动。
const _listMaxHeight = 360.0;

/// 列表里的一组:系列名,和组里各行的 id(拖动时靠它认行)与行本身。
typedef _Group = ({String series, List<String> ids, List<Widget> rows});

/// 按系列分组的模型列表:点系列名展开、收起;按住左边的把手上下拖动,
/// 系列那一行拖的是整组,模型那一行只在组里挪。
class _GroupedModelList extends StatefulWidget {
  const _GroupedModelList({
    required this.groups,
    required this.onMove,
    required this.current,
  });

  final List<_Group> groups;
  final void Function(int? group, int from, int to) onMove;

  /// 选中的模型所在的系列:一开始展开它,系列名标成蓝色。
  final String current;

  @override
  State<_GroupedModelList> createState() => _GroupedModelListState();
}

class _GroupedModelListState extends State<_GroupedModelList> {
  late final _open = {widget.current};

  Widget _handle(int index, {double top = 0}) => ReorderableDragStartListener(
    index: index,
    child: MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, top, 4, 0),
        child: Icon(
          Icons.drag_indicator,
          size: 16,
          color: PennaColors.slate400,
        ),
      ),
    ),
  );

  Widget _header(int index, _Group g) {
    final open = _open.contains(g.series);
    final current = g.series == widget.current;
    return InkWell(
      onTap: () =>
          setState(() => open ? _open.remove(g.series) : _open.add(g.series)),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _handle(index),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: Motion.base,
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: PennaColors.slate500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              tr(g.series), // 「本机」要翻译,WD14 这类查不到就原样
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: current ? PennaColors.primary : PennaColors.text,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${g.rows.length}',
              style: TextStyle(fontSize: 11, color: PennaColors.slate400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rows(int index, _Group g) => ReorderableListView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    onReorderItem: (from, to) => widget.onMove(index, from, to),
    proxyDecorator: (child, _, _) =>
        Material(color: Colors.transparent, child: child),
    children: [
      for (final (i, row) in g.rows.indexed)
        Padding(
          key: ValueKey(g.ids[i]),
          padding: const EdgeInsets.only(left: 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _handle(i, top: 14),
              Expanded(child: row),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _listMaxHeight),
      child: ReorderableListView(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) => widget.onMove(null, from, to),
        proxyDecorator: (child, _, _) =>
            Material(color: Colors.transparent, child: child),
        children: [
          for (final (i, g) in widget.groups.indexed)
            Column(
              key: ValueKey('series:${g.series}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(i, g),
                if (_open.contains(g.series)) _rows(i, g),
              ],
            ),
        ],
      ),
    );
  }
}

/// 一个小标签,比如「本机」。
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: PennaColors.diffAdd,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: PennaColors.diffAddText),
      ),
    );
  }
}

String _size(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
    : '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

/// 结果下面那排:复制、发送给 Agent、放到成稿。
class _ResultActions extends StatelessWidget {
  const _ResultActions({
    required this.text,
    required this.onToDraft,
    required this.onSend,
  });

  final String text;
  final ValueChanged<String> onToDraft;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    // 放不下时折到下一行:LLM 反推两份结果并排时一份只有半宽。
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
        PennaButton(
          label: tr('复制'),
          icon: Icons.content_copy,
          borderColor: PennaColors.border,
          onPressed: () => copyWithToast(context, text, tr('已复制')),
        ),
        PennaButton(
          label: tr('发送给 Agent'),
          icon: Icons.send_outlined,
          borderColor: PennaColors.border,
          onPressed: () => onSend(text),
        ),
        PennaButton(
          label: tr('放到成稿'),
          icon: Icons.keyboard_double_arrow_up,
          background: PennaColors.accent,
          foreground: Colors.white,
          onPressed: () => onToDraft(text),
        ),
      ],
    );
  }
}

/// 点按钮跑一件事,出错时弹提示。
Future<void> _run(BuildContext context, Future<String?> Function() task) async {
  final problem = await task();
  if (problem != null && context.mounted) {
    showToast(context, problem, warn: true);
  }
}
