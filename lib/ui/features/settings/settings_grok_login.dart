import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/providers/grok_auth.dart';
import '../../../core/harness/providers/llm_http.dart';
import '../../../core/harness/web_search.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_agent_sections.dart';
import 'settings_sections.dart';

/// Grok 账号卡片上的那一行:没登录时是登录按钮,登录了显示状态和退出。
/// [draft] 是卡片上还没保存的样子:登录时一起存上,协议才对得上。
class GrokLoginRow extends StatelessWidget {
  const GrokLoginRow({super.key, required this.service, required this.draft});

  final ConfigService service;
  final LlmProfile draft;

  Future<void> _login(BuildContext context) async {
    final tokens = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _GrokLoginDialog(),
    );
    if (tokens == null) return;
    service.update(
      service.config.putLlm(draft).withGrokTokens(draft.id, tokens),
    );
    if (context.mounted) showToast(context, tr('已登录 Grok'));
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = service.config.grokSignedIn(draft.id);
    return Row(
      children: [
        Icon(
          signedIn ? Icons.check_circle_outline : Icons.account_circle_outlined,
          size: 16,
          color: signedIn ? PennaColors.diffAddText : PennaColors.slate400,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(signedIn ? tr('已登录') : tr('未登录'), style: hintStyle),
        ),
        if (signedIn)
          PennaButton(
            label: tr('退出登录'),
            icon: Icons.logout,
            background: PennaColors.slate100,
            onPressed: () =>
                service.update(service.config.signOutGrok(draft.id)),
          )
        else
          PennaButton(
            label: tr('登录 Grok'),
            icon: Icons.login,
            background: PennaColors.primary,
            foreground: Colors.white,
            onPressed: () => _login(context),
          ),
      ],
    );
  }
}

void _openInBrowser(Uri page) => unawaited(
  Process.run(
    Platform.isWindows ? 'rundll32' : 'xdg-open',
    Platform.isWindows ? ['url.dll,FileProtocolHandler', '$page'] : ['$page'],
  ),
);

/// 登录窗口:要一个短码、打开确认页,等用户在浏览器里点确认。确认了交回 token。
class _GrokLoginDialog extends StatefulWidget {
  const _GrokLoginDialog();

  @override
  State<_GrokLoginDialog> createState() => _GrokLoginDialogState();
}

class _GrokLoginDialogState extends State<_GrokLoginDialog> {
  GrokDevice? _device;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final device = await startGrokLogin();
      if (!mounted) return;
      setState(() => _device = device);
      _openInBrowser(device.page);
      final tokens = await waitGrokLogin(device, cancelled: () => !mounted);
      if (mounted && tokens != null) Navigator.of(context).pop(tokens);
    } on LlmException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      // 只报类型,原文可能带着 token。
      if (mounted) {
        setState(() => _error = tr('Grok 登录失败({0})', [e.runtimeType]));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    return AlertDialog(
      title: Text(tr('登录 Grok'), style: titleStyle),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: PennaColors.diffDelText,
                ),
              )
            else if (device == null)
              Text(tr('正在连接…'), style: hintStyle)
            else ...[
              Text(tr('在浏览器里确认这个代码'), style: hintStyle),
              const SizedBox(height: 10),
              SelectableText(
                device.userCode,
                contextMenuBuilder: pennaTextMenu,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  PennaButton(
                    label: tr('打开网页'),
                    icon: Icons.open_in_new,
                    background: PennaColors.slate100,
                    onPressed: () => _openInBrowser(device.page),
                  ),
                  const SizedBox(width: 6),
                  PennaButton(
                    label: tr('复制'),
                    icon: Icons.copy,
                    background: PennaColors.slate100,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: device.userCode)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(tr('等待确认…'), style: hintStyle),
            ],
          ],
        ),
      ),
      actions: [
        PennaButton(
          label: tr('取消'),
          background: PennaColors.slate100,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 「API 管理」顶上那一行:联网搜索关着、自动,或勾选哪几个能搜的接口轮换(按勾选的先后)。
class WebSearchPicker extends StatelessWidget {
  const WebSearchPicker({super.key, required this.service});

  final ConfigService service;

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    final usable = [
      for (final l in cfg.llms)
        if (l.enabled && canWebSearch(l)) l,
    ];
    // 勾过又关掉、删掉的不算。
    final picked = [
      for (final id in cfg.webSearchLlmIds)
        if (usable.any((l) => l.id == id)) id,
    ];
    void put({required bool on, List<String> ids = const []}) => service.update(
      service.config.copyWith(webSearch: on, webSearchLlmIds: ids),
    );
    void toggle(String id) => put(
      on: true,
      ids: picked.contains(id)
          ? [
              for (final p in picked)
                if (p != id) p,
            ]
          : [...picked, id],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(tr('联网搜索'), style: titleStyle),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                usable.isEmpty
                    ? tr('需要 Gemini、Grok、OpenAI、智谱、百炼或 OpenRouter 的接口')
                    : tr('可多选,按勾选的先后轮换'),
                overflow: TextOverflow.ellipsis,
                style: hintStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PennaChip(
              label: tr('不联网'),
              selected: !cfg.webSearch,
              onTap: () => put(on: false),
            ),
            PennaChip(
              label: tr('自动'),
              selected: cfg.webSearch && picked.isEmpty,
              onTap: () => put(on: true),
            ),
            for (final llm in usable)
              PennaChip(
                label: [
                  if (cfg.webSearch &&
                      picked.length > 1 &&
                      picked.contains(llm.id))
                    '${picked.indexOf(llm.id) + 1}',
                  llm.name.trim().isEmpty ? tr('未命名') : llm.name,
                ].join(' · '),
                selected: cfg.webSearch && picked.contains(llm.id),
                onTap: () => toggle(llm.id),
              ),
            // 没有搜索工具的也列出来(灰的、选不了),免得以为它不见了(2026-11-13 用户反馈)。
            for (final llm in cfg.llms)
              if (llm.enabled && !canWebSearch(llm))
                Tooltip(
                  message: tr('这个接口没有联网搜索工具'),
                  child: Opacity(
                    opacity: 0.45,
                    child: PennaChip(
                      label: llm.name.trim().isEmpty ? tr('未命名') : llm.name,
                      selected: false,
                      onTap: () =>
                          showToast(context, tr('这个接口没有联网搜索工具'), warn: true),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
