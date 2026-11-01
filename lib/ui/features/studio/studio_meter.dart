part of 'studio_view_model.dart';

/// 上下文里的一部分:系统预设、Skill、对话这些,各占多少。
typedef ContextPart = ({String label, int tokens});

/// 输入框旁边的上下文圆环要显示的:用了多少([used])、上限([limit],认不出模型时为 null)。
/// [estimated] 为真是「预计加载」:这场对话刚切过来,还没在这次发过消息(用户要求)。
/// [usage] 是接口报的明细,用的是估算时为 null。[api]、[model] 是接口名和模型型号。
/// [parts] 各部分的份额加起来等于 [used]。
typedef ContextMeter = ({
  int used,
  int? limit,
  bool estimated,
  LlmUsage? usage,
  String api,
  String model,
  List<ContextPart> parts,
});

/// 按文字估出来的各部分。
typedef _ContextTokens = ({
  int preset,
  int skills,
  int rules,
  int draft,
  int chat,
  int tools,
  int files,
});

extension StudioMeter on StudioViewModel {
  /// 没有可用的模型时为 null。
  ContextMeter? get contextMeter {
    final cfg = config.config;
    final chain = _usable(cfg.agentChain);
    if (chain.isEmpty) return null;
    final reply = _messages.reversed.where((m) => m.usage != null).firstOrNull;
    final live = reply != null && reply.time == _liveUsageAt;
    // 切过来的对话:最后一条就是报过用量的回复时,那个数最准;否则按文字估。
    final latest = _messages.reversed.where((m) => !m.tool).firstOrNull;
    final measured = live || identical(reply, latest) ? reply?.usage : null;
    // 切过来的对话下一条用的是眼前排第一的模型,不一定是上次回复的那个。
    final (llm, model) = _modelNamed(chain, live ? reply.by : null);
    final t = _contextTokens(cfg);
    final total =
        t.preset + t.skills + t.rules + t.draft + t.chat + t.tools + t.files;
    final used = measured == null ? total : measured.input + measured.output;
    // 接口只报总数:各部分的比例按文字估,摊到真实的总数上。
    return (
      used: used,
      limit: llm.contextLimit > 0 ? llm.contextLimit : modelContextLimit(model),
      estimated: !live,
      usage: measured,
      api: llm.name,
      model: model,
      parts: [
        for (final (label, tokens) in [
          (tr('系统预设'), t.preset),
          ('Skill', t.skills),
          (tr('内置规则'), t.rules),
          (tr('成稿'), t.draft),
          (tr('对话'), t.chat),
          (tr('工具结果'), t.tools),
          (tr('附件和引用'), t.files),
        ])
          if (tokens > 0) (label: label, tokens: tokens * used ~/ total),
      ],
    );
  }

  /// 显示名([_requests] 起的)对应哪个接口的哪个模型;对不上就是眼前要用的第一个。
  (LlmProfile, String) _modelNamed(List<LlmProfile> chain, String? name) {
    for (final llm in chain) {
      for (final model in llm.models) {
        final shown = llm.models.length > 1 ? '${llm.name} · $model' : llm.name;
        if (shown == name) return (llm, model);
      }
    }
    return (chain.first, chain.first.models.first);
  }

  /// 下一条消息发出去时各部分大约要带多少 token。生成回复时每来一段字都会重建界面,
  /// 所以记住结果:对话和成稿都没变、或正在生成时不重算。
  _ContextTokens _contextTokens(AppConfig cfg) {
    final kept = _estimate;
    if (kept != null &&
        (isStreaming ||
            identical(_estimateFor, _messages) &&
                identical(_estimateBlocks, _blocks))) {
      return kept;
    }
    final preset = cfg.activePreset;
    final persona = estimateTokens(preset.systemPrompt);
    final skills = estimateTokens(_loadedSkillText(cfg));
    final draft = estimateTokens(
      layoutOnly ? _layoutPrompt : '${_joined(labels: true)}$_siblingPages',
    );
    final system = estimateTokens(_systemFor(cfg, preset));
    final sent = _sentSkills(cfg);
    var chat = 0, tools = 0, files = 0;
    for (final m in _messages) {
      if (!m.fromUser && (m.failed || m.text.isEmpty)) continue;
      final own = estimateTokens(m.text);
      m.tool ? tools += own : chat += own;
      if (!m.fromUser) continue;
      final extra = estimateTokens(_withReferences(m, sent)) - own;
      files +=
          (extra > 0 ? extra : 0) +
          m.attachments.where((a) => a.isImage).length * imageTokenEstimate;
    }
    final rules = system - persona - skills - draft;
    _estimateFor = _messages;
    _estimateBlocks = _blocks;
    return _estimate = (
      preset: persona + estimateTokens(cfg.piercingText),
      skills: skills,
      rules: rules > 0 ? rules : 0,
      draft: draft,
      chat: chat,
      tools: tools,
      files: files,
    );
  }

  /// 系统提示里 Skill 那部分的文字。区域控制那边固定带这几个(同 `_layoutSystemPrompt`)。
  String _loadedSkillText(AppConfig cfg) => layoutOnly
      ? [
          for (final s in builtinSkillList)
            if (s.id == 'moss-layout' ||
                s.id == 'character-lib' ||
                s.id == 'comic-page' && !cfg.disabledSkills.contains(s.id))
              s.body,
        ].join()
      : _skillPrompt(cfg);
}
