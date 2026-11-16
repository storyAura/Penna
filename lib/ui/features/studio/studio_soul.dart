part of 'studio_view_model.dart';

/// PennaSoul(见 [SoulStore]):系统提示里带着记着的约定和偏好,
/// 用户提到角色时记次数,回复里的 `<soul-remember>` / `<soul-forget>` 说完时照做。
// ponytail: 副聊天、漫画分镜的对话不带也不记;偏好只靠提示词起作用,程序不改推荐项的排序。
extension StudioSoul on StudioViewModel {
  /// 系统提示里的【PennaSoul】;没接上记忆时是空的。
  String get _soulPrompt => soul == null ? '' : soulPrompt(soul!.entries);

  /// 用户这句话提到的角色各记一次(够数的记成偏好,不出提示条:平时不露面)。
  void _noteSoulUses(ChatMessage message) {
    final store = soul;
    if (store == null) return;
    store.noteCharacters(_mentioned(message).keys);
  }

  /// 回复里的 PennaSoul 标签:记的记上(回复下面的提示条读的是回复原文),
  /// 删的删掉并在回复上记一笔。
  void _deliverSoul() {
    final store = soul;
    if (store == null || _messages.isEmpty) return;
    final found = splitSoul(_messages.last.text);
    for (final n in found.remember) {
      store.remember(n.kind, n.text);
    }
    final gone = [
      for (final id in found.forget)
        ?store.entries.where((e) => e.id == id).firstOrNull,
    ];
    if (gone.isEmpty) return;
    for (final e in gone) {
      store.forget(e.id);
    }
    _updateReply(
      (m) => m.copyWith(
        toolSummary: [
          ?m.toolSummary,
          tr('已从 PennaSoul 移除:{0}', [gone.map((e) => e.text).join(tr('、'))]),
        ].join(' · '),
      ),
    );
  }
}
