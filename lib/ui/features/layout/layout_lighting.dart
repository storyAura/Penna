part of 'layout_camera.dart';

/// 新灯和换色时用的色板、常用色温(照 lighting-kit)。
const _swatches = [
  '#ff3b30',
  '#ff9500',
  '#ffd60a',
  '#34c759',
  '#20c8ff',
  '#0a84ff',
  '#8e5cf7',
  '#ff2e88',
  '#ffffff',
];

/// 预设分组(22 个一长串不好找)。含 tr,所以是 getter。
List<(String, List<String>)> get _presetGroups => [
  (
    tr('人像'),
    [
      'natural',
      'rembrandt',
      'butterfly',
      'loop',
      'split',
      'three_point',
      'rim',
      'high_key',
      'low_key',
    ],
  ),
  (
    tr('自然与时段'),
    ['window', 'overcast', 'golden_hour', 'blue_hour', 'noon', 'moonlight'],
  ),
  (
    tr('氛围'),
    ['backlight', 'silhouette', 'top', 'under', 'neon', 'candle', 'spotlight'],
  ),
];

/// 灯光窗口:开关、预设、跟随镜头、光影预览、灯光球(拖手柄改方向)、选中那盏灯的参数、
/// 环境光和氛围;最下面是交出去时接在整体描述后的那句。本质是一句光影提示词,
/// 球和手柄只是方便看(用户要求;Agent 用 `<lighting>` 改同一份)。
class _LightingSection extends StatefulWidget {
  const _LightingSection({required this.board});

  final LayoutBoard board;

  @override
  State<_LightingSection> createState() => _LightingSectionState();
}

class _LightingSectionState extends State<_LightingSection> {
  /// 选中的那盏灯;没选过或被删了就是第一盏。
  String? _picked;

  LayoutBoard get board => widget.board;
  Lighting get lg => board.layout.lighting;
  Camera get cam => board.layout.camera;

  void _put(Lighting next, [String? action]) =>
      board.setLighting(next, action: action);

  /// 一行参数,拖动时只在开始那一帧记操作。
  Widget _dial(
    String label,
    double value,
    String unit,
    double step,
    double perPx,
    Lighting Function(double) apply,
  ) => _Dial(
    label: label,
    value: value,
    unit: unit,
    step: step,
    perPx: perPx,
    onStart: () => board.mark(tr('调整灯光')),
    onEnd: () => board.mark(null),
    onChanged: (v, {required bool step}) =>
        _put(apply(v), step ? tr('调整灯光') : null),
  );

  /// 预设格子展开着没有。
  bool _presets = false;

  @override
  Widget build(BuildContext context) {
    final on = lg.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 和摄像机窗口的标题一样高。
        SizedBox(
          height: 34,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.wb_sunny_outlined, size: 15, color: PennaColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tr('灯光'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: on,
                  onChanged: (v) => _put(
                    enableLighting(lg, v, cam),
                    v ? tr('打开灯光') : tr('关掉灯光'),
                  ),
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.expand,
          alignment: Alignment.topCenter,
          child: on
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _body(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 套用预设,收起预设格子。
  void _apply(String id) {
    _picked = null;
    _presets = false;
    _put(presetLighting(id, cam, lg), tr('套用灯光预设'));
  }

  List<Widget> _body() {
    final lights = lg.lights;
    final sel =
        lights.where((l) => l.id == _picked).firstOrNull ?? lights.firstOrNull;
    final preset = findPreset(lg.preset);
    final phrase = lightingPhrase(lg, cam, zh: isCjk(board.layout.caption));
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Tooltip(
          message: tr('打光预设'),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _presets = !_presets),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: PennaColors.slate50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: PennaColors.border),
              ),
              child: Row(
                children: [
                  if (preset != null) ...[
                    _PresetThumb(id: preset.id, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      preset == null ? tr('自定义') : tr(preset.name),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _presets ? 0.5 : 0,
                    duration: Motion.of(context, Motion.base),
                    curve: Motion.swift,
                    child: Icon(
                      Icons.expand_more,
                      size: 15,
                      color: PennaColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: Motion.of(context, Motion.base),
        curve: Motion.expand,
        alignment: Alignment.topCenter,
        child: _presets
            ? _PresetGrid(selected: lg.preset, onPick: _apply)
            : const SizedBox(width: double.infinity),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(
          spacing: 6,
          children: [
            Tooltip(
              message: lg.follow ? tr('灯跟着镜头转') : tr('灯固定在场景里,转镜头时光线相对画面会变'),
              child: PennaChip(
                label: tr('跟随镜头'),
                selected: lg.follow,
                onTap: () => _put(setFollow(lg, !lg.follow, cam), tr('调整灯光')),
              ),
            ),
            ValueListenableBuilder(
              valueListenable: board.shadePreview,
              builder: (context, on, _) => Tooltip(
                message: tr('体块和画布按灯光显示明暗'),
                child: PennaChip(
                  label: tr('光影预览'),
                  selected: on,
                  onTap: () => board.shadePreview.value = !on,
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: _LightBall(
          lighting: lg,
          camera: cam,
          selected: sel?.id,
          onPick: (id) => setState(() => _picked = id),
          onStart: () => board.mark(tr('拖动灯光')),
          onMove: (id, a) => _put(
            updateLight(lg, id, {
              'azimuth': a.azimuth,
              'elevation': a.elevation,
            }),
          ),
          onEnd: () => board.mark(null),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (i, l) in lights.indexed)
              PennaChip(
                label: '${i + 1} ${tr(lightRoleInfo[l.role]!.zh)}',
                selected: l.id == sel?.id,
                onTap: () => setState(() => _picked = l.id),
              ),
            if (lights.length < maxLights)
              PopupMenuButton<String>(
                popUpAnimationStyle: Motion.menu(context),
                tooltip: tr('加一盏灯'),
                icon: const Icon(Icons.add, size: 16),
                padding: EdgeInsets.zero,
                onSelected: (role) {
                  final next = addLight(lg, role, cam);
                  _picked = next.lights.last.id;
                  _put(next, tr('加一盏灯'));
                },
                itemBuilder: (_) => [
                  for (final r in lightRoles)
                    PopupMenuItem(
                      value: r,
                      height: 32,
                      child: Text(
                        tr(lightRoleInfo[r]!.zh),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      if (sel != null) ..._lightRows(sel),
      const SizedBox(height: 4),
      _dial(
        tr('环境光'),
        lg.ambient,
        '',
        0.05,
        0.003,
        (v) => lg.patch({'ambient': v}),
      ),
      _dial(
        tr('环境色温'),
        lg.ambientKelvin.toDouble(),
        'K',
        500,
        20,
        (v) => lg.patch({'ambient_kelvin': v}),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in lightExtras)
              PennaChip(
                label: tr(e.label),
                selected: lg.extras.contains(e.id),
                onTap: () => _put(toggleExtra(lg, e.id), tr('调整灯光')),
              ),
          ],
        ),
      ),
      if (phrase.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Tooltip(
            message: tr('导出时接在整体描述后面'),
            child: SelectableText(
              phrase,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: PennaColors.slate500,
              ),
            ),
          ),
        ),
    ];
  }

  /// 选中那盏灯的参数:方位(相对镜头)、高度、强度、软硬、色温或颜色,能删、能换角色。
  List<Widget> _lightRows(Light l) {
    final rel = relDir(l, lg, cam);
    Lighting set(Map<String, Object?> f) => updateLight(lg, l.id, f);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                popUpAnimationStyle: Motion.menu(context),
                tooltip: tr('换角色'),
                onSelected: (r) => _put(set({'role': r}), tr('调整灯光')),
                itemBuilder: (_) => [
                  for (final r in lightRoles)
                    PopupMenuItem(
                      value: r,
                      height: 32,
                      child: Text(
                        tr(lightRoleInfo[r]!.zh),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(
                          int.parse(l.color.substring(1), radix: 16) |
                              0xFF000000,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: PennaColors.border),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        directionText(rel.h, rel.v, zh: true),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: PennaColors.slate700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 14,
                      color: PennaColors.slate500,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: tr('删掉这盏灯'),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _put(removeLight(lg, l.id), tr('删掉一盏灯')),
            ),
          ],
        ),
      ),
      _dial(
        tr('方位'),
        rel.h,
        '°',
        15,
        0.5,
        (v) => set({'azimuth': toStoredAzimuth(v, lg, cam)}),
      ),
      _dial(tr('高度'), l.elevation, '°', 5, 0.3, (v) => set({'elevation': v})),
      _dial(
        tr('强度'),
        l.intensity,
        '',
        0.1,
        0.005,
        (v) => set({'intensity': v}),
      ),
      _dial(tr('软硬'), l.softness, '', 0.05, 0.003, (v) => set({'softness': v})),
      _dial(
        tr('色温'),
        (l.kelvin ?? 6500).toDouble(),
        'K',
        100,
        20,
        (v) => set({'kelvin': v}),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final c in _swatches)
              Tooltip(
                message: tr('彩色灯'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () =>
                      _put(set({'kelvin': null, 'color': c}), tr('调整灯光')),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse(c.substring(1), radix: 16) | 0xFF000000,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: l.kelvin == null && l.color == c
                            ? PennaColors.text
                            : PennaColors.border,
                        width: l.kelvin == null && l.color == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

/// 预设格子:按组排,一格是预设的小灯光球加名字,点一下套用。
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({required this.selected, required this.onPick});

  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (group, ids) in _presetGroups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4, left: 2),
              child: Text(
                group,
                style: TextStyle(fontSize: 10.5, color: PennaColors.slate500),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in ids)
                  if (findPreset(id) case final p?)
                    _PresetTile(
                      preset: p,
                      selected: p.id == selected,
                      onTap: () => onPick(p.id),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final LightPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        curve: Motion.swift,
        width: 66,
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 5),
        decoration: BoxDecoration(
          color: selected ? PennaColors.primaryBg : PennaColors.slate50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? PennaColors.primary : PennaColors.border,
          ),
        ),
        child: Column(
          children: [
            _PresetThumb(id: preset.id, size: 32),
            const SizedBox(height: 4),
            Text(
              tr(preset.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? PennaColors.primary : PennaColors.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预设的小灯光球(默认镜头下看):算一次就记着,不跟着每一帧重画。
class _PresetThumb extends StatefulWidget {
  const _PresetThumb({required this.id, required this.size});

  final String id;
  final double size;

  @override
  State<_PresetThumb> createState() => _PresetThumbState();
}

class _PresetThumbState extends State<_PresetThumb> {
  static final _cache = <String, ui.Image>{};

  @override
  Widget build(BuildContext context) {
    final px = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(16, 128);
    final key = '${widget.id}@$px';
    final img = _cache[key];
    if (img == null) {
      ui.decodeImageFromPixels(
        renderLitSphere(px, presetLighting(widget.id, null), null),
        px,
        px,
        ui.PixelFormat.rgba8888,
        (image) {
          _cache[key] = image;
          if (mounted) setState(() {});
        },
      );
    }
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        color: Color(0xFF2B2824),
        shape: BoxShape.circle,
      ),
      child: img == null
          ? null
          : RawImage(
              image: img,
              width: widget.size,
              height: widget.size,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
