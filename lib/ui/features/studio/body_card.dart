import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/harness/draft_block.dart';
import '../../../core/harness/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../layout/layout_json_view.dart';
import 'page_strip.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'body_diff.dart';
part 'body_editor.dart';
part 'body_pins.dart';
part 'body_section_card.dart';

TextStyle get draftLabelStyle => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: PennaColors.slate500,
);

typedef _Tint = ({Color bg, Color border, Color text});

/// 拖着的是哪一栏(blocks 里的起始下标)的第几段。
typedef _SectionDrag = ({int part, int span});

/// 分段框的配色,按段的先后轮着用;避开琥珀色,那是固定区的。
List<_Tint> get _sectionTints => PennaColors.isDark ? _darkTints : _lightTints;

const _lightTints = <_Tint>[
  (bg: Color(0xFFEFF6FF), border: Color(0xFFBFDBFE), text: Color(0xFF1D4ED8)),
  (bg: Color(0xFFECFDF5), border: Color(0xFFA7F3D0), text: Color(0xFF047857)),
  (bg: Color(0xFFF5F3FF), border: Color(0xFFDDD6FE), text: Color(0xFF6D28D9)),
  (bg: Color(0xFFFFF1F2), border: Color(0xFFFECDD3), text: Color(0xFFBE123C)),
  (bg: Color(0xFFECFEFF), border: Color(0xFFA5F3FC), text: Color(0xFF0E7490)),
  (bg: Color(0xFFFDF4FF), border: Color(0xFFF5D0FE), text: Color(0xFFA21CAF)),
];

const _darkTints = <_Tint>[
  (bg: Color(0xFF172238), border: Color(0xFF2B4270), text: Color(0xFF93B4FF)),
  (bg: Color(0xFF12291F), border: Color(0xFF225A41), text: Color(0xFF6EE7B7)),
  (bg: Color(0xFF221B36), border: Color(0xFF45366E), text: Color(0xFFC4B5FD)),
  (bg: Color(0xFF2C171C), border: Color(0xFF64303A), text: Color(0xFFFDA4AF)),
  (bg: Color(0xFF10272C), border: Color(0xFF1F5560), text: Color(0xFF67E8F9)),
  (bg: Color(0xFF2A1830), border: Color(0xFF5D3266), text: Color(0xFFF0ABFC)),
];

String get _labelHint => tr('例如 主体、服装、光影');

/// 没有标注的那段用的中性色。
_Tint get _plainTint => (
  bg: PennaColors.slate50,
  border: PennaColors.border,
  text: PennaColors.slate500,
);

/// 问用户要固定什么内容。点「添加」返回文字,取消返回 null。
Future<String?> showPinDialog(BuildContext context) {
  var text = '';
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('添加固定区'), style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: PennaField(
          label: tr('固定内容'),
          hint: tr('例如 masterpiece, best quality,'),
          maxLines: 3,
          value: '',
          onChanged: (v) => text = v,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, text),
          child: Text(tr('添加')),
        ),
      ],
    ),
  );
}

/// 成稿正文:平时是几栏可编辑文字和可拖动的固定区;
/// 有待确认改动时改为只读并显示 diff。
class BodyCard extends StatelessWidget {
  const BodyCard({
    super.key,
    required this.vm,
    this.onDiscuss,
    this.onPolish,
    this.onTranslate,
    this.onTranslateSelection,
    this.zhOpen = false,
    this.onCopied,
    this.onArchiveSeries,
  });

  /// 右键菜单的「翻译选中的」。
  final VoidCallback? onTranslateSelection;

  /// 去掉 [text] 里的 [s] 这一段,连同它和邻段之间的那个换行。
  static String _without(String text, SectionSpan s) => s.end < text.length
      ? text.replaceRange(s.start, s.end + 1, '')
      : text.replaceRange(s.start > 0 ? s.start - 1 : 0, s.end, '');

  final StudioViewModel vm;

  /// 页签上归档几个系列(存进档案库再从工作区删掉)。
  final void Function(Set<int> series)? onArchiveSeries;

  /// 顶栏的「展开」开着:每一段的中文对照都展开。
  final bool zhOpen;

  /// 用户复制了某一段之后。
  final VoidCallback? onCopied;

  /// 用户点了某一段的「润色」;参数是那段提示词在成稿里的范围。
  final void Function(int start, int end)? onPolish;

  /// 用户点了某一段的「翻译」;参数是那段的全文(带标注)和其中的提示词。
  final void Function(String section, String text)? onTranslate;

  /// 用户点了某一段的「讨论」;参数是那段文字(带标注)。
  final ValueChanged<String>? onDiscuss;

  /// 一栏可编辑文字:里面有分段标注就一段一个彩色框,没有就是一个普通输入栏。
  /// [tintFrom] 是这栏第一段该用第几个颜色。
  List<Widget> _column(
    BuildContext context,
    Part p,
    int partCount,
    int tintFrom,
  ) {
    _BodyEditor editor(
      String text,
      int at,
      int end,
      int minLines, {
      bool acceptPins = true,
      bool detach = false,
      VoidCallback? onEmpty,
    }) => _BodyEditor(
      body: text,
      minLines: minLines,
      acceptPins: acceptPins,
      onChanged: (t) => t.isEmpty && onEmpty != null
          ? onEmpty()
          : vm.setText(p.index, p.text.replaceRange(at, end, t)),
      onSelection: (range) => vm.bodySelection = range == null
          ? null
          : (p.offset + at + range.$1, p.offset + at + range.$2),
      onDropPin: (from, to) => vm.movePin(from, p.offset + at + to),
      // 选中一截文字后右键菜单里多出来的几项;「脱离」只有分段框里才有,
      // 「建立分段」只有普通文字里才有。
      selectionMenu: [
        (tr('固定选中的'), Icons.push_pin_outlined, vm.pinSelection),
        if (onPolish != null)
          (
            tr('润色选中的'),
            Icons.auto_fix_high,
            () {
              final range = vm.bodySelection;
              if (range != null) onPolish!(range.$1, range.$2);
            },
          ),
        if (onTranslateSelection != null)
          (tr('翻译选中的'), Icons.translate, onTranslateSelection!),
        if (detach) (tr('脱离选中的'), Icons.call_split, vm.detachSelection),
        if (!detach)
          (
            tr('建立分段'),
            Icons.dashboard_customize_outlined,
            () => _sectionSelection(context),
          ),
      ],
    );
    // 布局 JSON:按功能区分框看,但它仍是一整块文字,不拆成分段。
    final regions = layoutJsonRegions(p.text);
    if (regions != null && regions.isNotEmpty) {
      return [
        const SizedBox(height: 6),
        LayoutJsonColumn(
          text: p.text,
          regions: regions,
          style: monoStyle,
          editor: editor(p.text, 0, p.text.length, 6),
        ),
      ];
    }
    final spans = sectionSpans(p.text);
    if (spans.isEmpty) {
      return [
        const SizedBox(height: 6),
        editor(p.text, 0, p.text.length, partCount == 1 ? 6 : 1),
      ];
    }
    return [
      for (final (i, s) in spans.indexed) ...[
        const SizedBox(height: 6),
        // 固定区拖到一段上:插到这段前面。和上一段之间的换行留给这段。
        _DropSlot(
          onDrop: (from) =>
              vm.movePin(from, p.offset + s.start - (s.start > 0 ? 1 : 0)),
          // 同一栏里别的段拖到这段上:挪到这段的位置。
          section: (part: p.index, span: i),
          onDropSection: (from) => vm.moveSection(p.index, from, i),
          // 没有标注的(脱离了分段的)就是一栏普通文字,不画框;删空了这一处就没了。
          child: s.label.isEmpty
              ? editor(
                  p.text.substring(s.textStart, s.textEnd),
                  s.textStart,
                  s.textEnd,
                  1,
                  acceptPins: false,
                  onEmpty: () => vm.setText(p.index, _without(p.text, s)),
                )
              : _SectionCard(
                  leading: spans.length < 2
                      ? null
                      : _SectionHandle(
                          drag: (part: p.index, span: i),
                          label: s.label.isEmpty ? tr('未标注') : s.label,
                          tint: s.label.isEmpty
                              ? _plainTint
                              : _sectionTints[(tintFrom + i) %
                                    _sectionTints.length],
                        ),
                  label: s.label,
                  tint: s.label.isEmpty
                      ? _plainTint
                      : _sectionTints[(tintFrom + i) % _sectionTints.length],
                  zh: s.zh,
                  openAll: zhOpen,
                  onRename: () async {
                    final name = await askName(
                      context,
                      tr('分段的名字'),
                      s.label,
                      hint: _labelHint,
                    );
                    if (name == null || !context.mounted) return;
                    if (!vm.renameSection(p.index, i, name)) {
                      showToast(
                        context,
                        sectionLabel(name).isEmpty
                            ? tr('名字不能为空')
                            : tr('已经有叫这个名字的段了'),
                        warn: true,
                      );
                    }
                  },
                  copyText: p.text.substring(s.textStart, s.textEnd),
                  onCopied: onCopied,
                  quoted: vm.quote == p.text.substring(s.start, s.end),
                  onDiscuss: onDiscuss == null || s.textStart == s.textEnd
                      ? null
                      : () => onDiscuss!(p.text.substring(s.start, s.end)),
                  onDetach: s.textStart == s.textEnd
                      ? null
                      : () => vm.detachSection(p.index, i),
                  onPin: () => vm.pinSection(
                    p.offset + s.start,
                    p.offset + s.end,
                    p.text.substring(s.textStart, s.textEnd),
                  ),
                  onPolish: onPolish == null || s.textStart == s.textEnd
                      ? null
                      : () => onPolish!(
                          p.offset + s.textStart,
                          p.offset + s.textEnd,
                        ),
                  showTranslate: onTranslate != null,
                  onTranslate:
                      onTranslate == null ||
                          s.textStart == s.textEnd ||
                          vm.isTranslating
                      ? null
                      : () => onTranslate!(
                          p.text.substring(s.start, s.end),
                          p.text.substring(s.textStart, s.textEnd),
                        ),
                  onRemove: () => vm.setText(p.index, _without(p.text, s)),
                  child: editor(
                    p.text.substring(s.textStart, s.textEnd),
                    s.textStart,
                    s.textEnd,
                    1,
                    acceptPins: false,
                    detach: true,
                  ),
                ),
        ),
      ],
    ];
  }

  /// 把选中的普通文字建成一段:先问名字。问的时候输入框会失焦,选区先记下来。
  Future<void> _sectionSelection(BuildContext context) async {
    final selection = vm.bodySelection;
    final name = await askName(context, tr('新分段的名字'), '', hint: _labelHint);
    if (name == null || !context.mounted) return;
    vm.bodySelection = selection;
    if (sectionLabel(name).isEmpty) {
      showToast(context, tr('名字不能为空'), warn: true);
    } else if (vm.sectionNameTaken(name)) {
      showToast(context, tr('已经有叫这个名字的段了'), warn: true);
    } else if (!vm.sectionSelection(name)) {
      showToast(context, tr('只能把普通文字建成分段'), warn: true);
    }
  }

  /// 固定区。整段固定下来的还是原来那个分段框,只是罩上一层琥珀色、不能编辑;
  /// 别的是一条琥珀色的固定条。[tint] 是它该用第几个颜色,[live] 为假时不能拖也不能解除。
  Widget _pin(
    String text,
    int index,
    int offset,
    int tint, {
    bool live = true,
  }) {
    final s = text.startsWith('【') ? sectionSpans(text).firstOrNull : null;
    final onUnpin = live ? () => vm.unpin(index) : null;
    return _PinCard(
      text: s == null ? text : text.substring(s.textStart, s.textEnd),
      index: index,
      onUnpin: onUnpin,
      onDropPin: (from) => vm.movePin(from, offset),
      section: s == null
          ? null
          : _SectionCard(
              label: s.label,
              tint: _sectionTints[tint % _sectionTints.length],
              zh: s.zh,
              openAll: zhOpen,
              copyText: text.substring(s.textStart, s.textEnd),
              onCopied: onCopied,
              quoted: false,
              locked: true,
              onUnpin: onUnpin,
              child: Text(
                text.substring(s.textStart, s.textEnd),
                style: monoStyle,
              ),
            ),
    );
  }

  /// 只读的一段:有待确认改动时,没被改到的段照样是彩色框,只是不能编辑。
  Widget _readOnlySection(String text, SectionSpan s, int tint) => _SectionCard(
    label: s.label,
    tint: s.label.isEmpty
        ? _plainTint
        : _sectionTints[tint % _sectionTints.length],
    zh: s.zh,
    openAll: zhOpen,
    quoted: false,
    child: SelectableText(
      contextMenuBuilder: pennaTextMenu,
      text.substring(s.textStart, s.textEnd),
      style: monoStyle,
    ),
  );

  /// 不在改动范围里的一块文字,只读。返回它的组件和占了几个颜色。
  (List<Widget>, int) _readOnlyBlock(String text, int tintFrom) {
    final spans = sectionSpans(text);
    if (spans.isEmpty) {
      return (
        [
          const SizedBox(height: 6),
          SelectableText(
            contextMenuBuilder: pennaTextMenu,
            text,
            style: monoStyle,
          ),
        ],
        0,
      );
    }
    return (
      [
        for (final (i, s) in spans.indexed) ...[
          const SizedBox(height: 6),
          _readOnlySection(text, s, tintFrom + i),
        ],
      ],
      spans.length,
    );
  }

  /// 某一段自己的「采纳」「驳回」。
  List<Widget> _sectionActions(String label) => [
    PennaButton(
      label: tr('采纳'),
      background: PennaColors.diffAdd,
      foreground: PennaColors.diffAddText,
      onPressed: () => vm.acceptSection(label),
    ),
    const SizedBox(width: 4),
    PennaButton(
      label: tr('驳回'),
      background: PennaColors.diffDel,
      foreground: PennaColors.diffDelText,
      onPressed: () => vm.rejectSection(label),
    ),
  ];

  /// 待确认的那一块:按分段标注把改动前后对上,没变的段照常显示,
  /// 只有变了的段里出现红绿对比。返回组件和占了几个颜色。
  (List<Widget>, int) _pendingBlock(DiffProposal diff, int tintFrom) {
    final old = sectionSpans(diff.removed);
    final fresh = sectionSpans(diff.added);
    if (old.isEmpty && fresh.isEmpty) {
      return (
        [
          const SizedBox(height: 8),
          _DiffBlock(
            diff: diff,
            onAccept: vm.acceptDiff,
            onReject: vm.rejectDiff,
          ),
        ],
        0,
      );
    }
    // 先按改动前的顺序排,同标注的配成一对;改动后多出来的段接在最后。
    final unmatched = [...fresh];
    final pairs = <(SectionSpan?, SectionSpan?)>[
      for (final o in old)
        (
          o,
          switch (unmatched.indexWhere((n) => n.label == o.label)) {
            < 0 => null,
            final at => unmatched.removeAt(at),
          },
        ),
      for (final n in unmatched) (null, n),
    ];
    return (
      [
        const SizedBox(height: 8),
        _DiffHeader(
          diff: diff,
          onAccept: vm.acceptDiff,
          onReject: vm.rejectDiff,
          all: old.isNotEmpty,
        ),
        // 改动前是没分段的文字:整段算删掉。
        if (old.isEmpty && diff.removed.trim().isNotEmpty)
          ..._diffLines(diff.removed, ''),
        for (final (i, (before, after)) in pairs.indexed) ...[
          const SizedBox(height: 6),
          if (before != null &&
              after != null &&
              diff.removed.substring(before.start, before.end) ==
                  diff.added.substring(after.start, after.end))
            _readOnlySection(diff.added, after, tintFrom + i)
          else
            _SectionCard(
              label: (after ?? before)!.label,
              tint: (after ?? before)!.label.isEmpty
                  ? _plainTint
                  : _sectionTints[(tintFrom + i) % _sectionTints.length],
              zh: '',
              quoted: true,
              // 改动前就没分段时没法只换一段,只留上面总的那一对按钮。
              actions: old.isEmpty
                  ? const []
                  : _sectionActions((after ?? before)!.label),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _diffLines(
                  before == null
                      ? ''
                      : diff.removed.substring(before.start, before.end),
                  after == null
                      ? ''
                      : diff.added.substring(after.start, after.end),
                  strip: '【${(after ?? before)!.label}】',
                ),
              ),
            ),
        ],
      ],
      pairs.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = vm.pending;
    final parts = vm.parts;
    // 每一栏的第一段接着上一栏的颜色往下排,相邻两段不会撞色。
    var tint = 0;
    final columns = <Widget>[];
    if (pending == null) {
      for (final p in parts) {
        if (p.pinned) {
          columns
            ..add(const SizedBox(height: 6))
            ..add(_pin(p.text, p.index, p.offset, tint));
          if (p.text.startsWith('【')) tint++;
        } else {
          columns.addAll(_column(context, p, parts.length, tint));
          tint += sectionSpans(p.text).length;
        }
      }
      // 最下面留一条落点,固定区才拖得到最后。
      if (parts.any((p) => p.pinned)) {
        columns.add(
          _DropSlot(
            onDrop: (from) => vm.movePin(from, vm.body.length),
            child: const SizedBox(height: 14),
          ),
        );
      }
    } else {
      for (final (i, b) in vm.blocks.indexed) {
        if (b.pinned) {
          columns
            ..add(const SizedBox(height: 6))
            ..add(_pin(b.text, i, 0, tint, live: false));
          if (b.text.startsWith('【')) tint++;
          continue;
        }
        // 改动前后可能是空块(比如改的是开头或全文),不占位置。
        if (i != pending.segmentIndex && b.text.trim().isEmpty) continue;
        final (widgets, used) = i == pending.segmentIndex
            ? _pendingBlock(pending, tint)
            : _readOnlyBlock(b.text, tint);
        columns.addAll(widgets);
        tint += used;
      }
    }
    return PennaCard(
      radius: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageStrip(vm: vm, onArchive: onArchiveSeries),
          ...columns,
        ],
      ),
    );
  }
}
