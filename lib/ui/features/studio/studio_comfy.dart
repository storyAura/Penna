part of 'studio_view_model.dart';

/// Agent 出图:回复里写了 `<generate-image>`,程序交给 ComfyUI,出的图贴回那条回复。
extension StudioComfy on StudioViewModel {
  /// 告诉模型怎么出图(只有工作台的对话有)。
  String get _comfyPrompt =>
      '【出图】Penna 接着 ComfyUI,可以出图。用户要出图、要看效果时,在回复最后写 '
      '<$generateImageTag></$generateImageTag>,程序把提示词交给 ComfyUI,'
      '图会贴在这条回复下面(要几十秒,不用等,也不用说「请稍候」)。'
      '标签里不写字就用眼前这页的最终提示词;这条回复同时写了新的 <draft> 时,'
      '把要出图的整条提示词(不带【】标注和〔译〕行)写进标签里。一条回复最多写一个。'
      '不要说你不能出图,也不要描述画出来的样子:你看不到图。';

  /// 回复正常结束时:写了出图标签就去出图。不等它,出图要几十秒。
  void _deliverImage() {
    if (layoutOnly || _messages.isEmpty) return;
    final reply = _messages.last;
    final asked = splitGenerate(splitNewSkill(reply.text).prose);
    if (!asked.asked) return;
    // 标签里没写就用眼前这页(这条回复的成稿已经放上去了)。
    // ponytail: 成稿成了待确认改动时用的还是改之前的;要求模型这时把提示词写进标签。
    final prompt = asked.prompt.isNotEmpty
        ? stripSectionLabels(asked.prompt)
        : finalPrompt;
    unawaited(_imageFor(reply.time, prompt));
  }

  /// 出图,出完贴到 [at] 那条回复上;出错写在回复的记录里。
  /// 那条回复已经不在眼前的对话里(换了对话)就不贴,图还在出图列表和文件夹里。
  Future<void> _imageFor(DateTime at, String prompt) async {
    final done = await comfy.generate(prompt, owner: at);
    if (_disposed || done.images.isEmpty && done.error == null) return;
    final i = _messages.indexWhere((m) => !m.fromUser && m.time == at);
    if (i < 0) return;
    final m = _messages[i];
    final next = done.error == null
        ? m.copyWith(images: [...m.images, for (final g in done.images) g.path])
        : m.copyWith(
            toolSummary: [
              ?m.toolSummary,
              tr('出图失败:{0}', [done.error]),
            ].join(' · '),
          );
    _messages = List.unmodifiable([
      ..._messages.take(i),
      next,
      ..._messages.skip(i + 1),
    ]);
    _changed();
  }
}
