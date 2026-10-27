import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/look_switcher.dart';
import '../../core/theme.dart';
import '../../core/version.dart';
import '../../core/widgets.dart';
import '../update/update_flow.dart';
import 'settings_agent_sections.dart';
import 'settings_sections.dart';

/// 软件设置分区最宽多少:够宽时右边另起一栏放对话相关的开关。
const appSectionMaxWidth = 1200.0;

/// 宽于这个就分两栏,窄了右栏接在下面。
const _twoColumnsAt = 1000.0;

/// 「软件设置」:界面语言、深色模式、字体与头像、版本与更新、关于;
/// 右栏是对话相关的开关。
class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.service});

  final ConfigService service;

  @override
  Widget build(BuildContext context) {
    final left = _general();
    final right = _ChatOptions(service: service);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < _twoColumnsAt
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, gap, right],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 20),
                Expanded(flex: 2, child: right),
              ],
            ),
    );
  }

  Widget _general() {
    final cfg = service.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('软件设置'), tr('语言、外观与版本')),
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('界面语言'), style: titleStyle),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final l in languages)
                    PennaButton(
                      label: l.name,
                      icon: l.code == cfg.language ? Icons.check : null,
                      background: l.code == cfg.language
                          ? PennaColors.primaryBg
                          : null,
                      foreground: l.code == cfg.language
                          ? PennaColors.primary
                          : null,
                      borderColor: l.code == cfg.language
                          ? PennaColors.primaryBorder
                          : PennaColors.border,
                      onPressed: () => service.update(
                        service.config.copyWith(language: l.code),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('界面大小'), style: titleStyle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in uiScales)
                    PennaChip(
                      label: '${(s * 100).round()}%',
                      selected: s == cfg.uiScale,
                      onTap: () =>
                          service.update(service.config.copyWith(uiScale: s)),
                    ),
                ],
              ),
            ],
          ),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text(tr('深色模式'), style: titleStyle)),
              Builder(
                builder: (context) => Switch(
                  value: cfg.darkMode,
                  onChanged: (v) {
                    // 动画从开关这里扩散开。
                    final box = context.findRenderObject() as RenderBox?;
                    if (box != null && box.hasSize) {
                      lookRevealOrigin = box.localToGlobal(
                        box.size.center(Offset.zero),
                      );
                    }
                    service.update(service.config.copyWith(darkMode: v));
                  },
                ),
              ),
            ],
          ),
        ),
        gap,
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(tr('字体与头像 · 可填任意已安装的字体名'), style: hintStyle),
        ),
        _Appearance(service: service),
        gap,
        UpdateCard(service: service),
        gap,
        const _About(),
      ],
    );
  }
}

/// 「内置角色预览图」先藏起来(用户要求):预览图仓库还没建,开了也下不到图。
/// 建好仓库后改成 true 就回来了,设置里的值和译文都还留着。
const _characterPreviewsReady = false;

/// 右栏:对话相关的开关(压缩大图、自动审批,内置角色预览图先藏着)和区域控制的分辨率对齐。
class _ChatOptions extends StatelessWidget {
  const _ChatOptions({required this.service});

  final ConfigService service;

  Widget _toggle(
    String title,
    String hint,
    bool value,
    ValueChanged<bool> on,
  ) => PennaCard(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              Text(hint, style: hintStyle),
            ],
          ),
        ),
        Switch(value: value, onChanged: on),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(tr('对话'), tr('图片与成稿')),
        _toggle(
          tr('压缩大图'),
          tr('超过 1 MB 的图片缩到 2048 像素以内,转为 WebP'),
          cfg.compressImages,
          (v) => service.update(service.config.copyWith(compressImages: v)),
        ),
        gap,
        _toggle(
          tr('自动审批'),
          tr('成稿的改动直接采纳'),
          cfg.autoApprove,
          (v) => service.update(service.config.copyWith(autoApprove: v)),
        ),
        if (_characterPreviewsReady) ...[
          gap,
          _toggle(
            tr('内置角色预览图'),
            tr('角色库下载内置角色的图'),
            cfg.characterPreviews,
            (v) =>
                service.update(service.config.copyWith(characterPreviews: v)),
          ),
        ],
        gap,
        SectionHeading(tr('区域控制'), tr('画布尺寸')),
        _LayoutSnapCard(
          value: cfg.layoutSnap,
          onChanged: (v) =>
              service.update(service.config.copyWith(layoutSnap: v)),
        ),
      ],
    );
  }
}

/// 分辨率对齐:几个常用的倍数点一下就换,也能自己填(1 到 [maxLayoutSnap])。
class _LayoutSnapCard extends StatefulWidget {
  const _LayoutSnapCard({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_LayoutSnapCard> createState() => _LayoutSnapCardState();
}

class _LayoutSnapCardState extends State<_LayoutSnapCard> {
  static const _common = [8, 16, 32, 64];

  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(_LayoutSnapCard old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _controller.text = '${widget.value}';
  }

  /// 填的数读不了时放回原来的,超出范围的截到范围里。
  void _submit() {
    final v = int.tryParse(_controller.text.trim());
    if (v == null) {
      _controller.text = '${widget.value}';
      return;
    }
    final got = v.clamp(minLayoutSnap, maxLayoutSnap);
    _controller.text = '$got';
    if (got != widget.value) widget.onChanged(got);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: PennaColors.border),
    );
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('分辨率对齐'), style: titleStyle),
          Text(tr('画布宽高取它的倍数'), style: hintStyle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final n in _common)
                PennaChip(
                  label: '$n px',
                  selected: widget.value == n,
                  onTap: () => widget.onChanged(n),
                ),
              Tooltip(
                message: tr('1 为不对齐'),
                child: SizedBox(
                  width: 64,
                  child: TextField(
                    contextMenuBuilder: pennaTextMenu,
                    controller: _controller,
                    focusNode: _focus,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: PennaColors.card,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: border,
                      enabledBorder: border,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 关于:名字、版本、仓库地址、许可。
class _About extends StatelessWidget {
  const _About();

  static const _repo = 'https://github.com/storyAura/Penna';

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/avatar.png', width: 40, height: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Penna 羽毛笔', style: titleStyle),
                const SizedBox(height: 2),
                Text(
                  tr('文生图提示词工作台 · v{0} · MIT 许可', [appVersion]),
                  style: hintStyle,
                ),
              ],
            ),
          ),
          PennaButton(
            label: 'GitHub',
            icon: Icons.open_in_new,
            borderColor: PennaColors.border,
            // 交给系统用默认浏览器打开。
            onPressed: () => Process.run(
              Platform.isWindows ? 'rundll32' : 'xdg-open',
              Platform.isWindows
                  ? ['url.dll,FileProtocolHandler', _repo]
                  : [_repo],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _FontChoice = ({String label, String family});

List<_FontChoice> get _latinChoices => [
  (label: tr('内置 · Maple Mono'), family: ''),
  (label: 'Segoe UI', family: 'Segoe UI'),
  (label: 'Consolas', family: 'Consolas'),
  (label: 'Cascadia Mono', family: 'Cascadia Mono'),
];

List<_FontChoice> get _cjkChoices => [
  (label: tr('内置 · 霞鹜 975 圆体'), family: ''),
  (label: tr('微软雅黑'), family: 'Microsoft YaHei UI'),
  (label: tr('等线'), family: 'DengXian'),
  (label: tr('楷体'), family: 'KaiTi'),
];

/// 外观:英文、中文字体各选各的。
/// 外观:字体、头像、预览。
class _Appearance extends StatelessWidget {
  const _Appearance({required this.service});

  final ConfigService service;

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FontPicker(
          title: tr('英文字体'),
          value: cfg.fontLatin,
          choices: _latinChoices,
          onChanged: (v) =>
              service.update(service.config.copyWith(fontLatin: v)),
        ),
        gap,
        _FontPicker(
          title: tr('中文字体'),
          value: cfg.fontCjk,
          choices: _cjkChoices,
          onChanged: (v) => service.update(service.config.copyWith(fontCjk: v)),
        ),
        gap,
        PennaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('头像'), style: titleStyle),
              const SizedBox(height: 10),
              _AvatarRow(
                name: 'Penna Agent',
                fromUser: false,
                path: cfg.agentAvatar,
                onChanged: (v) =>
                    service.update(service.config.copyWith(agentAvatar: v)),
              ),
              const SizedBox(height: 10),
              _AvatarRow(
                name: tr('用户'),
                fromUser: true,
                path: cfg.userAvatar,
                onChanged: (v) =>
                    service.update(service.config.copyWith(userAvatar: v)),
              ),
            ],
          ),
        ),
        gap,
        PennaCard(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('预览'), style: hintStyle),
              SizedBox(height: 6),
              Text(
                'Penna 羽毛笔 · 文生图提示词工作台\n'
                'A cybernetic android walking in the rain, 35mm, ISO 400.\n'
                '0123456789 , . ( ) { } -> =>',
                style: TextStyle(fontSize: 14, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一个头像的设置行:预览、换图、恢复默认。
// ponytail: 只记图片的路径,图片被挪走或删掉就变回默认头像;
// 要不受影响的话,选图时把它复制进「文档\Penna」。
class _AvatarRow extends StatelessWidget {
  const _AvatarRow({
    required this.name,
    required this.fromUser,
    required this.path,
    required this.onChanged,
  });

  final String name;
  final bool fromUser;
  final String path;
  final ValueChanged<String> onChanged;

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('图片'), extensions: ['png', 'jpg', 'jpeg', 'webp']),
      ],
    );
    if (picked != null) onChanged(picked.path);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PennaAvatar(fromUser: fromUser, path: path, size: 40),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
        if (path.isNotEmpty) ...[
          PennaButton(label: tr('恢复默认'), onPressed: () => onChanged('')),
          const SizedBox(width: 6),
        ],
        PennaButton(
          label: tr('换图片'),
          icon: Icons.image_outlined,
          background: PennaColors.slate100,
          onPressed: _pick,
        ),
      ],
    );
  }
}

class _FontPicker extends StatefulWidget {
  const _FontPicker({
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String title;
  final String value;
  final List<_FontChoice> choices;
  final ValueChanged<String> onChanged;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  /// 点了药丸后加一,让下面的输入框跟着显示新字体名。
  int _picks = 0;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: titleStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.choices)
                PennaChip(
                  label: c.label,
                  selected: widget.value == c.family,
                  onTap: () {
                    setState(() => _picks++);
                    widget.onChanged(c.family);
                  },
                ),
            ],
          ),
          gap,
          PennaField(
            key: ValueKey(_picks),
            label: tr('自定义'),
            hint: tr('字体名'),
            value: widget.value,
            onChanged: (v) => widget.onChanged(v.trim()),
          ),
        ],
      ),
    );
  }
}
