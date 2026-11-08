part of 'studio_view_model.dart';

/// Agent 换工作流时写的标签。
const comfyWorkflowTag = 'comfy-workflow';

/// Agent 出图:回复里写了 `<generate-image>`,程序交给 ComfyUI,出的图贴回那条回复;
/// 写了 `<comfy-workflow>` 就先换工作流(用户要换模型时,换成用那个模型的工作流)。
extension StudioComfy on StudioViewModel {
  /// 告诉模型怎么出图、怎么换工作流(工作台和区域控制的对话都有)。
  String get _comfyPrompt => [
    '【出图】Penna 接着 ComfyUI,可以出图。用户要出图、要看效果时,在回复最后写 '
        '<$generateImageTag></$generateImageTag>,程序把提示词交给 ComfyUI,'
        '图会贴在这条回复下面(要几十秒,不用等,也不用说「请稍候」)。'
        '${layoutOnly ? '标签里不写字:程序用画板上眼前这张布局交出去的 JSON 出图'
                  '(这条回复写的 <layout> 已经放上去了)。' : '标签里不写字就用眼前这页的最终提示词;这条回复同时写了新的 <draft> 时,'
                  '把要出图的整条提示词(不带【】标注和〔译〕行)写进标签里。'}'
        '一条回复最多写一个。'
        '不要说你不能出图,也不要描述画出来的样子:你看不到图。',
    _comfyFlowNote,
  ].where((s) => s.isNotEmpty).join('\n');

  /// 出图用的提示词:区域控制那边是画板交出去的 MOSS JSON,工作台是最终提示词。
  String get comfyPrompt => layoutOnly ? (layout?.json ?? '') : finalPrompt;

  /// 有哪些工作流、各用什么模型;没连上就只说一句。
  String get _comfyFlowNote {
    final status = comfy.status;
    if (status == null) return '';
    if (!status.connected) {
      return '【ComfyUI】现在没连上。用户要出图、换模型时照样写标签,程序会把原因告诉他。';
    }
    return '【ComfyUI 的工作流】(名字:用的模型)\n${comfy.flowsForAgent}\n'
        '用户要换模型、换工作流时,写 <$comfyWorkflowTag>工作流名字</$comfyWorkflowTag>,'
        '换成用那个模型的工作流,换工作流和出图可以写在同一条回复里。'
        '没有哪个工作流用他说的模型,或者对得上好几个时,不写这个标签,'
        '用 <options> 列出现有的工作流问他用哪个。';
  }

  /// 写给副聊天的系统提示也带上(副聊天同样能出图、换工作流)。
  String get comfyGuide => _comfyPrompt;

  /// 改主聊天里 [at] 那条回复(按时刻找,出图期间对话里可能又多了几条);
  /// 已经不在眼前的对话里(换了对话)就不改,图还在出图列表和文件夹里。
  void Function(ChatMessage Function(ChatMessage)) _updateAt(DateTime at) =>
      (change) {
        final i = _messages.indexWhere((m) => !m.fromUser && m.time == at);
        if (i < 0) return;
        _messages = List.unmodifiable([
          ..._messages.take(i),
          change(_messages[i]),
          ..._messages.skip(i + 1),
        ]);
        _changed();
      };

  /// 主聊天的回复正常结束时:照它写的 ComfyUI 标签做事,结果记在这条回复上。
  void _deliverComfy() {
    if (_messages.isEmpty) return;
    final reply = _messages.last;
    deliverComfy(reply.text, reply.time, _updateAt(reply.time));
  }

  /// 主聊天里点了「出图」(回复下面、成稿卡片上):[prompt] 见 [generateFor]。
  void generateReply(ChatMessage reply, {String? prompt}) => generateFor(
    reply.text,
    reply.time,
    _updateAt(reply.time),
    prompt: prompt,
  );

  /// 回复里的 ComfyUI 标签(主聊天、副聊天共用):写了 `<comfy-workflow>` 先换工作流,
  /// 换不成就不出图;写了 `<generate-image>` 就出图(设置成手动确认时等用户点回复下面的「出图」)。
  /// [update] 改那条回复。
  void deliverComfy(
    String reply,
    DateTime at,
    void Function(ChatMessage Function(ChatMessage)) update,
  ) {
    final prose = splitNewSkill(reply).prose;
    final flows = splitToolTag(prose, comfyWorkflowTag).queries;
    if (flows.isNotEmpty) {
      final done = comfy.switchWorkflow(flows.last);
      _noteOn(
        update,
        done.flow != null
            ? tr('已换工作流:{0}', [done.flow])
            : tr('没换成工作流:{0}', [done.problem]),
      );
      if (done.flow == null) return;
    }
    if (!splitGenerate(prose).asked || !config.config.comfy.autoGenerate) {
      return;
    }
    generateFor(reply, at, update);
  }

  /// 出图,不等它(要几十秒),出完贴回 [at] 那条回复,出错记在它上面。
  /// [prompt] 不给就用回复里出图标签写的,标签里没写就用眼前这页的最终提示词
  /// (这条回复的成稿已经放上去了)。
  // ponytail: 成稿成了待确认改动时用的还是改之前的;要求模型这时把提示词写进标签。
  void generateFor(
    String reply,
    DateTime at,
    void Function(ChatMessage Function(ChatMessage)) update, {
    String? prompt,
  }) {
    final asked = splitGenerate(splitNewSkill(reply).prose);
    // 区域控制那边始终用画板上的布局(标签里写的不算,模型拼不对 JSON)。
    final text =
        prompt ??
        (asked.prompt.isNotEmpty && !layoutOnly
            ? stripSectionLabels(asked.prompt)
            : comfyPrompt);
    unawaited(() async {
      final done = await comfy.generate(text, owner: at);
      if (_disposed) return;
      if (done.error != null) {
        _noteOn(update, tr('出图失败:{0}', [done.error]));
      } else if (done.images.isNotEmpty) {
        update(
          (m) => m.copyWith(
            images: [...m.images, for (final g in done.images) g.path],
          ),
        );
      }
    }());
  }

  void _noteOn(
    void Function(ChatMessage Function(ChatMessage)) update,
    String text,
  ) => update(
    (m) => m.copyWith(toolSummary: [?m.toolSummary, text].join(' · ')),
  );
}
