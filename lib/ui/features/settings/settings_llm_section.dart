import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/harness/llm_probe.dart';
import '../../../core/harness/providers/gemini_provider.dart';
import '../../../core/harness/providers/grok_auth.dart';
import '../../../core/harness/providers/llm_http.dart';
import '../../../core/harness/providers/llm_router.dart';
import '../../../core/harness/web_search.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../studio/mention.dart';
import 'settings_agent_sections.dart';
import 'settings_grok_login.dart';
import 'settings_sections.dart';
import '../../../l10n/l10n.dart';

part 'settings_llm_card.dart';
part 'settings_llm_health.dart';
part 'settings_model_list.dart';

/// 用 API Key 的协议和用账号登录的协议,卡片上分两行列。
const _apiProtocols = [protocolOpenAi, protocolGoogle];
const _accountProtocols = [protocolGrok, protocolClaudeCode, protocolCodex];

Map<String, String> get _protocolLabels => {
  protocolOpenAi: tr('OpenAI 兼容'),
  protocolGoogle: 'Google',
  protocolGrok: tr('Grok 账号'),
  protocolClaudeCode: tr('Claude 订阅'),
  protocolCodex: tr('Codex 订阅'),
};

/// 「常用服务」里预填的接口(地址和模型取自各家 2026-10 的文档)。名字存进设置,不翻译。
const llmProviders = [
  (name: 'xAI Grok', baseUrl: 'https://api.x.ai/v1', model: defaultGrokModel),
  (
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-flash',
  ),
  (
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-5.2',
  ),
  (name: 'Kimi', baseUrl: 'https://api.moonshot.cn/v1', model: 'kimi-k3.1-pro'),
  (
    name: '阿里云百炼',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  ),
];

/// 测试连接用的请求:[key] 不给就用存着的(卡片上测的是还没存的草稿)。
LlmRequest probeRequest(
  ConfigService service,
  LlmProfile llm,
  String model, {
  String? key,
}) => LlmRequest(
  protocol: llm.protocol,
  baseUrl: llm.baseUrl,
  model: model,
  apiKey: key ?? service.config.llmKey(llm.id),
  token: llm.protocol == protocolGrok
      ? () => grokAccessToken(service, llm.id)
      : null,
  serviceTier: llm.protocol == protocolGoogle ? llm.serviceTier : '',
  messages: const [],
);

/// API 管理:多个接口按顺序使用,失败自动换下一个;Agent 和润色可各自指定。
class LlmSection extends StatefulWidget {
  const LlmSection({super.key, required this.service});

  final ConfigService service;

  @override
  State<LlmSection> createState() => _LlmSectionState();
}

class _LlmSectionState extends State<LlmSection> {
  /// 刚加的那张卡片:展开着,好填 Key。
  String? _added;

  ConfigService get service => widget.service;

  void _add({
    String? name,
    String? baseUrl,
    String model = '',
    String protocol = protocolOpenAi,
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _added = id);
    service.update(
      service.config.putLlm(
        LlmProfile(
          id: id,
          name: name ?? tr('新模型'),
          baseUrl: baseUrl ?? defaultBaseUrls[protocolOpenAi]!,
          model: model,
          protocol: protocol,
        ),
      ),
    );
  }

  /// 在按钮下面弹出常用服务,选一个就加一张填好地址和模型的卡片(Key 自己填)。
  Future<void> _addProvider(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final picked = await popMenu(
      context,
      box.localToGlobal(box.size.bottomLeft(Offset.zero)),
      [
        for (final p in llmProviders) p.name,
        _protocolLabels[protocolGrok]!,
        _protocolLabels[protocolClaudeCode]!,
        _protocolLabels[protocolCodex]!,
      ],
    );
    if (picked == _protocolLabels[protocolClaudeCode]) {
      return _add(
        name: 'Claude',
        baseUrl: '',
        model: 'opus',
        protocol: protocolClaudeCode,
      );
    }
    if (picked == _protocolLabels[protocolCodex]) {
      return _add(
        name: 'Codex',
        baseUrl: '',
        model: cliDefaultModel,
        protocol: protocolCodex,
      );
    }
    if (picked == _protocolLabels[protocolGrok]) {
      return _add(
        name: 'Grok',
        baseUrl: grokApiBase,
        model: defaultGrokModel,
        protocol: protocolGrok,
      );
    }
    final p = llmProviders.where((p) => p.name == picked).firstOrNull;
    if (p != null) _add(name: p.name, baseUrl: p.baseUrl, model: p.model);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final health = _LlmHealthPanel(service: service);
      // 宽的时候右边一栏放「全部测试」,窄了挪到上面。
      if (box.maxWidth < _twoColumnsFrom) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [health, gap, _list(context)],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _list(context)),
          const SizedBox(width: 16),
          SizedBox(
            width: _healthWidth,
            child: Padding(
              // 和左边标题下面的第一张卡片对齐。
              padding: const EdgeInsets.only(top: 60),
              child: health,
            ),
          ),
        ],
      );
    },
  );

  Widget _list(BuildContext context) {
    final cfg = service.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('API 管理'), tr('按顺序使用,失败自动换下一个 · 改动自动保存')),
        if (cfg.llms.isNotEmpty) ...[
          PennaCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LlmRolePicker(
                  title: tr('Agent 对话'),
                  service: service,
                  pinnedId: cfg.activeLlmId,
                  onPick: (id) =>
                      service.config.copyWith(activeLlmId: () => id),
                ),
                gap,
                LlmRolePicker(
                  title: tr('润色'),
                  service: service,
                  pinnedId: cfg.polishLlmId,
                  onPick: (id) =>
                      service.config.copyWith(polishLlmId: () => id),
                ),
                gap,
                WebSearchPicker(service: service),
              ],
            ),
          ),
          gap,
        ],
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) =>
              service.update(service.config.moveLlm(from, to)),
          proxyDecorator: (child, _, _) =>
              Material(color: Colors.transparent, child: child),
          children: [
            for (final (index, llm) in cfg.llms.indexed)
              Padding(
                key: ValueKey(llm.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: _LlmCard(
                  service: service,
                  llm: llm,
                  index: index,
                  // 只有一个接口时直接摊开。
                  open: llm.id == _added || cfg.llms.length == 1,
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PennaButton(
              label: tr('添加接口'),
              icon: Icons.add,
              background: PennaColors.primary,
              foreground: Colors.white,
              onPressed: _add,
            ),
            Builder(
              builder: (context) => PennaButton(
                label: tr('常用服务'),
                icon: Icons.expand_more,
                borderColor: PennaColors.border,
                onPressed: () => _addProvider(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 给某个用途指定模型:「按顺序」或某一个已启用的模型。
class LlmRolePicker extends StatelessWidget {
  const LlmRolePicker({
    super.key,
    required this.title,
    required this.service,
    required this.pinnedId,
    required this.onPick,
  });

  final String title;
  final ConfigService service;
  final String? pinnedId;

  /// 选中某项后的新配置;null 表示按顺序。
  final AppConfig Function(String? id) onPick;

  @override
  Widget build(BuildContext context) {
    final usable = service.config.llms.where((l) => l.enabled).toList();
    // 指定的模型被删了或关了,就当作按顺序。
    final pinned = usable.any((l) => l.id == pinnedId) ? pinnedId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: titleStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PennaChip(
              label: tr('按顺序'),
              selected: pinned == null,
              onTap: () => service.update(onPick(null)),
            ),
            for (final llm in usable)
              PennaChip(
                label: llm.name.trim().isEmpty ? tr('未命名') : llm.name,
                selected: pinned == llm.id,
                onTap: () => service.update(onPick(llm.id)),
              ),
          ],
        ),
      ],
    );
  }
}
