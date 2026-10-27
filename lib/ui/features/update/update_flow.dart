import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/harness/local/download.dart';
import '../../../core/harness/update/updater.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import '../../core/version.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import '../studio/markdown_text.dart';
import '../../../l10n/l10n.dart';

typedef FetchRelease = Future<Release?> Function();

/// 检查更新([channel] 是 'main' 正式版或 'dev' 测试版)。有新版本就弹窗介绍并可一键更新。
/// [quiet] 为真时(启动时自动检查)已是最新、出错都不打扰用户。
/// [switching] 为真时(刚切了通道)只要版本不同就给装,测试版切回正式版也能退回去。
Future<void> checkForUpdate(
  BuildContext context, {
  bool quiet = false,
  bool switching = false,
  FetchRelease? fetch,
  String current = appVersion,
  String channel = 'main',
}) async {
  Release? release;
  try {
    release = await (fetch ?? () => fetchLatestRelease(channel: channel))();
  } on UpdateException catch (e) {
    if (!quiet && context.mounted) showToast(context, e.message, warn: true);
    return;
  }
  if (!context.mounted) return;
  final diff = release == null ? 0 : compareVersions(release.version, current);
  if (switching ? diff == 0 : diff <= 0) {
    if (!quiet) showToast(context, tr('已是最新版本'));
    return;
  }
  final found = release!;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdateDialog(release: found, current: current),
  );
}

/// 新版本弹窗:更新说明,点「更新」后下载、解开,退出 Penna 换上新文件再重新打开。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.release, required this.current});

  final Release release;
  final String current;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final _cancel = DownloadCancel();

  /// 下载进度(0~1);null 表示还没开始下载。
  double? _progress;
  String? _status;
  bool _busy = false;

  Future<void> _update() async {
    // 换文件靠一个 PowerShell 脚本(见 updater.dart),只有 Windows 上能跑。
    if (!Platform.isWindows) {
      _fail(tr('这个平台不能自动更新,请到 GitHub 下载新版本覆盖本目录'));
      return;
    }
    final release = widget.release;
    setState(() {
      _busy = true;
      _progress = 0;
      _status = tr('下载中…');
    });
    try {
      final temp = await Directory.systemTemp.createTemp('penna-update-');
      final zip = '${temp.path}${Platform.pathSeparator}update.zip';
      await downloadFile(
        (
          url: release.url,
          path: zip,
          size: release.size,
          sha256: release.sha256,
        ),
        cancel: _cancel,
        onProgress: (got, total) {
          if (mounted && total != null && total > 0) {
            setState(() => _progress = got / total);
          }
        },
      );
      if (!mounted) return;
      setState(() => _status = tr('正在解压…'));
      final from = await unpackUpdate(
        zip,
        '${temp.path}${Platform.pathSeparator}new',
      );
      setState(() => _status = tr('即将重启…'));
      await launchUpdater(
        updateScript(
          pid: pid,
          from: from,
          to: File(Platform.resolvedExecutable).parent.path,
          cleanup: temp.path,
        ),
        temp.path,
      );
      // 走正常的关窗流程:先停掉本地反推的服务,再退出;脚本等 Penna 退出后换文件、重新打开。
      await windowManager.close();
    } on DownloadException catch (e) {
      _fail(e.message);
    } on UpdateException catch (e) {
      _fail(e.message);
    } on Object catch (e) {
      _fail(tr('更新失败({0})', [e.runtimeType]));
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
      _status = message;
    });
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final body = TextStyle(fontSize: 13, height: 1.6, color: PennaColors.text);
    return AlertDialog(
      title: Text(
        compareVersions(release.version, widget.current) < 0
            ? tr('切换到 v{0}', [release.version])
            : tr('发现新版本 v{0}', [release.version]),
        style: const TextStyle(fontSize: 16),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('当前版本 v{0}', [widget.current]),
              style: TextStyle(fontSize: 12, color: PennaColors.slate500),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: PennaCard(
                color: PennaColors.slate50,
                radius: 6,
                child: SingleChildScrollView(
                  child: release.notes.isEmpty
                      ? Text(tr('暂无更新说明'), style: body)
                      : SelectableText.rich(
                          markdownSpan(release.notes, body),
                          contextMenuBuilder: pennaTextMenu,
                        ),
                ),
              ),
            ),
            if (_progress != null || _status != null) ...[
              const SizedBox(height: 12),
              if (_progress != null)
                LinearProgressIndicator(value: _progress, minHeight: 4),
              if (_status != null) ...[
                const SizedBox(height: 6),
                Text(
                  _status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _busy
                        ? PennaColors.slate500
                        : PennaColors.diffDelText,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancel.cancel();
            Navigator.pop(context);
          },
          child: Text(_busy ? tr('取消') : tr('稍后')),
        ),
        TextButton(
          onPressed: Platform.isWindows && !_busy ? _update : null,
          child: Text(Platform.isWindows ? tr('更新并重启') : tr('请到 GitHub 手动更新')),
        ),
      ],
    );
  }
}

/// 设置里的「版本与更新」:当前版本和「检查更新」按钮。
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, this.fetch, this.service});

  final FetchRelease? fetch;

  /// 有它时显示「正式版 / 测试版」的通道切换,检查更新按它选的来。
  final ConfigService? service;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool _checking = false;

  Future<void> _check({bool switching = false}) async {
    setState(() => _checking = true);
    await checkForUpdate(
      context,
      switching: switching,
      fetch: widget.fetch,
      channel: widget.service?.config.updateChannel ?? 'main',
    );
    if (mounted) setState(() => _checking = false);
  }

  /// 切了通道就马上查一次,有那个通道的版本直接给装。
  void _switch(ConfigService service, String channel) {
    if (service.config.updateChannel == channel || _checking) return;
    service.update(service.config.copyWith(updateChannel: channel));
    _check(switching: true);
  }

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('版本与更新'), style: titleStyle),
                SizedBox(height: 2),
                Text(
                  tr('当前版本 v{0} · 每次启动自动检查', [appVersion]),
                  style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                ),
              ],
            ),
          ),
          if (widget.service case final service?) ...[
            for (final (channel, label) in [
              ('main', tr('正式版')),
              ('dev', tr('测试版')),
            ]) ...[
              PennaChip(
                label: label,
                selected: service.config.updateChannel == channel,
                onTap: () => _switch(service, channel),
              ),
              const SizedBox(width: 6),
            ],
            const SizedBox(width: 6),
          ],
          PennaButton(
            label: _checking ? tr('检查中…') : tr('检查更新'),
            icon: Icons.system_update_alt,
            borderColor: PennaColors.border,
            onPressed: _checking ? null : _check,
          ),
        ],
      ),
    );
  }
}
