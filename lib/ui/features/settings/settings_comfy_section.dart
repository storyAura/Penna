import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/comfyui.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../studio/comfy_runner.dart';
import 'settings_agent_sections.dart';
import 'settings_sections.dart';

/// ComfyUI:出图的后端(几台,本机或云端)、导入的工作流、图存在哪。
class ComfySection extends StatefulWidget {
  const ComfySection({super.key, required this.service, required this.runner});

  final ConfigService service;
  final ComfyRunner runner;

  @override
  State<ComfySection> createState() => _ComfySectionState();
}

class _ComfySectionState extends State<ComfySection> {
  bool _busy = false;

  ConfigService get _service => widget.service;
  ComfySettings get _comfy => _service.config.comfy;

  void _put(ComfySettings next) =>
      _service.update(_service.config.copyWith(comfy: next));

  void _addServer() => _put(
    _comfy.putServer((
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: tr('云端'),
      url: '',
    )),
  );

  Future<void> _import() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (picked == null) return;
    try {
      final text = await picked.readAsString();
      parseApiWorkflow(text);
      final id = '${DateTime.now().microsecondsSinceEpoch}';
      final name = picked.name.replaceAll(RegExp(r'\.json$'), '');
      // 导进来就换成它。
      _put(
        _comfy.putFlow((id: id, name: name, text: text)).copyWith(flowId: id),
      );
    } on ComfyException catch (e) {
      if (mounted) showToast(context, e.message, warn: true);
    } on Exception {
      // 读不了,或不是 UTF-8 的文字。
      if (mounted) {
        showToast(context, tr('读不了「{0}」', [picked.name]), warn: true);
      }
    }
  }

  /// 从随 Penna 带的标准工作流里挑一个加进列表(菜单在 [button] 下面),加了就换成它。
  Future<void> _addStandard(BuildContext button) async {
    final box = button.findRenderObject()! as RenderBox;
    final picked = await popMenu(
      context,
      box.localToGlobal(Offset(0, box.size.height)),
      [for (final (name, _) in standardWorkflows) name],
    );
    final asset = standardWorkflows.where((f) => f.$1 == picked).firstOrNull;
    if (asset == null) return;
    final text = await rootBundle.loadString(asset.$2);
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    _put(
      _comfy.putFlow((id: id, name: asset.$1, text: text)).copyWith(flowId: id),
    );
  }

  Future<void> _removeFlow(ComfyFlow flow) async {
    if (await confirmDelete(
      context,
      tr('删除「{0}」?', [flow.name]),
      tr('此操作不可撤销。'),
    )) {
      _put(_comfy.removeFlow(flow.id));
    }
  }

  Future<void> _rename(ComfyFlow flow) async {
    final name = await askName(context, tr('改名'), flow.name);
    if (name == null || name.trim().isEmpty) return;
    _put(_comfy.putFlow((id: flow.id, name: name.trim(), text: flow.text)));
  }

  /// 复制一份放在它下面(LoRA 配置、要上传的素材跟着复制)。
  void _copy(ComfyFlow flow) => _put(
    _comfy.copyFlow(
      flow.id,
      newId: '${DateTime.now().microsecondsSinceEpoch}',
      name: tr('{0} 副本', [tr(flow.name)]),
    ),
  );

  /// 右键一个工作流:改名、复制、导出、删除。
  Future<void> _flowMenu(ComfyFlow flow, Offset at) async {
    final picked = await popMenu(context, at, [
      tr('改名'),
      tr('复制'),
      tr('导出'),
      tr('删除'),
    ]);
    if (!mounted || picked == null) return;
    if (picked == tr('删除')) return _removeFlow(flow);
    if (picked == tr('改名')) return _rename(flow);
    if (picked == tr('复制')) return _copy(flow);
    final file = await getSaveLocation(
      suggestedName:
          '${flow.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.json',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    try {
      await File(file.path).writeAsString(flow.text);
      if (mounted) showToast(context, tr('已导出'));
    } on FileSystemException {
      if (mounted) showToast(context, tr('写不进这个位置'), warn: true);
    }
  }

  Future<void> _moveImages() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    setState(() => _busy = true);
    try {
      final moved = await widget.runner.moveTo(dir);
      if (mounted) showToast(context, tr('已换位置,搬过去 {0} 张图', [moved]));
    } on FileSystemException catch (e) {
      if (mounted) {
        showToast(context, tr('没搬完:{0}', [e.message]), warn: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openFolder() {
    final dir = widget.runner.imageDir;
    Directory(dir).createSync(recursive: true);
    Process.run(Platform.isWindows ? 'explorer' : 'xdg-open', [dir]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('ComfyUI', tr('出图的后端')),
        for (final server in _comfy.servers) ...[
          _ServerCard(
            key: ValueKey(server.id),
            service: _service,
            runner: widget.runner,
            server: server,
          ),
          gap,
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: PennaButton(
            label: tr('添加 ComfyUI'),
            icon: Icons.add,
            borderColor: PennaColors.border,
            onPressed: _addServer,
          ),
        ),
        gap,
        // Agent 写了出图标签时:直接出,还是在回复下面放一个「出图」等用户点。
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(child: Text(tr('Agent 出图'), style: titleStyle)),
              for (final (auto, label) in [
                (true, tr('直接出图')),
                (false, tr('手动确认')),
              ]) ...[
                const SizedBox(width: 6),
                PennaChip(
                  label: label,
                  selected: _comfy.autoGenerate == auto,
                  onTap: () => _put(_comfy.copyWith(autoGenerate: auto)),
                ),
              ],
            ],
          ),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Agent 出图的画面方向'), style: titleStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (mode, label) in [
                    (orientationKeep, tr('照工作流的大小')),
                    (orientationAuto, tr('让 Agent 决定')),
                    (orientationLandscape, tr('只出横图')),
                    (orientationPortrait, tr('只出竖图')),
                  ])
                    PennaChip(
                      label: label,
                      selected: _comfy.orientation == mode,
                      onTap: () => _put(_comfy.copyWith(orientation: mode)),
                    ),
                ],
              ),
            ],
          ),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('系列连续出图'), style: titleStyle),
                    Text(tr('Agent 一次写了几页时按顺序全部出图'), style: hintStyle),
                  ],
                ),
              ),
              Switch(
                value: _service.config.seriesGenerate,
                onChanged: (v) => _service.update(
                  _service.config.copyWith(seriesGenerate: v),
                ),
              ),
            ],
          ),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('工作流'), style: titleStyle)),
                  Builder(
                    builder: (button) => PennaButton(
                      label: tr('内置工作流'),
                      icon: Icons.inventory_2_outlined,
                      borderColor: PennaColors.border,
                      onPressed: () => _addStandard(button),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PennaButton(
                    label: tr('导入工作流'),
                    icon: Icons.file_open_outlined,
                    tooltip: tr('ComfyUI 保存或「导出 (API)」的 JSON'),
                    borderColor: PennaColors.border,
                    onPressed: _import,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_comfy.flows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(tr('还没导入,出图用内置文生图'), style: hintStyle),
                ),
              // 按住左边的把手拖着换顺序(侧栏下拉里的先后跟着变)。
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _comfy.flows.length,
                onReorderItem: (from, to) => _put(_comfy.moveFlow(from, to)),
                itemBuilder: (context, i) {
                  final flow = _comfy.flows[i];
                  return _FlowRow(
                    key: ValueKey(flow.id),
                    index: i,
                    name: tr(flow.name),
                    selected: _comfy.flow?.id == flow.id,
                    onSelect: () => _put(_comfy.copyWith(flowId: flow.id)),
                    onRename: () => _rename(flow),
                    onCopy: () => _copy(flow),
                    onRemove: () => _removeFlow(flow),
                    onMenu: (at) => _flowMenu(flow, at),
                  );
                },
              ),
            ],
          ),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('图片位置'), style: titleStyle),
                    Text(widget.runner.imageDir, style: hintStyle),
                  ],
                ),
              ),
              PennaButton(
                label: tr('打开'),
                icon: Icons.folder_open_outlined,
                borderColor: PennaColors.border,
                onPressed: _openFolder,
              ),
              const SizedBox(width: 6),
              PennaButton(
                label: tr('更换位置'),
                icon: Icons.drive_file_move_outlined,
                tooltip: tr('已有的图一起搬过去'),
                borderColor: PennaColors.border,
                onPressed: _busy ? null : _moveImages,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 工作流列表里的一行:拖动把手、点了用它、改名、复制、删除;右键是 [onMenu](给窗口坐标)。
class _FlowRow extends StatelessWidget {
  const _FlowRow({
    super.key,
    required this.index,
    required this.name,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onCopy,
    required this.onRemove,
    required this.onMenu,
  });

  final int index;
  final String name;
  final bool selected;
  final VoidCallback onSelect, onRename, onCopy, onRemove;
  final ValueChanged<Offset> onMenu;

  Widget _action(String tip, IconData icon, VoidCallback onTap) => IconButton(
    tooltip: tip,
    iconSize: 16,
    visualDensity: VisualDensity.compact,
    color: PennaColors.slate400,
    icon: Icon(icon),
    onPressed: onTap,
  );

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onSelect,
    onSecondaryTapUp: (d) => onMenu(d.globalPosition),
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: PennaColors.slate400,
                ),
              ),
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 16,
            color: selected ? PennaColors.primary : PennaColors.slate400,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          _action(tr('改名'), Icons.edit_outlined, onRename),
          _action(tr('复制'), Icons.copy_outlined, onCopy),
          _action(tr('删除'), Icons.delete_outline, onRemove),
        ],
      ),
    ),
  );
}

/// 一台 ComfyUI:名称、地址、Key,测试连接(显示延迟),设为当前、删除。
class _ServerCard extends StatefulWidget {
  const _ServerCard({
    super.key,
    required this.service,
    required this.runner,
    required this.server,
  });

  final ConfigService service;
  final ComfyRunner runner;
  final ComfyServer server;

  @override
  State<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<_ServerCard> {
  bool _testing = false;
  String? _result;
  bool _failed = false;

  ConfigService get _service => widget.service;
  ComfyServer get _server => widget.server;
  ComfySettings get _comfy => _service.config.comfy;

  void _put(ComfyServer next) =>
      _service.update(_service.config.copyWith(comfy: _comfy.putServer(next)));

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    String result;
    var failed = false;
    try {
      final p = await ComfyClient(
        _server.url,
        key: _service.config.secrets[comfyKeyName(_server.id)] ?? '',
      ).ping();
      result = tr('已连接 · ComfyUI {0} · {1} ms', [p.version, p.ms]);
      // 侧栏跟着刷新:地址、Key 可能刚改过。
      if (_comfy.serverId == _server.id) {
        unawaited(widget.runner.check(full: true));
      }
    } on ComfyException catch (e) {
      result = e.message;
      failed = true;
    } on Object catch (e) {
      result = tr('连接失败({0})', [e.runtimeType]);
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = result;
      _failed = failed;
    });
  }

  Future<void> _delete() async {
    if (await confirmDelete(
      context,
      tr('删除「{0}」?', [_server.name]),
      tr('此操作不可撤销。'),
    )) {
      _service.update(
        _service.config.copyWith(comfy: _comfy.removeServer(_server.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _comfy.serverId == _server.id;
    return PennaCard(
      borderColor: current ? PennaColors.primaryBorder : PennaColors.border,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: PennaField(
                  label: tr('名称'),
                  value: tr(_server.name),
                  onChanged: (v) =>
                      _put((id: _server.id, name: v, url: _server.url)),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: current
                    ? PennaChip(label: tr('当前'), selected: true, onTap: () {})
                    : PennaChip(
                        label: tr('设为当前'),
                        selected: false,
                        onTap: () => widget.runner.selectServer(_server.id),
                      ),
              ),
              if (_comfy.servers.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: IconButton(
                    tooltip: tr('删除'),
                    iconSize: 18,
                    icon: const Icon(Icons.delete_outline),
                    color: PennaColors.slate500,
                    onPressed: _delete,
                  ),
                ),
            ],
          ),
          gap,
          PennaField(
            label: tr('地址'),
            hint: comfyDefaultUrl,
            value: _server.url,
            onChanged: (v) =>
                _put((id: _server.id, name: _server.name, url: v.trim())),
          ),
          gap,
          PennaField(
            label: 'Key',
            hint: tr('云端需要时填写'),
            obscure: true,
            value: _service.config.secrets[comfyKeyName(_server.id)] ?? '',
            onChanged: (v) => _service.update(
              _service.config.setSecret(comfyKeyName(_server.id), v),
            ),
          ),
          gap,
          Row(
            children: [
              PennaButton(
                label: tr('测试连接'),
                icon: Icons.sync_alt,
                background: PennaColors.slate100,
                onPressed: _testing ? null : _test,
              ),
              const SizedBox(width: 10),
              if (_result != null)
                Expanded(
                  child: Text(
                    _result!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: _failed
                          ? PennaColors.diffDelText
                          : PennaColors.accent,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
