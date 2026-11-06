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

/// ComfyUI:出图的后端(本机或云端)、用哪个工作流、图存在哪。
class ComfySection extends StatefulWidget {
  const ComfySection({super.key, required this.service, required this.runner});

  final ConfigService service;
  final ComfyRunner runner;

  @override
  State<ComfySection> createState() => _ComfySectionState();
}

class _ComfySectionState extends State<ComfySection> {
  bool _busy = false;

  /// 最近一次测试的结果;[_failed] 决定它用什么颜色显示。
  String? _result;
  bool _failed = false;

  ConfigService get _service => widget.service;
  ComfySettings get _comfy => _service.config.comfy;

  void _put(ComfySettings next) =>
      _service.update(_service.config.copyWith(comfy: next));

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    String result;
    var failed = false;
    try {
      final client = ComfyClient(
        _comfy.url,
        key: _service.config.secrets[comfyKeyName] ?? '',
      );
      final p = await client.ping();
      result = tr('已连接 · ComfyUI {0} · {1} ms', [p.version, p.ms]);
      // 侧栏跟着刷新:地址、Key 可能刚改过。
      unawaited(widget.runner.check(full: true));
    } on ComfyException catch (e) {
      result = e.message;
      failed = true;
    } on Object catch (e) {
      result = tr('连接失败({0})', [e.runtimeType]);
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      _failed = failed;
    });
  }

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
      final name = picked.name.replaceAll(RegExp(r'\.json$'), '');
      _put(_comfy.copyWith(workflow: text, workflowName: name));
    } on ComfyException catch (e) {
      if (mounted) showToast(context, e.message, warn: true);
    } on Exception {
      // 读不了,或不是 UTF-8 的文字。
      if (mounted) {
        showToast(context, tr('读不了「{0}」', [picked.name]), warn: true);
      }
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
    final imported = _comfy.workflow.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('ComfyUI', tr('出图的后端')),
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PennaField(
                label: tr('地址'),
                hint: comfyDefaultUrl,
                value: _comfy.url,
                onChanged: (v) => _put(
                  _comfy.copyWith(url: v.trim().isEmpty ? comfyDefaultUrl : v),
                ),
              ),
              gap,
              PennaField(
                label: 'Key',
                hint: tr('云端需要时填写'),
                obscure: true,
                value: _service.config.secrets[comfyKeyName] ?? '',
                onChanged: (v) =>
                    _service.update(_service.config.setSecret(comfyKeyName, v)),
              ),
              gap,
              Row(
                children: [
                  PennaButton(
                    label: tr('测试连接'),
                    icon: Icons.sync_alt,
                    background: PennaColors.slate100,
                    onPressed: _busy ? null : _test,
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
                    Text(tr('工作流'), style: titleStyle),
                    Text(
                      imported ? _comfy.workflowName : tr('内置 · 文生图'),
                      style: hintStyle,
                    ),
                  ],
                ),
              ),
              if (imported)
                PennaButton(
                  label: tr('用内置'),
                  icon: Icons.restart_alt,
                  borderColor: PennaColors.border,
                  onPressed: () =>
                      _put(_comfy.copyWith(workflow: '', workflowName: '')),
                ),
              const SizedBox(width: 6),
              PennaButton(
                label: tr('导入 (API)'),
                icon: Icons.file_open_outlined,
                tooltip: tr('ComfyUI 里「导出 (API)」的 JSON'),
                borderColor: PennaColors.border,
                onPressed: _import,
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
