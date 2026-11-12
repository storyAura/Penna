part of 'settings_llm_section.dart';

/// 「API 管理」放两栏时的总宽:左边接口卡片,右边 [_LlmHealthPanel]。
const llmSectionMaxWidth = 1100.0;

/// 窄到这个宽度以下,右栏挪到上面。
const _twoColumnsFrom = 980.0;

const _healthWidth = 320.0;

/// 一个模型的测试结果:[chat] / [search] 是 null 时还在测([searchable] 为假的不测搜索)。
typedef _Health = ({
  String name,
  String model,
  bool searchable,
  ProbeResult? chat,
  ProbeResult? search,
});

extension on _Health {
  bool get done => chat != null && (!searchable || search != null);
  bool get failed => chat?.error != null || search?.error != null;
}

/// 右栏:一次测全部启用的接口(每个模型的对话,能搜的接口再测联网),
/// 有问题的单独列在最上面,都写响应速度。2026-11-13 用户要求。
class _LlmHealthPanel extends StatefulWidget {
  const _LlmHealthPanel({required this.service});

  final ConfigService service;

  @override
  State<_LlmHealthPanel> createState() => _LlmHealthPanelState();
}

class _LlmHealthPanelState extends State<_LlmHealthPanel> {
  List<_Health> _rows = const [];
  bool _running = false;

  /// 每点一次加一;旧的那轮回来的结果不算。
  int _run = 0;

  Future<void> _testAll() async {
    final run = ++_run;
    final service = widget.service;
    final targets = [
      for (final llm in service.config.llms)
        if (llm.enabled)
          for (final (i, model) in llm.models.indexed)
            // 搜索只用接口里排第一的模型,所以只测它。
            (llm: llm, model: model, search: i == 0 && canWebSearch(llm)),
    ];
    setState(() {
      _running = true;
      _rows = [
        for (final t in targets)
          (
            name: t.llm.name.trim().isEmpty ? tr('未命名') : t.llm.name,
            model: t.model,
            searchable: t.search,
            chat: null,
            search: null,
          ),
      ];
    });
    void put(int i, _Health Function(_Health) change) {
      if (!mounted || run != _run) return;
      setState(() => _rows = [..._rows]..[i] = change(_rows[i]));
    }

    await Future.wait([
      for (final (i, t) in targets.indexed) ...[
        probeChat(probeRequest(service, t.llm, t.model), streamChat).then(
          (r) => put(
            i,
            (h) => (
              name: h.name,
              model: h.model,
              searchable: h.searchable,
              chat: r,
              search: h.search,
            ),
          ),
        ),
        if (t.search)
          probeSearch(probeRequest(service, t.llm, t.model), streamChat).then(
            (r) => put(
              i,
              (h) => (
                name: h.name,
                model: h.model,
                searchable: h.searchable,
                chat: h.chat,
                search: r,
              ),
            ),
          ),
      ],
    ]);
    if (mounted && run == _run) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final failed = [
      for (final h in _rows)
        if (h.failed) h,
    ];
    final waiting = [
      for (final h in _rows)
        if (!h.done && !h.failed) h,
    ];
    final fine = [
      for (final h in _rows)
        if (h.done && !h.failed) h,
    ]..sort((a, b) => a.chat!.ms!.compareTo(b.chat!.ms!));
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('全部测试'), style: titleStyle),
                    Text(tr('对话和联网搜索的响应速度'), style: hintStyle),
                  ],
                ),
              ),
              PennaButton(
                label: _running ? tr('测试中') : tr('开始'),
                icon: Icons.speed,
                background: PennaColors.primary,
                foreground: Colors.white,
                onPressed: _running ? null : _testAll,
              ),
            ],
          ),
          if (failed.isNotEmpty)
            _HealthGroup(
              title: tr('有问题 · {0}', [failed.length]),
              color: PennaColors.diffDelText,
              rows: failed,
            ),
          if (waiting.isNotEmpty)
            _HealthGroup(
              title: tr('测试中 · {0}', [waiting.length]),
              color: PennaColors.slate500,
              rows: waiting,
            ),
          if (fine.isNotEmpty)
            _HealthGroup(
              title: tr('正常 · {0}', [fine.length]),
              color: PennaColors.diffAddText,
              rows: fine,
            ),
        ],
      ),
    );
  }
}

class _HealthGroup extends StatelessWidget {
  const _HealthGroup({
    required this.title,
    required this.color,
    required this.rows,
  });

  final String title;
  final Color color;
  final List<_Health> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        for (final h in rows) _HealthRow(health: h),
      ],
    ),
  );
}

/// 一行:接口名和模型,下面是对话、联网各自的速度或出错原因。
class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.health});

  final _Health health;

  Widget _result(String what, ProbeResult? r) {
    final error = r?.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 34, child: Text(what, style: hintStyle)),
        Expanded(
          child: r == null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: PennaColors.slate400,
                    ),
                  ),
                )
              : Tooltip(
                  message: error ?? '',
                  child: Text(
                    error ?? formatMs(r.ms!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: error != null
                          ? PennaColors.diffDelText
                          : PennaColors.diffAddText,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: PennaColors.slate50,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          health.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        Text(health.model, overflow: TextOverflow.ellipsis, style: hintStyle),
        const SizedBox(height: 4),
        _result(tr('对话'), health.chat),
        if (health.searchable) _result(tr('联网'), health.search),
      ],
    ),
  );
}
