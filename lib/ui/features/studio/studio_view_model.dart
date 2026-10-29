import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/chat_peek.dart';
import '../../../core/harness/characters/character_dict.dart';
import '../../../core/harness/characters/character_mentions.dart';
import '../../../core/harness/draft_block.dart';
import '../../../core/harness/layout.dart';
import '../../../core/harness/local/local_tools.dart';
import '../../../core/harness/providers/llm_router.dart';
import '../../../core/harness/providers/openai_provider.dart';
import '../../../core/harness/tags/tag_dictionary.dart';
import '../../../core/harness/tags/tag_search.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/character_store.dart';
import '../../../data/services/config_service.dart';
import '../../../data/services/skill_store.dart';
import '../../../data/services/translate_chain.dart';
import '../../../data/services/translate_engines.dart';
import '../layout/layout_board.dart';
import '../local/local_model.dart';
import 'chat_message.dart';
import 'side_chat.dart';
import '../../../l10n/l10n.dart';

export 'chat_message.dart';

part 'studio_auto_lookup.dart';
part 'studio_chat.dart';
part 'studio_context.dart';
part 'studio_draft.dart';
part 'studio_history.dart';
part 'studio_layout_pages.dart';
part 'studio_pages.dart';
part 'studio_rewrite.dart';
part 'studio_storage.dart';

/// 成稿的一块文字。[pinned] 为真时是固定区:润色和 Agent 都改不到它。
typedef Block = ({String text, bool pinned});

/// 排着队还没发出去的一条用户消息。
typedef QueuedMessage = ({
  String text,
  List<String> skillIds,
  List<Attachment> attachments,
  String? quote,
});

/// 操作记录里的一笔:什么时候,做了什么,做之前、做之后工作台的样子。
/// 记录是一棵树:每一笔记着做它时眼前是哪一笔之后([parent]),回到前面再做别的,
/// 原来那几笔就成了另一个分支,还能切回去(见 [StudioHistory])。
@immutable
class ActionRecord {
  const ActionRecord._({
    required this.id,
    required this.time,
    required this.text,
    required this.parent,
    required _Snapshot before,
    this.details = const [],
    _Snapshot? after,
    // 命名参数不能带下划线,写不成 this._before。
    // ignore: prefer_initializing_formals
  }) : _before = before,
       // ignore: prefer_initializing_formals
       _after = after;

  final int id;
  final DateTime time;
  final String text;

  /// 合成这一笔的那几步(Agent 一条回复里新开页、起名、采纳……);只有一步时是空的。
  final List<String> details;

  /// 做这一步时眼前是哪一笔之后的样子;null 是最开始(或那一笔已经太旧、删掉了)。
  final int? parent;

  final _Snapshot _before;

  /// 做完之后的样子。眼前这一笔的就是现在,换走时才补上,所以可能是 null。
  final _Snapshot? _after;

  ActionRecord _withAfter(_Snapshot after) => ActionRecord._(
    id: id,
    time: time,
    text: text,
    parent: parent,
    before: _before,
    details: details,
    after: after,
  );
}

/// 一笔记录和眼前的关系。
enum ActionState {
  /// 眼前就是做完这一笔之后的样子。
  current,

  /// 走到眼前之前做过的。
  done,

  /// 从眼前往后做过、又撤回来的(「回到这一步之后」能重做)。
  undone,

  /// 别的分支上的:回到前面以后又做了别的,它们留在原来那条路上。
  branch,
}

const _maxActions = 100;

/// 某一刻工作台的样子(成稿各页、系列、对话),回滚时整个换回去。
typedef _Snapshot = ({
  List<DraftPage> pages,
  int page,
  Map<int, String> seriesNames,
  Map<int, ChatSession> seriesChats,
  List<ChatMessage> messages,
  String chatId,
  List<ChatSession> archive,
  Set<String> closedTabs,
});

/// 界面上的一栏:一个固定区,或一段连着的可编辑文字。
/// [index] 是它在 blocks 里的起始下标,[offset] 是它在 body 里的起始位置。
typedef Part = ({int index, int offset, String text, bool pinned});

/// 一处待确认的改动:把成稿第 [segmentIndex] 块从 [removed] 换成 [added]。
@immutable
class DiffProposal {
  const DiffProposal({
    required this.title,
    required this.segmentIndex,
    required this.removed,
    required this.added,
  });

  final String title;
  final int segmentIndex;
  final String removed;
  final String added;
}

/// 工作台状态:成稿是唯一交付物,Agent 的改动必须先成为 diff 再由用户确认。
class StudioViewModel extends ChangeNotifier {
  StudioViewModel({
    required this.config,
    required this.streamChat,
    this.translate = translateWithConfig,
    this.skills,
    List<Block> blocks = const [],
    this.tags = '',
    String? translation,
    this._pending,
    List<ChatMessage> messages = const [],
    this.saveFile,
    this.tagSearch,
    this.tagDictionary,
    this.characters,
    this.characterDict,
    this.layout,
    this.layoutOnly = false,
  }) : _blocks = List.unmodifiable(blocks),
       _messages = List.unmodifiable(messages) {
    if (saveFile != null) addListener(_scheduleSave);
    if (layoutOnly) layout?.addListener(_boardListener);
  }

  /// 区域控制那场对话(`layoutOnly`)里每一页的成稿就是一张布局,画板摆的是眼前这一页
  /// (见 [StudioLayoutPages])。[_boardText] 是画板和眼前这页最近一次对上时的内容,
  /// 还没对过是 null。
  String? _boardText;
  void _boardListener() => _pullBoard();

  /// 替模型查 Danbooru 标签的函数;为 null 时模型要查也不理(测试里换成假的)。
  final TagSearcher? tagSearch;

  /// 内置词库,用来核对模型最后写出来的标签是不是真的有。
  final TagDictionary? tagDictionary;

  /// 角色库:用户自己存的角色,和内置的 Danbooru 角色。模型要查、要存时用;
  /// 两个都没有就不理它的 `<search-character>` / `<save-character>`。
  final CharacterStore? characters;
  final CharacterDict? characterDict;

  /// 布局画板:模型看得到它的画布尺寸和现有的框,写出的 `<layout>` 放到这里;
  /// 没有就不提布局,也不理 `<layout>`。
  final LayoutBoard? layout;

  /// 本地反推:Agent 写 `<reverse-image>`、`<download-model>` 时由它来跑。
  /// 本地反推页和工作台都建好之后才接上(`main()`、`AppShell`),所以不是 final;
  /// 没有就不提本地反推,也不理这两个标签。
  LocalModel? local;

  /// 区域控制工作台的那场对话(`layoutOnly`)。主工作区的 Agent 写 `<ask-layout>` 时,
  /// 把活转给它,等它把布局放到画板上,再把 JSON 拿回主工作区的新系列。
  /// 和 [local] 一样建好之后才接上;没有就由主工作区的 Agent 自己写 `<layout>`。
  StudioViewModel? layoutAgent;

  /// 副聊天(另一个模型,只读工作区)。主聊天的 Agent 写 `<read-side-chat>` 时读它的记录;
  /// 同样建好之后才接上,布局页的对话没有。
  SideChat? side;

  /// 布局页右边那场对话用的:系统提示只讲布局,回复里的 `<layout>` 放到 [layout] 上,
  /// 不往成稿里送。界面和工作台的对话是同一个 `ChatPane`。
  final bool layoutOnly;

  /// 工作台存盘的文件(「文档/Penna/workspace.json」);为 null 时不存(测试用)。
  final File? saveFile;

  /// 消息附件另存的文件夹:[saveFile] 旁边的 attachments\<存档名>\(两场对话各一个,
  /// 清理时互不相干)。不存盘时是 null。
  /// 从用户的话里认内置角色名(程序替模型先查角色库用),第一次用时才建索引。
  late final CharacterMentions? _mentions = characterDict == null
      ? null
      : CharacterMentions(characterDict!, tags: tagDictionary);

  late final AttachmentFiles? _files = () {
    final file = saveFile;
    if (file == null) return null;
    final sep = Platform.pathSeparator;
    final name = file.uri.pathSegments.last.replaceFirst(
      RegExp(r'\.json$'),
      '',
    );
    return AttachmentFiles(
      Directory('${file.parent.path}${sep}attachments$sep$name'),
    );
  }();

  Timer? _saveTimer;

  /// 有改动就过一小会儿存一次;生成回复时先不存,结束时那次通知会补上。
  void _scheduleSave() {
    if (isStreaming) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  void _saveNow() {
    _saveTimer = null;
    final file = saveFile;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // 先写临时文件再改名:中途断电也不会留下半截的文件。
      File('${file.path}.tmp')
        ..writeAsStringSync(jsonEncode(toJson()), flush: true)
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      // 这次没存上,下次有改动会再试。
      debugPrint(tr('保存工作台失败:{0}', [e.message]));
    }
  }

  /// 成稿的各页;眼前这一页([_page])的内容在 [_blocks] 这几个字段里,
  /// 这里它那一格是旧的,换页时才写回去。见 [StudioPages]。
  List<DraftPage> _pages = const [_blankPage];
  int _page = 0;

  /// 不在眼前的那些系列各自的对话。
  Map<int, ChatSession> _seriesChats = const {};

  /// 起过名字的系列;没起的显示成「系列 N」。
  Map<int, String> _seriesNames = const {};

  /// Agent 要另起系列却满了时的提醒(见 [StudioPages.seriesAlert])。
  String? _seriesAlert;

  void _changed() {
    if (layoutOnly) _syncBoard();
    notifyListeners();
  }

  /// 操作记录,新的在前;只留在内存里,关掉程序就没了。怎么记、怎么回到某一步见 [StudioHistory]。
  // ponytail: 不存盘,关掉程序就不能回滚了;打字不记,回到某一步时那之后手打的字跟着那一步走
  // (换走时眼前的样子记在当前这一笔的「之后」里,切回来还在)。
  List<ActionRecord> _actions = const [];
  List<ActionRecord> get actions => _actions;

  /// 眼前是哪一笔做完之后的样子;null 是最开始(还没做,或回到了最早那一笔之前)。
  int? _head;

  int _nextActionId = 0;

  /// 正在把几笔合成一笔时(见 [StudioHistory._asOneStep]),各步的说明先攒在这里。
  List<String>? _steps;

  /// 眼前这一页叫什么,记操作时用:「系列 1 · 第 2 页」。
  String get _here =>
      tr('{0} · 第 {1} 页', [seriesName(series), pageNumber(_page)]);

  String _chatId = _newId();
  List<ChatSession> _archive = const [];

  /// 用户在标签行上关掉的那些对话(只是不占标签了,历史里还在)。
  Set<String> _closedTabs = const {};

  List<PromptRecord> _promptLog = const [];

  /// 历史提示词,新的在前。最多留 [_maxPrompts] 条。
  List<PromptRecord> get promptLog => _promptLog;

  final ConfigService config;
  final ChatStreamer streamChat;
  final ConfigTranslator translate;

  /// 用户导入的 Skill;没有就不往系统提示里加东西。
  final SkillStore? skills;

  final String tags;

  String? _translation;
  String? _translationBy;
  bool _translating = false;

  /// 成稿的中文对照,以及它出自哪个引擎(显示名)。
  String? get translation => _translation;
  String? get translationBy => _translationBy;
  bool get isTranslating => _translating;

  List<Block> _blocks;
  DiffProposal? _pending;
  List<ChatMessage> _messages;
  StreamSubscription<String>? _reply;

  List<Block> get blocks => _blocks;
  DiffProposal? get pending => _pending;

  /// 眼前这场对话的编号:换了对话(新对话、打开历史、换系列)就变。
  String get chatId => _chatId;

  /// 排在 [pending] 后面等确认的改动(成稿被固定区隔成几栏时,每栏一处)。
  List<DiffProposal> _queued = const [];
  int get queuedDiffs => _queued.length;

  /// 所有还没确认的改动里要换上去的文字,用来看某份成稿是不是已经在等确认了。
  String get pendingAdded =>
      [?_pending, ..._queued].map((d) => d.added).join('\n');

  List<ChatMessage> get messages => _messages;
  bool get isStreaming => _reply != null || _toolBusy;

  /// 成稿编辑框里当前选中的范围(起、止,按 body 数);由编辑框随时报上来。
  (int, int)? bodySelection;

  bool _polishing = false;
  bool get isPolishing => _polishing;

  String? _quote;

  /// 用户选来和 Agent 讨论的那段成稿(带标注);随下一条消息发出。
  String? get quote => _quote;

  /// 生成回复时用户又发来的话,排着队等这条说完;只在内存里。
  List<QueuedMessage> _outbox = const [];
  List<QueuedMessage> get outbox => _outbox;

  bool _toolBusy = false;

  /// 每开始或作废一次查标签就加一,用来丢掉迟到的结果。
  int _toolRun = 0;

  /// 用户这一条消息之后已经查了几轮;封顶,免得模型没完没了地查。
  int _toolRounds = 0;

  /// 这一轮里查回来过的标签(标准写法)。
  final _foundTags = <String>{};

  bool _disposed = false;

  void _updateReply(ChatMessage Function(ChatMessage) change) {
    _messages = List.unmodifiable([
      ..._messages.take(_messages.length - 1),
      change(_messages.last),
    ]);
    notifyListeners();
  }

  void _finishReply() {
    _reply = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (layoutOnly) layout?.removeListener(_boardListener);
    // 还有没落盘的改动就趁现在存掉。
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow();
    }
    unawaited(_reply?.cancel());
    _reply = null;
    super.dispose();
  }
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

const _maxChats = 50;
const _maxPrompts = 100;
