import 'package:flutter/foundation.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/providers/llm_http.dart';
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
    this.usage,
    this.otherReplies = const [],
    this.replyAt = 0,
    this.cut,
    this.images = const [],
  });

  /// 这条回复让 ComfyUI 出的图(文件路径,在「设置 → ComfyUI」的图片位置里)。
  /// 只给用户看,不发给模型。
  final List<String> images;

  /// 这条回复没写完的原因;写完了、接口没说时是 null。
  final LlmCut? cut;

  /// 重新回复时另存的那几份:每份是这条消息后面的全部内容(可能带着查资料的几轮)。
  /// 不含眼前显示的那一份,它排在 [replyAt] 这个位置。
  final List<List<ChatMessage>> otherReplies;
  final int replyAt;

  /// 这条回复用了多少 token(接口报了才有)。
  final LlmUsage? usage;

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
    LlmUsage? usage,
    List<List<ChatMessage>>? otherReplies,
    int? replyAt,
    LlmCut? cut,
    List<String>? images,
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
    usage: usage ?? this.usage,
    otherReplies: otherReplies ?? this.otherReplies,
    replyAt: replyAt ?? this.replyAt,
    cut: cut ?? this.cut,
    images: images ?? this.images,
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
    if (usage case final u?)
      'usage': {'input': u.input, 'cached': u.cached, 'output': u.output},
    'cut': ?cut?.name,
    if (images.isNotEmpty) 'images': images,
    if (otherReplies.isNotEmpty) ...{
      'otherReplies': [
        for (final reply in otherReplies)
          [for (final m in reply) m.toJson(files: files)],
      ],
      'replyAt': replyAt,
    },
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
    usage: switch (j['usage']) {
      {'input': final int i, 'cached': final int c, 'output': final int o} => (
        input: i,
        cached: c,
        output: o,
      ),
      _ => null,
    },
    otherReplies: List.unmodifiable([
      for (final reply in (j['otherReplies'] as List?) ?? const [])
        List<ChatMessage>.unmodifiable([
          for (final m in reply as List)
            ChatMessage.fromJson(m as Map<String, dynamic>, files: files),
        ]),
    ]),
    replyAt: j['replyAt'] as int? ?? 0,
    cut: LlmCut.values.asNameMap()[j['cut']],
    images: List.unmodifiable(((j['images'] as List?) ?? const []).cast()),
  );
}

/// 重新回复时从哪条消息后面重来:最后一条查询结果也算,查过的资料不用再查一遍
/// (转区域控制、本地反推再跑一次还会多出东西)。这一轮已经另存过回复时,
/// 回到存着它们的那一条:新的回复可能又查了几轮,这时最后一条已经往后挪了。
int replyAnchor(List<ChatMessage> messages) {
  final ask = messages.lastIndexWhere((m) => m.fromUser && !m.tool);
  if (ask >= 0) {
    for (var i = ask; i < messages.length; i++) {
      if (messages[i].otherReplies.isNotEmpty) return i;
    }
  }
  return messages.lastIndexWhere((m) => m.fromUser);
}

/// 第几份(从 0 数)、一共几份;只有一份时是 null。
({int at, int total})? replyPager(List<ChatMessage> messages) {
  final at = replyAnchor(messages);
  if (at < 0 || messages[at].otherReplies.isEmpty) return null;
  final anchor = messages[at];
  return (at: anchor.replyAt, total: anchor.otherReplies.length + 1);
}

/// 全部几份回复,按先后排,眼前这份也在里面。
List<List<ChatMessage>> _allReplies(List<ChatMessage> messages, int at) {
  final anchor = messages[at];
  return [
    ...anchor.otherReplies.take(anchor.replyAt),
    messages.sublist(at + 1),
    ...anchor.otherReplies.skip(anchor.replyAt),
  ];
}

/// 要重新回复时的上文:眼前这份回复收起来,新写的排在最后。
/// 出错的、一个字没写就停了的不留。还没有可以回复的消息时是 null。
// ponytail: 只有最新一轮能翻;发了下一条之后,旧的几份还存着但翻不到了,
// 因为换掉中间的回复,后面的对话就对不上了。要翻得做成分支。
List<ChatMessage>? retryHistory(List<ChatMessage> messages) {
  final at = replyAnchor(messages);
  if (at < 0) return null;
  final all = [
    for (final reply in _allReplies(messages, at))
      if (reply.isNotEmpty && !reply.last.failed && reply.last.text.isNotEmpty)
        reply,
  ];
  return [
    ...messages.take(at),
    messages[at].copyWith(
      otherReplies: List.unmodifiable(all),
      replyAt: all.length,
    ),
  ];
}

/// 换成第 [index] 份回复(从 0 数)。
List<ChatMessage> showReply(List<ChatMessage> messages, int index) {
  final at = replyAnchor(messages);
  if (at < 0) return messages;
  final all = _allReplies(messages, at);
  if (index < 0 || index >= all.length) return messages;
  return [
    ...messages.take(at),
    messages[at].copyWith(
      otherReplies: List.unmodifiable([
        for (final (i, reply) in all.indexed)
          if (i != index) reply,
      ]),
      replyAt: index,
    ),
    ...all[index],
  ];
}

/// 用户改了第 [index] 条消息后的上文:它后面的都不要了,附件、引用的 Skill 和段照旧。
/// 算一条新消息,所以时间是 [time],另存的回复也不带。不是用户自己写的消息时是 null。
List<ChatMessage>? editedHistory(
  List<ChatMessage> messages,
  int index,
  String text,
  DateTime time,
) {
  if (index < 0 || index >= messages.length) return null;
  final m = messages[index];
  if (!m.fromUser || m.tool) return null;
  return [
    ...messages.take(index),
    ChatMessage(
      fromUser: true,
      text: text,
      time: time,
      skillIds: m.skillIds,
      attachments: m.attachments,
      quote: m.quote,
    ),
  ];
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
