import 'package:flutter/foundation.dart';

import '../../../core/harness/attachment.dart';
import '../../../l10n/l10n.dart';

@immutable
class ChatMessage {
  const ChatMessage({
    required this.fromUser,
    required this.text,
    required this.time,
    this.toolSummary,
    this.toolDetails = const [],
    this.failed = false,
    this.stopped = false,
    this.by,
    this.skillIds = const [],
    this.attachments = const [],
    this.quote,
    this.tool = false,
  });

  /// 这条不是用户写的,是程序替模型查回来的资料(标签搜索结果)。
  /// 发给模型时和用户消息一样走,界面上只显示成一行可展开的记录。
  final bool tool;

  /// 用户发这条消息时选中的那段成稿(带标注);这轮只讨论它。
  final String? quote;

  /// 这条回复是被用户打断的,可能只有半截。
  final bool stopped;

  /// 用户发这条消息时用 @ 引用的 Skill。
  final List<String> skillIds;

  /// 用户随这条消息附上的图片和文本文件。
  final List<Attachment> attachments;

  final bool fromUser;
  final String text;
  final DateTime time;
  final String? toolSummary;
  final List<String> toolDetails;

  /// 这条回复以出错告终;不再作为历史发给模型。
  final bool failed;

  /// 这条回复出自哪个模型(显示名)。
  final String? by;

  ChatMessage copyWith({
    String? text,
    bool? failed,
    bool? stopped,
    String? by,
    String? toolSummary,
    List<String>? toolDetails,
  }) => ChatMessage(
    fromUser: fromUser,
    text: text ?? this.text,
    time: time,
    failed: failed ?? this.failed,
    stopped: stopped ?? this.stopped,
    by: by ?? this.by,
    skillIds: skillIds,
    attachments: attachments,
    quote: quote,
    tool: tool,
    toolSummary: toolSummary ?? this.toolSummary,
    toolDetails: toolDetails ?? this.toolDetails,
  );

  /// 存盘用。给了 [files] 才存附件(另存成文件,这里只记文件名)。
  Map<String, dynamic> toJson({AttachmentFiles? files}) => {
    if (files != null && attachments.isNotEmpty)
      'attachments': [for (final a in attachments) files.put(a)],
    'fromUser': fromUser,
    'text': text,
    'time': time.toIso8601String(),
    if (failed) 'failed': true,
    if (stopped) 'stopped': true,
    'by': ?by,
    if (skillIds.isNotEmpty) 'skillIds': skillIds,
    'quote': ?quote,
    if (tool) 'tool': true,
    'toolSummary': ?toolSummary,
  };

  /// 附件的文件没了的就不带上。
  factory ChatMessage.fromJson(
    Map<String, dynamic> j, {
    AttachmentFiles? files,
  }) => ChatMessage(
    attachments: files == null
        ? const []
        : List.unmodifiable([
            for (final a in (j['attachments'] as List?) ?? const [])
              ?files.get(a),
          ]),
    fromUser: j['fromUser'] as bool,
    text: j['text'] as String,
    time: DateTime.parse(j['time'] as String),
    failed: j['failed'] == true,
    stopped: j['stopped'] == true,
    by: j['by'] as String?,
    skillIds: List.unmodifiable(((j['skillIds'] as List?) ?? const []).cast()),
    quote: j['quote'] as String?,
    tool: j['tool'] == true,
    toolSummary: j['toolSummary'] as String?,
  );
}

/// 对话里显示的一行:一条消息,加上写它之前查标签的那几次记录。
typedef ChatRow = ({int index, ChatMessage message, List<ChatMessage> lookups});

/// 把查标签的中间步骤收起来:查了几轮,都列在最后那条回复上面,不各占一行。
/// 只是为了要查标签而发的那条回复(后面紧跟着查询结果)不显示。
List<ChatRow> foldLookups(List<ChatMessage> messages) {
  final rows = <ChatRow>[];
  var lookups = const <ChatMessage>[];
  for (final (i, m) in messages.indexed) {
    if (m.tool) {
      lookups = [...lookups, m];
    } else if (m.fromUser ||
        i + 1 == messages.length ||
        !messages[i + 1].tool) {
      rows.add((index: i, message: m, lookups: lookups));
      lookups = const [];
    }
  }
  return rows;
}

/// 一场对话的名字:用户说的第一句话的第一行;还没说话就是「新对话」。
String chatTitle(List<ChatMessage> messages) {
  final first = messages
      .where((m) => m.fromUser && !m.tool && m.text.trim().isNotEmpty)
      .firstOrNull;
  if (first == null) return messages.isEmpty ? tr('新对话') : tr('未命名');
  return first.text.trim().split('\n').first;
}

/// 一场收起来的对话。
typedef ChatSession = ({String id, List<ChatMessage> messages});

/// 历史提示词里的一条:当时的成稿(带分段标注)。
typedef PromptRecord = ({DateTime time, String text});
