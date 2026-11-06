import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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

  Future<void> _removeFlow(ComfyFlow flow) async {
    if (await confirmDelete(
      context,
      tr('删除「{0}」?', [flow.name]),
      tr('此操作不可撤销。'),
    )) {
      _put(_comfy.removeFlow(flow.id));
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
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr('工作流'), style: titleStyle)),
                  PennaButton(
                    label: tr('导入 (API)'),
                    icon: Icons.file_open_outlined,
                    tooltip: tr('ComfyUI 里「导出 (API)」的 JSON'),
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
              for (final flow in _comfy.flows)
                _FlowRow(
                  name: tr(flow.name),
                  selected: _comfy.flow?.id == flow.id,
                  onSelect: () => _put(_comfy.copyWith(flowId: flow.id)),
                  onRemove: () => _removeFlow(flow),
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

/// 工作流列表里的一行:点了用它,导入的能删。
class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.name,
    required this.selected,
    required this.onSelect,
    this.onRemove,
  });

  final String name;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onSelect,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 16,
            color: selected ? PennaColors.primary : PennaColors.slate400,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
          if (onRemove != null)
            IconButton(
              tooltip: tr('删除'),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate400,
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            )
          else
            const SizedBox(height: 32),
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
