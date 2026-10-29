import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/local/llama_server.dart';
import '../../../core/harness/local/model_sources.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../local/local_model.dart';
import 'settings_sections.dart';
import '../../../l10n/l10n.dart';

/// 本地反推的设置:模型文件夹、下载来源、HuggingFace Token、llama.cpp 运行时与参数、看图要求。
class LocalSection extends StatelessWidget {
  const LocalSection({super.key, required this.service, required this.local});

  final ConfigService service;
  final LocalModel local;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: local,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(tr('本地反推'), tr('模型存放、下载与本地运行')),
          _Folders(local: local),
          gap,
          _card(
            tr('下载'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(tr('模型')),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final MapEntry(key: id, value: label)
                        in modelSources.entries)
                      PennaChip(
                        label: tr(label),
                        selected: local.source == id,
                        onTap: () => local.update(() => local.source = id),
                      ),
                  ],
                ),
                if (local.source == 'custom') ...[
                  gap,
                  PennaField(
                    label: tr('自定义来源'),
                    hint: 'https://hf-mirror.com',
                    value: local.customSource,
                    onChanged: (v) =>
                        local.update(() => local.customSource = v.trim()),
                  ),
                  if (local.customSource.isNotEmpty &&
                      sourceBase(local.customSource) == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        tr('地址要以 http:// 或 https:// 开头'),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: PennaColors.diffDelText,
                        ),
                      ),
                    ),
                ],
                gap,
                _label(tr('llama.cpp 运行时')),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (accel, label) in [
                      (false, tr('官方源')),
                      (true, tr('GitHub 加速')),
                    ])
                      PennaChip(
                        label: label,
                        selected: local.githubAccel == accel,
                        onTap: () =>
                            local.update(() => local.githubAccel = accel),
                      ),
                  ],
                ),
                gap,
                PennaField(
                  label: 'HuggingFace Token',
                  hint: tr('下载要申请访问的模型时用'),
                  obscure: true,
                  value: service.config.secrets[hfTokenSecret] ?? '',
                  onChanged: (v) => service.update(
                    service.config.setSecret(hfTokenSecret, v.trim()),
                  ),
                ),
              ],
            ),
          ),
          gap,
          _Runtime(local: local),
          gap,
          _card(tr('llama-server 参数'), _Params(local: local)),
          gap,
          _Prompts(local: local),
        ],
      ),
    );
  }
}

Widget _card(String title, Widget child, {Widget? trailing}) => PennaCard(
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
);

Widget _label(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(
    text,
    style: TextStyle(fontSize: 11.5, color: PennaColors.slate500),
  ),
);

Widget _path(String text) => Tooltip(
  message: text,
  child: Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: monoStyle.copyWith(fontSize: 11.5, color: PennaColors.slate700),
  ),
);

/// 模型文件夹:电脑上已有模型的文件夹,连同子文件夹一起找,找到的直接用。
class _Folders extends StatelessWidget {
  const _Folders({required this.local});

  final LocalModel local;

  Future<void> _add() async {
    final path = await getDirectoryPath();
    if (path != null) await local.addFolder(path);
  }

  @override
  Widget build(BuildContext context) {
    final any = local.modelFolders.isNotEmpty || local.autoFolders.isNotEmpty;
    Widget row(String folder, Widget end) => Row(
      children: [
        Icon(Icons.folder_outlined, size: 15, color: PennaColors.slate500),
        const SizedBox(width: 6),
        Expanded(child: _path(folder)),
        end,
      ],
    );
    return _card(
      tr('模型文件夹'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (any)
            IconButton(
              tooltip: tr('重新扫描'),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate500,
              icon: const Icon(Icons.refresh),
              onPressed: local.scanning ? null : local.rescan,
            ),
          PennaButton(
            label: tr('添加文件夹'),
            icon: Icons.create_new_folder_outlined,
            borderColor: PennaColors.border,
            onPressed: _add,
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final folder in local.modelFolders)
            row(
              folder,
              IconButton(
                tooltip: tr('移除'),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                color: PennaColors.slate400,
                icon: const Icon(Icons.close),
                onPressed: () => local.removeFolder(folder),
              ),
            ),
          // HuggingFace、ModelScope 的缓存:在就自动找,不能移除。
          for (final folder in local.autoFolders)
            row(
              folder,
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  tr('自动'),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
              ),
            ),
          Text(
            any ? local.foundSummary : tr('添加已有模型的文件夹,子文件夹一起查找'),
            style: TextStyle(fontSize: 11.5, color: PennaColors.slate500),
          ),
        ],
      ),
    );
  }
}

/// llama.cpp 运行时:下载固定版本,或用自己的 llama-server.exe。
class _Runtime extends StatelessWidget {
  const _Runtime({required this.local});

  final LocalModel local;

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'llama-server',
          // Windows 上选 .exe;别的平台的可执行文件没有后缀,不设过滤。
          extensions: Platform.isWindows ? ['exe'] : null,
        ),
      ],
    );
    if (picked != null) local.update(() => local.exePath = picked.path);
  }

  Future<void> _download(BuildContext context) async {
    final problem = await local.downloadRuntime();
    if (problem != null && context.mounted) {
      showToast(context, problem, warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exe = local.serverExe;
    final progress = local.progressOf('runtime');
    return _card(
      tr('llama.cpp 运行时'),
      trailing: PennaButton(
        label: tr('选择 llama-server.exe'),
        icon: Icons.folder_open,
        borderColor: PennaColors.border,
        onPressed: _pick,
      ),
      exe != null
          ? Row(
              children: [
                Icon(Icons.check_circle, size: 15, color: PennaColors.accent),
                const SizedBox(width: 6),
                Expanded(child: _path(exe)),
                if (local.exePath.isNotEmpty)
                  PennaButton(
                    label: tr('不用这个'),
                    icon: Icons.close,
                    background: PennaColors.slate100,
                    onPressed: () => local.update(() => local.exePath = ''),
                  ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Platform.isWindows
                            ? tr('llama.cpp {0} · Vulkan 版 · {1} MB', [
                                llamaCppTag,
                                (llamaRuntimeSize / (1 << 20)).toStringAsFixed(
                                  1,
                                ),
                              ])
                            : tr(
                                '这个平台请自行下载 llama.cpp 运行时,再用「选择 llama-server」指过来',
                              ),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: progress.received / llamaRuntimeSize,
                          minHeight: 3,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (progress != null)
                  PennaButton(
                    label: tr('停止'),
                    icon: Icons.stop_circle_outlined,
                    background: PennaColors.slate100,
                    onPressed: () => local.cancelDownload('runtime'),
                  )
                else if (Platform.isWindows)
                  PennaButton(
                    label: tr('下载'),
                    icon: Icons.download,
                    background: PennaColors.primaryBg,
                    foreground: PennaColors.primary,
                    onPressed: local.dir == null
                        ? null
                        : () => _download(context),
                  ),
              ],
            ),
    );
  }
}

/// 看图描述的要求:像 Preset 一样存好几条,有名字,选中的那条就是 GGUF 模型用的。
class _Prompts extends StatelessWidget {
  const _Prompts({required this.local});

  final LocalModel local;

  Future<void> _remove(BuildContext context) async {
    final ok = await confirmDelete(
      context,
      tr('删除「{0}」?', [local.currentPrompt.name]),
      tr('此操作不可撤销。'),
    );
    if (ok) local.removePrompt();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = local.currentPrompt;
    // 换了一条(或加、删)时输入框重建,显示那一条的文字。
    final key = '${local.promptIndex}-${local.captionPrompts.length}';
    return _card(
      tr('看图描述的要求'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PennaButton(
            label: tr('新建(复制当前)'),
            icon: Icons.add,
            borderColor: PennaColors.border,
            onPressed: local.addPrompt,
          ),
          if (local.captionPrompts.length > 1) ...[
            const SizedBox(width: 6),
            PennaButton(
              label: tr('删除'),
              icon: Icons.delete_outline,
              borderColor: PennaColors.border,
              onPressed: () => _remove(context),
            ),
          ],
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, p) in local.captionPrompts.indexed)
                PennaChip(
                  label: p.name.trim().isEmpty ? tr('未命名') : p.name,
                  selected: i == local.promptIndex,
                  onTap: () => local.pickPrompt(i),
                ),
            ],
          ),
          gap,
          PennaField(
            key: ValueKey('prompt-name-$key'),
            label: tr('名称'),
            value: prompt.name,
            onChanged: (v) => local.editPrompt(name: v),
          ),
          gap,
          PennaField(
            key: ValueKey('prompt-text-$key'),
            label: tr('要求'),
            value: prompt.text,
            maxLines: 5,
            onChanged: (v) => local.editPrompt(text: v),
          ),
        ],
      ),
    );
  }
}

/// 端口、上下文长度、GPU 层数。不在范围里的数不收,框里改回合法的数才生效。
class _Params extends StatelessWidget {
  const _Params({required this.local});

  final LocalModel local;

  Widget _field(
    String label,
    int value,
    ({int min, int max}) range,
    ValueChanged<int> set,
  ) => Expanded(
    child: PennaField(
      label: label,
      value: '$value',
      onChanged: (v) {
        final n = int.tryParse(v.trim());
        if (n != null && n >= range.min && n <= range.max) {
          local.update(() => set(n));
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _field(tr('端口'), local.port, (
          min: 1024,
          max: 65535,
        ), (n) => local.port = n),
        const SizedBox(width: 10),
        _field(tr('上下文长度'), local.context, (
          min: 512,
          max: 262144,
        ), (n) => local.context = n),
        const SizedBox(width: 10),
        _field(tr('GPU 层数(-1 全部)'), local.gpuLayers, (
          min: -1,
          max: 999,
        ), (n) => local.gpuLayers = n),
      ],
    );
  }
}
