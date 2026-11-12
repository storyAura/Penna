part of 'settings_llm_section.dart';

/// 停手多久后自动存。
const _autosaveDelay = Duration(milliseconds: 500);

/// 一个接口一张卡片。收起时一行:名字、协议、用的模型;点开改。
/// 改动停手 [_autosaveDelay] 后自动存,点选类的(协议、模型)立即存。
class _LlmCard extends StatefulWidget {
  const _LlmCard({
    required this.service,
    required this.llm,
    required this.index,
    required this.open,
  });

  final ConfigService service;
  final LlmProfile llm;
  final int index;

  /// 一开始是否展开。
  final bool open;

  @override
  State<_LlmCard> createState() => _LlmCardState();
}

class _LlmCardState extends State<_LlmCard> {
  late bool _open = widget.open;
  bool _pulling = false;

  /// 最近一次拉取到的模型;null 表示还没拉过或上次失败。
  List<String>? _models;
  String? _pullError;

  /// 测试连接通过后的那句话。
  String? _testOk;

  /// 设置在别处变了几次;输入框靠它重建,显示新的值。
  int _rebuilds = 0;

  /// 名称、地址、模型、协议和 Key 先改在这里,停手后由 [_flush] 存进设置。
  /// 开关、删除、拖动顺序不经过它,立即生效。
  late LlmProfile _draft = widget.llm;
  late String _key = service.config.llmKey(widget.llm.id);

  /// 上次看到的已保存的 Key;别处改了 Key 时拿它判断这张卡片改没改过。
  late String _savedKey = _key;
  Timer? _saveTimer;

  ConfigService get service => widget.service;
  LlmProfile get llm => _draft;

  static bool _same(LlmProfile a, LlmProfile b) =>
      a.name == b.name &&
      a.baseUrl == b.baseUrl &&
      a.model == b.model &&
      a.protocol == b.protocol &&
      a.contextLimit == b.contextLimit &&
      a.serviceTier == b.serviceTier;

  bool get _grok => llm.protocol == protocolGrok;
  bool get _account => _accountProtocols.contains(llm.protocol);

  // Grok 账号的 Key 是程序自己换的 token,不算用户改的。
  bool get _dirty =>
      !_same(_draft, widget.llm) ||
      !_grok && _key != service.config.llmKey(llm.id);

  /// 把草稿存进设置。换成别的协议时 Grok 的 token 一起删掉,不能发给别的地址。
  static AppConfig _commit(AppConfig cfg, LlmProfile draft, String key) {
    final next = cfg.putLlm(draft);
    return draft.protocol == protocolGrok
        ? next
        : next.signOutGrok(draft.id).setSecret(llmSecretKey(draft.id), key);
  }

  @override
  void didUpdateWidget(_LlmCard old) {
    super.didUpdateWidget(old);
    // 设置在别处变了(刚自动存完、本地反推更新了地址):没改过的那几项跟着走,改过的留着草稿。
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
      serviceTier: pick(_draft.serviceTier, was.serviceTier, now.serviceTier),
    );
    final nextKey = pick(_key, _savedKey, key);
    // 输入框只在创建时读一次值:显示的内容变了才重建它们(刚存完不用)。
    if (!_same(next, _draft) || nextKey != _key) _rebuilds++;
    _draft = next;
    _key = nextKey;
    _savedKey = key;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // 拆树时不能通知:没存的改动放进微任务里存。
    if (_dirty) {
      final draft = _draft.copyWith(enabled: widget.llm.enabled);
      final key = _key;
      Future.microtask(() => _store(service, draft, key));
    }
    super.dispose();
  }

  /// 删掉的接口不存:不然会把刚删的又加回去。
  static void _store(ConfigService service, LlmProfile draft, String key) {
    final cfg = service.config;
    if (!cfg.llms.any((l) => l.id == draft.id)) return;
    service.update(_commit(cfg, draft, key));
  }

  void _flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty) return;
    _store(service, _draft.copyWith(enabled: widget.llm.enabled), _key);
  }

  /// 打字:停手后再存。
  void _later() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_autosaveDelay, _flush);
  }

  void _put(LlmProfile next, {bool now = false}) {
    setState(() => _draft = next);
    now ? _flush() : _later();
  }

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

  /// 给填的每个模型各发一句话,等到第一个字就算通,记下各用了多久;
  /// 能联网搜索的接口再用第一个模型搜一次(搜索只用排第一的模型)。
  Future<void> _test() async {
    final models = llm.models;
    setState(() {
      _pulling = true;
      _pullError = models.isEmpty ? tr('先填模型名称') : null;
      _testOk = null;
    });
    String? error = _pullError;
    final speeds = <String>[];
    LlmRequest request(String model) =>
        probeRequest(service, llm, model, key: _key);
    for (final model in error == null ? models : const <String>[]) {
      final where = models.length > 1 ? '$model:' : '';
      final r = await probeChat(request(model), streamChat);
      if (r.error != null) {
        error = '$where${r.error}';
        break;
      }
      speeds.add('$where${formatMs(r.ms!)}');
    }
    if (error == null && canWebSearch(llm)) {
      final r = await probeSearch(request(models.first), streamChat);
      if (r.error != null) {
        // 对话是通的,速度照样写上。
        error = [
          ...speeds,
          tr('联网搜索:{0}', [r.error!]),
        ].join(' · ');
      } else {
        speeds.add(tr('联网 {0}', [formatMs(r.ms!)]));
      }
    }
    if (!mounted) return;
    setState(() {
      _pulling = false;
      _pullError = error;
      _testOk = error == null ? [tr('连接正常'), ...speeds].join(' · ') : null;
    });
  }

  /// 勾选或取消一个模型;勾选的先后就是使用的先后。
  void _pick(String model) {
    final picked = llm.models;
    _setModels([
      for (final m in picked)
        if (m != model) m,
      if (!picked.contains(model)) model,
    ]);
  }

  /// 手填的(逗号隔开能一次加几个),已经有的不重复加。
  void _addModels(String text) {
    final added = [
      for (final m in text.split(RegExp('[,,]')))
        if (m.trim().isNotEmpty) m.trim(),
    ];
    _setModels({...llm.models, ...added}.toList());
  }

  void _setModels(List<String> models) =>
      _put(llm.copyWith(model: models.join(', ')), now: true);

  /// 换协议时,如果地址还是原协议的默认值,就一起换成新协议的默认值。
  void _setProtocol(String protocol) {
    if (protocol == llm.protocol) return;
    final untouched =
        llm.baseUrl.trim().isEmpty ||
        llm.baseUrl.trim() == defaultBaseUrls[llm.protocol];
    // 换走时 token 不留在 Key 那一栏:它只能发给 xAI。
    if (_grok) _key = '';
    _rebuilds++;
    _put(
      llm.copyWith(
        protocol: protocol,
        baseUrl: untouched || protocol == protocolGrok
            ? defaultBaseUrls[protocol] ?? ''
            : null,
        model: llm.models.isNotEmpty
            ? null
            : switch (protocol) {
                protocolGrok => defaultGrokModel,
                protocolClaudeCode => 'opus',
                protocolCodex => cliDefaultModel,
                _ => null,
              },
      ),
      now: true,
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
    final on = widget.llm.enabled;
    return PennaCard(
      borderColor: on ? PennaColors.primaryBorder : PennaColors.border,
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, on),
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.expand,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 4, 8),
                    child: _body(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// 收起时也看得到的一行:拖动把手、序号、名字、协议、用的模型、开关。
  Widget _header(BuildContext context, bool on) {
    final models = llm.models;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _open = !_open),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: PennaColors.slate400,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 18,
            child: Text(
              '${widget.index + 1}',
              style: titleStyle.copyWith(
                color: on ? PennaColors.primary : PennaColors.slate400,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        llm.name.trim().isEmpty ? tr('未命名') : llm.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ProtocolBadge(protocol: llm.protocol, account: _account),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  models.isEmpty ? tr('未填模型') : models.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: models.isEmpty
                        ? PennaColors.amber
                        : PennaColors.slate500,
                  ),
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
              value: on,
              onChanged: (v) => service.update(
                service.config.putLlm(widget.llm.copyWith(enabled: v)),
              ),
            ),
          ),
          AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: Motion.of(context, Motion.base),
            child: Icon(
              Icons.expand_more,
              size: 20,
              color: PennaColors.slate500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _protocolRow('API Key', _apiProtocols),
      const SizedBox(height: 6),
      _protocolRow(tr('账号登录'), _accountProtocols),
      gap,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PennaField(
              key: ValueKey('name-$_rebuilds'),
              label: tr('显示名称'),
              value: llm.name,
              onChanged: (v) => _put(llm.copyWith(name: v)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: PennaField(
              key: ValueKey('limit-$_rebuilds'),
              label: tr('上下文上限(K)'),
              hint: tr('自动'),
              value: llm.contextLimit > 0 ? '${llm.contextLimit ~/ 1000}' : '',
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
      ..._credentials(),
      if (llm.protocol == protocolGoogle) ...[_tierRow(), gap],
      _modelsBlock(),
    ],
  );

  Widget _protocolRow(String title, List<String> protocols) => Row(
    children: [
      SizedBox(width: 72, child: Text(title, style: _labelStyle)),
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in protocols)
              PennaChip(
                label: _protocolLabels[p]!,
                selected: llm.protocol == p,
                onTap: () => _setProtocol(p),
              ),
          ],
        ),
      ),
    ],
  );

  /// Google 接口的用量档位:自动(不传)、Standard、Flex、Priority。
  /// Vertex Express 官方没写能选档位,灰着不能点。
  Widget _tierRow() {
    final transport = geminiTransport(llm.baseUrl);
    final supported = geminiTierSupported(llm.baseUrl);
    final tier = llm.serviceTier;
    final hint = !supported
        ? tr('Vertex Express 不能选档位,按标准处理')
        : switch (tier) {
            'standard' => tr('标准价'),
            'flex' when transport == GeminiTransport.vertexProject => tr(
              'Vertex 的 Flex 只支持 global 和 3.8 Flash 及更早的模型',
            ),
            'flex' => tr('便宜一半,要排队 1–15 分钟,忙时报 429 / 503'),
            'priority' => tr('更贵更稳;AI Studio 要 Tier 2 / 3'),
            _ => tr('不传档位,按标准处理'),
          };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: SizedBox(
            width: 72,
            child: Text(tr('用量档位'), style: _labelStyle),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: supported ? 1 : 0.45,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (value, label) in [
                      ('', tr('自动')),
                      ('standard', 'Standard'),
                      ('flex', 'Flex'),
                      ('priority', 'Priority'),
                    ])
                      PennaChip(
                        label: label,
                        selected: tier == value,
                        onTap: supported
                            ? () => _put(
                                llm.copyWith(serviceTier: value),
                                now: true,
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hint,
                style: TextStyle(fontSize: 11.5, color: PennaColors.slate500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 用 Key 的填地址和 Key;Grok 账号是登录行;订阅只写一句用本机的哪个。
  List<Widget> _credentials() => [
    if (_grok)
      GrokLoginRow(
        service: service,
        draft: _draft.copyWith(enabled: widget.llm.enabled),
      )
    else if (isCliProtocol(llm.protocol))
      Text(
        llm.protocol == protocolClaudeCode
            ? tr('用本机 Claude Code 登录的账号')
            : tr('用本机 Codex 登录的账号'),
        style: TextStyle(fontSize: 12, color: PennaColors.slate500),
      )
    else ...[
      PennaField(
        // 换协议会改默认地址,要重建输入框才显示得出来。
        key: ValueKey('url-$_rebuilds'),
        label: 'Base URL',
        hint: defaultBaseUrls[llm.protocol],
        value: llm.baseUrl,
        onChanged: (v) => _put(llm.copyWith(baseUrl: v)),
      ),
      gap,
      PennaField(
        key: ValueKey('key-$_rebuilds'),
        label: 'API Key',
        hint: tr('可留空'),
        obscure: true,
        value: _key,
        onChanged: (v) {
          _key = v;
          _later();
        },
      ),
    ],
    gap,
  ];

  /// 模型:按使用顺序一排,叉掉去掉,后面的输入框回车加;拉取后从列表里勾。
  Widget _modelsBlock() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(tr('模型'), style: _labelStyle),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, model) in llm.models.indexed)
            MentionChip(
              name: model,
              prefix: '${i + 1} · ',
              onRemove: () => _pick(model),
            ),
          _ModelAdder(
            hint: switch (llm.protocol) {
              protocolGoogle => 'gemini-2.5-flash',
              protocolGrok => 'grok-4.7',
              protocolClaudeCode => 'opus',
              protocolCodex => 'default',
              _ => 'gpt-4o-mini',
            },
            onAdd: _addModels,
          ),
        ],
      ),
      const SizedBox(height: 10),
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
              (_pullError ?? _testOk) ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: _pullError != null
                    ? PennaColors.diffDelText
                    : PennaColors.diffAddText,
              ),
            ),
          ),
          if (_models != null)
            PennaButton(
              label: tr('收起列表'),
              icon: Icons.expand_less,
              background: PennaColors.slate100,
              onPressed: () => setState(() => _models = null),
            ),
        ],
      ),
      if (_models != null) ...[
        const SizedBox(height: 8),
        _ModelList(
          models: _models!,
          selected: llm.models.toSet(),
          onPick: _pick,
        ),
      ],
    ],
  );
}

TextStyle get _labelStyle => TextStyle(
  fontSize: 11.5,
  fontWeight: FontWeight.w600,
  color: PennaColors.slate500,
);

/// 卡片标题旁的小标签:钥匙是 API Key,人像是账号登录。
class _ProtocolBadge extends StatelessWidget {
  const _ProtocolBadge({required this.protocol, required this.account});

  final String protocol;
  final bool account;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: account ? PennaColors.primaryBg : PennaColors.slate100,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          account ? Icons.person_outline : Icons.key_outlined,
          size: 12,
          color: account ? PennaColors.primary : PennaColors.slate500,
        ),
        const SizedBox(width: 4),
        Text(
          _protocolLabels[protocol] ?? protocol,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: account ? PennaColors.primary : PennaColors.slate700,
          ),
        ),
      ],
    ),
  );
}

/// 模型那一排最后的小输入框:回车把填的加进去。
class _ModelAdder extends StatefulWidget {
  const _ModelAdder({required this.hint, required this.onAdd});

  final String hint;
  final ValueChanged<String> onAdd;

  @override
  State<_ModelAdder> createState() => _ModelAdderState();
}

class _ModelAdderState extends State<_ModelAdder> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text.trim().isNotEmpty) widget.onAdd(text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: TextField(
      contextMenuBuilder: pennaTextMenu,
      controller: _controller,
      focusNode: _focus,
      onSubmitted: _submit,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: tr('+ 回车添加,如 {0}', [widget.hint]),
        hintStyle: TextStyle(color: PennaColors.slate400),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: PennaColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: PennaColors.border),
        ),
      ),
    ),
  );
}
