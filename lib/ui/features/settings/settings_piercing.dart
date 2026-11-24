import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/preset_dialogue.dart';
import '../../../core/harness/preset_import/sillytavern_preset.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_agent_sections.dart' show hintStyle;
import 'settings_sections.dart';

/// 穿甲弹的三种模式:提示词、文档、工具调用(2026-11-25 用户要求工具调用从 Preset 挪过来)。
enum PiercingMode { prompt, document, tool }

PiercingMode piercingModeOf(AppConfig cfg) => cfg.piercingDocument
    ? PiercingMode.document
    : cfg.piercingTool
    ? PiercingMode.tool
    : PiercingMode.prompt;

/// 换成 [mode]:文档和工具调用互斥。
AppConfig withPiercingMode(AppConfig cfg, PiercingMode mode) => cfg.copyWith(
  piercingDocument: mode == PiercingMode.document,
  piercingTool: mode == PiercingMode.tool,
);

/// 换成存下的 [name] 那段穿甲弹(侧栏的闪电和设置页共用)。
AppConfig withPiercing(AppConfig cfg, String name) {
  final hit = cfg.piercingSaved.where((p) => p.name == name).firstOrNull;
  return hit == null
      ? cfg
      : cfg.copyWith(piercingName: hit.name, piercingPrompt: hit.text);
}

/// 新名字撞了就接数字(「名字 2」「名字 3」…)。
String freshPiercingName(AppConfig cfg, String name) {
  final taken = {for (final p in cfg.piercingSaved) p.name};
  if (!taken.contains(name)) return name;
  var n = 2;
  while (taken.contains('$name $n')) {
    n++;
  }
  return '$name $n';
}

/// 穿甲弹:一段接在所有 Preset 系统提示最前面的话,默认关。能存几段、在它们之间切换,
/// 能导入文本和 SillyTavern 预设,能预览对话标记拆出来的样子。
/// 文字先改在草稿里,点「保存」才写进设置。
class PiercingCard extends StatefulWidget {
  const PiercingCard({super.key, required this.service});

  final ConfigService service;

  @override
  State<PiercingCard> createState() => _PiercingCardState();
}

class _PiercingCardState extends State<PiercingCard> {
  ConfigService get service => widget.service;

  late String _draft = service.config.piercingPrompt;

  /// 输入框靠它重建来显示换进来的文字。
  int _reloads = 0;

  bool _preview = false;

  bool get _dirty => _draft != service.config.piercingPrompt;

  @override
  void dispose() {
    // 换到别的分区时卡片会被拆掉:没保存的改动替用户存上,不悄悄丢掉。
    if (_dirty) {
      final cfg = _saved(service.config, _draft);
      Future.microtask(() => service.update(cfg));
    }
    super.dispose();
  }

  /// 把 [text] 存成眼前这段(还没存过的起个名字)。
  AppConfig _saved(AppConfig cfg, String text) {
    final name = cfg.piercingName.isNotEmpty
        ? cfg.piercingName
        : freshPiercingName(cfg, tr('穿甲弹 {0}', [cfg.piercingSaved.length + 1]));
    final has = cfg.piercingSaved.any((p) => p.name == name);
    return cfg.copyWith(
      piercingPrompt: text,
      piercingName: name,
      piercingSaved: [
        for (final p in cfg.piercingSaved)
          p.name == name ? (name: name, text: text) : p,
        if (!has) (name: name, text: text),
      ],
    );
  }

  void _show(String text) => setState(() {
    _draft = text;
    _reloads++;
  });

  Future<void> _save() async {
    service.update(_saved(service.config, _draft));
    await service.flushed();
    if (!mounted) return;
    setState(() {});
    final error = service.lastError;
    showToast(context, error ?? tr('已保存'), warn: error != null);
  }

  void _switch(String name) {
    var cfg = service.config;
    if (_dirty) cfg = _saved(cfg, _draft);
    cfg = withPiercing(cfg, name);
    service.update(cfg);
    _show(cfg.piercingPrompt);
  }

  /// 新加一段:[text] 是它的文字,起名撞了接数字。
  void _add(String name, String text) {
    var cfg = service.config;
    if (_dirty) cfg = _saved(cfg, _draft);
    final fresh = freshPiercingName(cfg, name);
    service.update(
      cfg.copyWith(
        piercingSaved: [...cfg.piercingSaved, (name: fresh, text: text)],
        piercingName: fresh,
        piercingPrompt: text,
      ),
    );
    _show(text);
  }

  Future<void> _create() async {
    final name = await askName(context, tr('新建穿甲弹'), '');
    if (name == null || !mounted) return;
    _add(
      name.trim().isEmpty
          ? tr('穿甲弹 {0}', [service.config.piercingSaved.length + 1])
          : name.trim(),
      '',
    );
  }

  Future<void> _rename() async {
    final cfg = service.config;
    final old = cfg.piercingName;
    final asked = await askName(context, tr('改名'), old);
    final name = asked?.trim() ?? '';
    if (name.isEmpty || name == old || !mounted) return;
    final fresh = freshPiercingName(cfg, name);
    service.update(
      cfg.copyWith(
        piercingName: fresh,
        piercingSaved: [
          for (final p in cfg.piercingSaved)
            p.name == old ? (name: fresh, text: p.text) : p,
        ],
      ),
    );
  }

  void _delete() {
    final cfg = service.config;
    final left = [
      for (final p in cfg.piercingSaved)
        if (p.name != cfg.piercingName) p,
    ];
    // 工具调用模式删掉后回到「不用预设」。
    final next = cfg.piercingTool ? null : left.firstOrNull;
    service.update(
      cfg.copyWith(
        piercingSaved: left,
        piercingName: next?.name ?? '',
        piercingPrompt: next?.text ?? '',
        piercing: (next != null || cfg.piercingTool) && cfg.piercing,
      ),
    );
    _show(next?.text ?? '');
  }

  Future<File?> _pick(String label, List<String> extensions) async {
    final picked = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)],
    );
    return picked == null ? null : File(picked.path);
  }

  /// 文本文件:读进草稿,点「保存」才存。
  Future<void> _importText() async {
    final file = await _pick(tr('文本'), ['txt', 'md']);
    if (file == null) return;
    try {
      final text = await file.readAsString();
      if (mounted) _show(text);
    } on Exception {
      if (mounted) showToast(context, tr('读不了这个文件'), warn: true);
    }
  }

  /// SillyTavern 的 Chat Completion 预设:条目拼成一段,谁说的、聊天记录在哪写成对话标记,
  /// 存成新的一段(名字取文件名)。
  Future<void> _importTavern() async {
    final file = await _pick(tr('SillyTavern 预设'), ['json']);
    if (file == null) return;
    try {
      final text = sillyTavernToPrompt(jsonDecode(await file.readAsString()));
      if (!mounted) return;
      final name = file.uri.pathSegments.last.replaceFirst(
        RegExp(r'\.json$', caseSensitive: false),
        '',
      );
      _add(name, text);
      setState(() => _preview = true);
      showToast(context, tr('已导入「{0}」', [name]));
    } on FormatException {
      if (mounted) showToast(context, tr('这不是 SillyTavern 预设'), warn: true);
    } on Exception {
      if (mounted) showToast(context, tr('读不了这个文件'), warn: true);
    }
  }

  Future<void> _export() async {
    final at = await getSaveLocation(
      suggestedName: '${service.config.piercingName.ifEmpty('piercing')}.txt',
      acceptedTypeGroups: [
        XTypeGroup(label: tr('文本'), extensions: ['txt']),
      ],
    );
    if (at == null) return;
    try {
      await File(at.path).writeAsString(_draft);
      if (mounted) showToast(context, tr('已导出'));
    } on FileSystemException {
      if (mounted) showToast(context, tr('写不进这个位置'), warn: true);
    }
  }

  /// 换模式。工具调用是一种规范的做法,本身不用写字(2026-11-25 用户纠正):换过去时
  /// 不带提示词,导入过 SillyTavern 预设的可以再挑一个;换回提示词模式时没挑就用第一段。
  void _mode(PiercingMode m) {
    var cfg = service.config;
    if (_dirty) cfg = _saved(cfg, _draft);
    cfg = withPiercingMode(cfg, m);
    if (m == PiercingMode.tool) {
      cfg = cfg.copyWith(piercingName: '', piercingPrompt: '');
    } else if (cfg.piercingName.isEmpty && cfg.piercingSaved.isNotEmpty) {
      cfg = withPiercing(cfg, cfg.piercingSaved.first.name);
    }
    service.update(cfg);
    _show(cfg.piercingPrompt);
  }

  /// 工具调用模式:默认不带预设;导入的 SillyTavern 预设能挑一个用、预览、删掉,不编辑。
  List<Widget> _toolMode(AppConfig cfg, Color small) {
    final picked = cfg.piercingName.isNotEmpty;
    return [
      gap,
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          PennaChip(
            label: tr('不用预设'),
            selected: !picked,
            onTap: () {
              service.update(
                service.config.copyWith(piercingName: '', piercingPrompt: ''),
              );
              _show('');
            },
          ),
          for (final p in cfg.piercingSaved)
            PennaChip(
              label: p.name,
              selected: p.name == cfg.piercingName,
              onTap: () => _switch(p.name),
            ),
        ],
      ),
      gap,
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          PennaButton(
            label: tr('导入 SillyTavern 预设'),
            icon: Icons.download_outlined,
            background: small,
            onPressed: _importTavern,
          ),
          if (picked) ...[
            PennaButton(
              label: tr('预览'),
              icon: _preview
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              background: _preview ? PennaColors.primaryBg : small,
              onPressed: () => setState(() => _preview = !_preview),
            ),
            PennaButton(
              label: tr('删除'),
              icon: Icons.delete_outline,
              background: small,
              onPressed: _delete,
            ),
          ],
        ],
      ),
      if (picked && _preview) ...[
        gap,
        PiercingPreview(text: cfg.piercingPrompt),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cfg = service.config;
    final mode = piercingModeOf(cfg);
    final small = PennaColors.slate100;
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
                    Text(tr('穿甲弹'), style: titleStyle),
                    Text(tr('所有 Preset 共用'), style: hintStyle),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: cfg.piercing,
                  onChanged: (on) =>
                      service.update(service.config.copyWith(piercing: on)),
                ),
              ),
            ],
          ),
          gap,
          Row(
            children: [
              for (final (m, label) in [
                (PiercingMode.prompt, tr('提示词')),
                (PiercingMode.document, tr('文档')),
                (PiercingMode.tool, tr('工具调用')),
              ]) ...[
                PennaChip(
                  label: label,
                  selected: mode == m,
                  onTap: () => _mode(m),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  switch (mode) {
                    PiercingMode.prompt => tr('接在系统提示最前面'),
                    PiercingMode.document => tr('对话以文档收发'),
                    PiercingMode.tool => tr('回复写进工具参数 · OpenAI 兼容、Google 接口'),
                  },
                  overflow: TextOverflow.ellipsis,
                  style: hintStyle,
                ),
              ),
            ],
          ),
          if (mode == PiercingMode.tool) ..._toolMode(cfg, small),
          if (mode == PiercingMode.prompt) ...[
            gap,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in cfg.piercingSaved)
                        PennaChip(
                          label: p.name,
                          selected: p.name == cfg.piercingName,
                          onTap: () => _switch(p.name),
                        ),
                      PennaChip(
                        label: tr('+ 新建'),
                        selected: false,
                        onTap: _create,
                      ),
                    ],
                  ),
                ),
                if (cfg.piercingSaved.any(
                  (p) => p.name == cfg.piercingName,
                )) ...[
                  IconButton(
                    tooltip: tr('改名'),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: _rename,
                  ),
                  IconButton(
                    tooltip: tr('删除'),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _delete,
                  ),
                ],
              ],
            ),
            gap,
            PennaField(
              key: ValueKey('piercing-$_reloads'),
              label: tr('提示词'),
              hint: tr('可用 <<user>>、<<assistant>>、<<history>> 写成几轮对话'),
              maxLines: 6,
              value: _draft,
              onChanged: (v) => setState(() => _draft = v),
            ),
            gap,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PennaButton(
                  label: tr('保存'),
                  icon: Icons.check,
                  background: _dirty ? PennaColors.primary : small,
                  foreground: _dirty ? Colors.white : null,
                  onPressed: _dirty ? _save : null,
                ),
                PennaButton(
                  label: tr('导入文本'),
                  icon: Icons.file_open_outlined,
                  background: small,
                  onPressed: _importText,
                ),
                PennaButton(
                  label: tr('导入 SillyTavern 预设'),
                  icon: Icons.download_outlined,
                  background: small,
                  onPressed: _importTavern,
                ),
                PennaButton(
                  label: tr('导出'),
                  icon: Icons.save_alt,
                  background: small,
                  onPressed: _export,
                ),
                PennaButton(
                  label: tr('预览'),
                  icon: _preview
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  background: _preview ? PennaColors.primaryBg : small,
                  onPressed: () => setState(() => _preview = !_preview),
                ),
              ],
            ),
            if (_preview) ...[gap, PiercingPreview(text: _draft)],
          ],
        ],
      ),
    );
  }
}

/// 穿甲弹发出去的样子:系统提示、事先说好的几轮、聊天记录的位置、用户这次的话。
class PiercingPreview extends StatelessWidget {
  const PiercingPreview({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final d = presetDialogue(text);
    final rows = <(String, String?)>[
      if (d == null && text.trim().isNotEmpty) (tr('系统提示'), text.trim()),
      if (d != null && d.lead.isNotEmpty) (tr('系统提示'), d.lead),
      for (final t in d?.head ?? const <PresetTurn>[])
        (_role(t.role), t.content),
      (tr('聊天记录'), null),
      for (final t in d?.tail ?? const <PresetTurn>[])
        (_role(t.role), t.content),
      (tr('用户这次的话'), null),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PennaColors.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PennaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (who, body)) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    who,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: body == null
                          ? PennaColors.slate400
                          : PennaColors.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    body ?? '—',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: body == null
                          ? PennaColors.slate400
                          : PennaColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _role(String role) => role == 'user' ? tr('用户') : tr('模型');
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
