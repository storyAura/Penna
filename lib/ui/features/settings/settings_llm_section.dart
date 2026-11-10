import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/harness/providers/grok_auth.dart';
import '../../../core/harness/providers/llm_http.dart';
import '../../../core/harness/providers/llm_router.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../studio/mention.dart';
import 'settings_grok_login.dart';
import 'settings_sections.dart';
import '../../../l10n/l10n.dart';

part 'settings_model_list.dart';

Map<String, String> get _protocolLabels => {
  protocolOpenAi: 'OpenAI',
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

/// API 管理:多个接口按顺序使用,失败自动换下一个;Agent 和润色可各自指定。
class LlmSection extends StatelessWidget {
  const LlmSection({super.key, required this.service});

  final ConfigService service;

  void _add({
    String? name,
    String? baseUrl,
    String model = '',
    String protocol = protocolOpenAi,
  }) {
    service.update(
      service.config.putLlm(
        LlmProfile(
          id: '${DateTime.now().microsecondsSinceEpoch}',
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
  Widget build(BuildContext context) {
    final cfg = service.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('API 管理'), tr('按顺序使用,失败自动换下一个 · Key 仅存本机')),
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
                child: _LlmCard(service: service, llm: llm, index: index),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PennaButton(
              label: tr('添加模型'),
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

class _LlmCard extends StatefulWidget {
  const _LlmCard({
    required this.service,
    required this.llm,
    required this.index,
  });

  final ConfigService service;
  final LlmProfile llm;
  final int index;

  @override
  State<_LlmCard> createState() => _LlmCardState();
}

class _LlmCardState extends State<_LlmCard> {
  bool _pulling = false;

  /// 最近一次拉取到的模型;null 表示还没拉过或上次失败。
  List<String>? _models;
  String? _pullError;

  /// 测试连接通过后的那句话。
  String? _testOk;

  /// 从列表里选过几次;模型名称输入框靠它重建来显示选中的名字。
  int _picks = 0;

  /// 放弃过几次改动;所有输入框靠它重建,显示回已保存的值。
  int _reverts = 0;

  /// 还没保存的改动:名称、地址、模型、协议和 Key 都先改在这里,点「保存」才写进设置。
  /// 开关、删除、拖动顺序不经过它,立即生效。
  late LlmProfile _draft = widget.llm;
  late String _key = service.config.llmKey(widget.llm.id);

  /// 上次看到的已保存的 Key;别处改了 Key 时拿它判断这张卡片改没改过。
  late String _savedKey = _key;
  bool _saving = false;

  ConfigService get service => widget.service;
  LlmProfile get llm => _draft;
  int get index => widget.index;

  static bool _same(LlmProfile a, LlmProfile b) =>
      a.name == b.name &&
      a.baseUrl == b.baseUrl &&
      a.model == b.model &&
      a.protocol == b.protocol &&
      a.contextLimit == b.contextLimit;

  bool get _grok => llm.protocol == protocolGrok;

  // Grok 账号的 Key 是程序自己换的 token,不算用户改的。
  bool get _dirty =>
      !_same(_draft, widget.llm) ||
      !_grok && _key != service.config.llmKey(llm.id);

  /// 把草稿存进设置。换成别的协议时 Grok 的 token 一起删掉,不能发给别的地址。
  AppConfig _commit(AppConfig cfg, LlmProfile draft, String key) {
    final next = cfg.putLlm(draft);
    return draft.protocol == protocolGrok
        ? next
        : next.signOutGrok(draft.id).setSecret(llmSecretKey(draft.id), key);
  }

  @override
  void didUpdateWidget(_LlmCard old) {
    super.didUpdateWidget(old);
    // 设置在别处变了(刚保存完、本地反推更新了地址):没改过的那几项跟着走,改过的留着草稿。
    final was = old.llm, now = widget.llm;
    final key = service.config.llmKey(now.id);
    if (_same(was, now) && key == _savedKey) return;
    String pick(String draft, String before, String after) =>
        draft == before ? after : draft;
    final next = now.copyWith(
      name: pick(_draft.name, was.name, now.name),
      baseUrl: pick(_draft.baseUrl, was.baseUrl, now.baseUrl),
      model: pick(_draft.model, was.model, now.model),
      protocol: pick(_draft.protocol, was.protocol, now.protocol),
      contextLimit: _draft.contextLimit == was.contextLimit
          ? now.contextLimit
          : _draft.contextLimit,
    );
    final nextKey = pick(_key, _savedKey, key);
    // 输入框只在创建时读一次值:显示的内容变了才重建它们(刚保存完不用)。
    if (!_same(next, _draft) || nextKey != _key) _reverts++;
    _draft = next;
    _key = nextKey;
    _savedKey = key;
  }

  @override
  void dispose() {
    // 换到别的分区时卡片会被拆掉:没保存的改动替用户存上,不悄悄丢掉。
    // 删掉的卡片不算:不然会把刚删的接口又加回去。
    if (_dirty) {
      final draft = _draft.copyWith(enabled: widget.llm.enabled);
      final key = _key;
      Future.microtask(() {
        final cfg = service.config;
        if (!cfg.llms.any((l) => l.id == draft.id)) return;
        service.update(_commit(cfg, draft, key));
      });
    }
    super.dispose();
  }

  void _put(LlmProfile next) => setState(() => _draft = next);

  Future<void> _save() async {
    setState(() => _saving = true);
    service.update(
      _commit(
        service.config,
        _draft.copyWith(enabled: widget.llm.enabled),
        _key,
      ),
    );
    await service.flushed();
    if (!mounted) return;
    setState(() => _saving = false);
    final error = service.lastError;
    showToast(context, error ?? tr('已保存'), warn: error != null);
  }

  void _revert() => setState(() {
    _draft = widget.llm;
    _key = _savedKey = service.config.llmKey(widget.llm.id);
    _reverts++;
  });

  Future<void> _pull() async {
    setState(() {
      _pulling = true;
      _pullError = null;
      _testOk = null;
    });
    List<String>? models;
    String? error;
    try {
      models = await listModels(
        protocol: llm.protocol,
        baseUrl: _grok ? grokApiBase : llm.baseUrl,
        apiKey: _grok ? await grokAccessToken(service, llm.id) : _key,
      );
      if (models.isEmpty) error = tr('接口没有返回模型');
    } on LlmException catch (e) {
      error = e.message;
    } on Object catch (e) {
      // 没料到的错误也要让按钮恢复可用;只报类型,原文可能带着 Key。
      error = tr('拉取失败({0})', [e.runtimeType]);
    }
    if (!mounted) return;
    setState(() {
      _pulling = false;
      _models = error == null ? models : null;
      _pullError = error;
    });
  }

  /// 给填的每个模型各发一句话,等到第一个字就算通。
  Future<void> _test() async {
    final models = llm.models;
    setState(() {
      _pulling = true;
      _pullError = models.isEmpty ? tr('先填模型名称') : null;
      _testOk = null;
    });
    String? error = _pullError;
    for (final model in error == null ? models : const <String>[]) {
      final where = models.length > 1 ? '$model:' : '';
      try {
        // 拿到第一段就取消订阅,请求随之掐断,不等它说完。
        await streamChat(
          LlmRequest(
            protocol: llm.protocol,
            baseUrl: llm.baseUrl,
            model: model,
            apiKey: _key,
            token: _grok ? () => grokAccessToken(service, llm.id) : null,
            messages: const [
              {'role': 'user', 'content': 'hi'},
            ],
          ),
        ).first.timeout(const Duration(seconds: 30));
      } on LlmException catch (e) {
        error = '$where${e.message}';
      } on TimeoutException {
        error = tr('{0}30 秒没有回应', [where]);
      } on Object catch (e) {
        // 只报类型,原文可能带着 Key。
        error = '$where测试失败(${e.runtimeType})';
      }
      if (error != null) break;
    }
    if (!mounted) return;
    setState(() {
      _pulling = false;
      _pullError = error;
      _testOk = error == null ? tr('连接正常') : null;
    });
  }

  /// 勾选或取消一个模型;勾选的先后就是使用的先后。
  void _pick(String model) {
    final picked = llm.models;
    _put(
      llm.copyWith(
        model: [
          for (final m in picked)
            if (m != model) m,
          if (!picked.contains(model)) model,
        ].join(', '),
      ),
    );
    setState(() => _picks++);
  }

  /// 换协议时,如果地址还是原协议的默认值,就一起换成新协议的默认值。
  void _setProtocol(String protocol) {
    if (protocol == llm.protocol) return;
    final untouched =
        llm.baseUrl.trim().isEmpty ||
        llm.baseUrl.trim() == defaultBaseUrls[llm.protocol];
    // 换走时 token 不留在 Key 那一栏:它只能发给 xAI。
    if (_grok) _key = '';
    _put(
      llm.copyWith(
        protocol: protocol,
        baseUrl: untouched || protocol == protocolGrok
            ? defaultBaseUrls[protocol] ?? ''
            : null,
        model: llm.models.isNotEmpty
            ? null
            : protocol == protocolGrok
            ? defaultGrokModel
            : protocol == protocolClaudeCode
            ? 'opus'
            : protocol == protocolCodex
            ? cliDefaultModel
            : null,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await confirmDelete(
      context,
      tr('删除「{0}」?', [llm.name]),
      tr('API Key 会一并删除。'),
    );
    if (ok) service.update(service.config.removeLlm(llm.id));
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PennaCard(
      borderColor: widget.llm.enabled
          ? PennaColors.primaryBorder
          : PennaColors.border,
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: PennaColors.slate400,
                    ),
                  ),
                ),
              ),
              Text(
                '${index + 1}',
                style: titleStyle.copyWith(
                  color: widget.llm.enabled
                      ? PennaColors.primary
                      : PennaColors.slate400,
                ),
              ),
              const SizedBox(width: 12),
              // 协议多了一行放不下时折行。
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final protocol in _protocolLabels.keys)
                      PennaChip(
                        label: _protocolLabels[protocol]!,
                        selected: llm.protocol == protocol,
                        onTap: () => _setProtocol(protocol),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('删除'),
                iconSize: 18,
                icon: const Icon(Icons.delete_outline),
                color: PennaColors.slate500,
                onPressed: () => _confirmDelete(context),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: widget.llm.enabled,
                  onChanged: (on) => service.update(
                    service.config.putLlm(widget.llm.copyWith(enabled: on)),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PennaField(
                        key: ValueKey('name-$_reverts'),
                        label: tr('显示名称'),
                        value: llm.name,
                        onChanged: (v) => _put(llm.copyWith(name: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PennaField(
                        // 换成 Grok 时可能填上默认模型,要重建才显示得出来。
                        key: ValueKey(
                          'model-${llm.protocol}-$_picks-$_reverts',
                        ),
                        label: tr('模型名称'),
                        hint: switch (llm.protocol) {
                          protocolGoogle => tr('gemini-2.5-flash,可填多个'),
                          protocolGrok => tr('grok-4.7,可填多个'),
                          protocolClaudeCode => tr('opus、sonnet,可填多个'),
                          protocolCodex => tr('default 为默认模型'),
                          _ => tr('gpt-4o-mini,可填多个'),
                        },
                        value: llm.model,
                        onChanged: (v) => _put(llm.copyWith(model: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: PennaField(
                        key: ValueKey('limit-$_reverts'),
                        label: tr('上下文上限(K)'),
                        hint: tr('自动'),
                        value: llm.contextLimit > 0
                            ? '${llm.contextLimit ~/ 1000}'
                            : '',
                        onChanged: (v) => _put(
                          llm.copyWith(
                            contextLimit: (int.tryParse(v.trim()) ?? 0) * 1000,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                gap,
                if (_grok) ...[
                  GrokLoginRow(
                    service: service,
                    draft: _draft.copyWith(enabled: widget.llm.enabled),
                  ),
                  gap,
                ] else if (isCliProtocol(llm.protocol)) ...[
                  Text(
                    llm.protocol == protocolClaudeCode
                        ? tr('用本机 Claude Code 登录的账号')
                        : tr('用本机 Codex 登录的账号'),
                    style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                  ),
                  gap,
                ] else ...[
                  PennaField(
                    // 换协议会改默认地址,要重建输入框才显示得出来。
                    key: ValueKey('url-${llm.protocol}-$_reverts'),
                    label: 'Base URL',
                    hint: defaultBaseUrls[llm.protocol],
                    value: llm.baseUrl,
                    onChanged: (v) => _put(llm.copyWith(baseUrl: v)),
                  ),
                  gap,
                  PennaField(
                    key: ValueKey('key-${llm.protocol}-$_reverts'),
                    label: 'API Key',
                    hint: tr('可留空'),
                    obscure: true,
                    value: _key,
                    onChanged: (v) => setState(() => _key = v),
                  ),
                  gap,
                ],
                Row(
                  children: [
                    PennaButton(
                      label: tr('拉取模型'),
                      icon: Icons.cloud_download_outlined,
                      background: PennaColors.slate100,
                      onPressed: _pulling ? null : _pull,
                    ),
                    const SizedBox(width: 6),
                    PennaButton(
                      label: tr('测试连接'),
                      icon: Icons.bolt_outlined,
                      background: PennaColors.slate100,
                      onPressed: _pulling ? null : _test,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (_pullError ?? _testOk) ?? (dirty ? tr('未保存') : ''),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _pullError != null
                              ? PennaColors.diffDelText
                              : _testOk != null
                              ? PennaColors.diffAddText
                              : PennaColors.amber,
                        ),
                      ),
                    ),
                    if (dirty) ...[
                      PennaButton(
                        label: tr('放弃'),
                        icon: Icons.undo,
                        background: PennaColors.slate100,
                        onPressed: _saving ? null : _revert,
                      ),
                      const SizedBox(width: 6),
                    ],
                    PennaButton(
                      label: tr('保存'),
                      icon: Icons.check,
                      background: PennaColors.primary,
                      foreground: Colors.white,
                      onPressed: dirty && !_saving ? _save : null,
                    ),
                  ],
                ),
                // 已选的模型按使用顺序排在列表上面:列表再长也看得见选了什么。
                if (llm.models.length > 1 ||
                    _models != null && llm.models.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(tr('已选'), style: titleStyle),
                      for (final (i, model) in llm.models.indexed)
                        MentionChip(
                          name: model,
                          prefix: '${i + 1} · ',
                          onRemove: () => _pick(model),
                        ),
                    ],
                  ),
                ],
                if (_models != null) ...[
                  const SizedBox(height: 8),
                  _ModelList(
                    models: _models!,
                    selected: llm.models.toSet(),
                    onPick: _pick,
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PennaButton(
                      label: tr('收起列表'),
                      icon: Icons.expand_less,
                      background: PennaColors.slate100,
                      onPressed: () => setState(() => _models = null),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
