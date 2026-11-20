part of 'studio_view_model.dart';

/// PennaSoul(见 [SoulStore]):系统提示里带着记着的约定和偏好,
/// 用户提到角色时记次数,回复里的 `<soul-remember>` / `<soul-forget>` 说完时照做。
/// 工作台、区域控制、漫画分镜的对话和它们的副聊天都读、都记(2026-11-16 用户要求),
/// 用的是同一份 [SoulStore];副聊天借这里的 [soulGuide]、[noteSoulUses]、[applySoul]。
// ponytail: 偏好只靠提示词起作用,程序不改推荐项的排序。
extension StudioSoul on StudioViewModel {
  /// 系统提示里的【PennaSoul】;没接上记忆时是空的。
  String get soulGuide =>
      soul == null ? '' : soulPrompt(soul!.entries, cast: soul!.cast);

  /// 用户这句话提到的角色各记一次(并进「常用角色」,不出提示条:平时不露面)。
  void noteSoulUses(ChatMessage message) =>
      soul?.noteCharacters(_mentioned(message).keys);

  /// 照 [reply] 里的 PennaSoul 标签做:记的记上(回复下面的提示条读的是回复原文),
  /// 删的删掉。返回要记在那条回复上的一句(删了哪几条),没删是 null。
  String? applySoul(String reply) {
    final store = soul;
    if (store == null) return null;
    final found = splitSoul(reply);
    for (final n in found.remember) {
      store.remember(n.kind, n.text);
    }
    final gone = [
      for (final id in found.forget)
        ?store.entries.where((e) => e.id == id).firstOrNull,
    ];
    if (gone.isEmpty) return null;
    for (final e in gone) {
      store.forget(e.id);
    }
    return tr('已从 PennaSoul 移除:{0}', [gone.map((e) => e.text).join(tr('、'))]);
  }

  /// 主聊天这条回复里的 PennaSoul 标签。
  void _deliverSoul() {
    if (_messages.isEmpty) return;
    final note = applySoul(_messages.last.text);
    if (note == null) return;
    _updateReply(
      (m) => m.copyWith(toolSummary: [?m.toolSummary, note].join(' · ')),
    );
  }
}
