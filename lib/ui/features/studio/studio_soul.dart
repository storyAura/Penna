part of 'studio_view_model.dart';

/// PennaSoul(见 [SoulStore]):系统提示里带着记着的约定,
/// 用户提到角色时记次数,回复里的 `<soul-remember>` / `<soul-forget>` 说完时照做。
/// 工作台、区域控制、漫画分镜的对话和它们的副聊天都读、都记(2026-11-16 用户要求),
/// 用的是同一份 [SoulStore];副聊天借这里的 [soulGuide]、[noteSoulUses]、[applySoul]。
/// 是实验性功能,「设置 → 实验性功能」里打开才起作用(`AppConfig.soulOn`,默认关)。
extension StudioSoul on StudioViewModel {
  /// 接上了记忆并且开着。
  bool get soulOn => soul != null && config.config.soulOn;

  /// 系统提示里的【PennaSoul】;没开时是空的。
  String get soulGuide => soulOn ? soulPrompt(soul!.entries) : '';

  /// 用户这句话提到的角色各记一次(并进「常用角色」,不出提示条:平时不露面)。
  void noteSoulUses(ChatMessage message) {
    if (soulOn) soul!.noteCharacters(_mentioned(message).keys);
  }

  /// 照 [reply] 里的 PennaSoul 标签做:用户这句话 [asked] 明说了要记住才记上
  /// (回复下面的提示条读的是回复原文),没收下的标签从 [text] 里去掉;删的删掉。
  /// [note] 是要记在那条回复上的一句(删了哪几条),没删是 null。
  ({String text, String? note}) applySoul(String reply, String asked) {
    final found = splitSoul(reply);
    final keep = soulOn && askedToRemember(asked);
    final text = keep || found.remember.isEmpty
        ? reply
        : dropSoulRemember(reply);
    if (!soulOn) return (text: text, note: null);
    final store = soul!;
    if (keep) {
      for (final n in found.remember) {
        store.remember(n.kind, n.text);
      }
    }
    final gone = [
      for (final id in found.forget)
        ?store.entries.where((e) => e.id == id).firstOrNull,
    ];
    for (final e in gone) {
      store.forget(e.id);
    }
    return (
      text: text,
      note: gone.isEmpty
          ? null
          : tr('已从 PennaSoul 移除:{0}', [gone.map((e) => e.text).join(tr('、'))]),
    );
  }

  /// 主聊天这条回复里的 PennaSoul 标签。
  void _deliverSoul() {
    if (_messages.isEmpty) return;
    final asked =
        _messages.where((m) => m.fromUser && !m.tool).lastOrNull?.text ?? '';
    final done = applySoul(_messages.last.text, asked);
    if (done.text == _messages.last.text && done.note == null) return;
    _updateReply(
      (m) => m.copyWith(
        text: done.text,
        toolSummary: done.note == null
            ? m.toolSummary
            : [?m.toolSummary, done.note].join(' · '),
      ),
    );
  }
}
