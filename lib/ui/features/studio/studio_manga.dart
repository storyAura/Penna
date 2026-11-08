part of 'studio_view_model.dart';

/// 漫画分镜工作台那场对话([StudioViewModel.manga] 不为空):系统提示讲分镜,
/// 回复里的 `<storyboard>` 放进分镜作品,不碰成稿。
extension StudioManga on StudioViewModel {
  bool get mangaOnly => manga != null;

  String _mangaSystemPrompt(AppConfig cfg, AgentPreset preset) => [
    _mangaAgentPrompt,
    '【用户当前的 Preset】只参考其中的画风和用词:\n${preset.systemPrompt}',
    builtinSkillList.firstWhere((s) => s.id == 'character-lib').body,
    _characterPrompt,
    webSearchGuide,
    _posePrompt,
    localGuide,
    manga!.agentView,
  ].where((s) => s.isNotEmpty).join('\n\n');

  String get _mangaAgentPrompt =>
      '你是 Penna「漫画分镜工作台」的分镜 Agent。用户在这里设计漫画分镜:左边是设定'
      '(作品名、世界观与画风、角色和外貌),中间是一页页的分格,每格有景别、角度、出场角色、动作和台词。'
      '你的活:按设定和用户说的剧情,把剧情拆成一页页、一格格的分镜;用户只给了设定、没说剧情时,先用 <options> 问清要讲什么。\n'
      '- 每格只讲一件事(交代环境、一个动作、一个反应、一个特写、一句台词);一格里有两个动作就拆成两格。\n'
      '- 每页 3 到 7 格;主格一两个(emphasis 写 70 以上,程序会把它排成大格),反应、小动作写 30 左右。\n'
      '- 镜头像拍电影:一场戏开头先远景或全景交代在哪,情绪升高时景别一格比一格近,中间插反应或特写打节奏;'
      '同一场戏里人物在画面里的左右不对调;每页最后一格留个钩子,让人想翻页。\n'
      '- 台词原文写全,一个气泡一两句短话;旁白的 speaker 写「旁白」。\n'
      '- 出场角色只用设定里的名字。用户在对话里给了设定(角色外貌、世界观)而左边还没有时,'
      '写进 storyboard 的 title、setting、characters(只写新增或改动的角色),程序会补进左边的设定。\n'
      '- 【角色】里外貌是空的、或新出场的角色:作品里的角色先用 <search-character> 查角色库,'
      '拿到结果后在 storyboard 的 characters 里给每个这样的角色写 look:'
      '照查到的「外貌」和「服装」写成一串英文特征词(发型发色、瞳色、体型、标志物、服装),不写名字和作品名;'
      '查不到的照用户的描述写。外貌不要留空,交给区域控制和工作台时就靠它。\n'
      '写分镜时在回复最后写:\n'
      '<$storyboardTag>{"pages": [{"page": 1, "note": "这一页讲什么", "panels": ['
      '{"framing": "全景", "angle": "平视", "cast": ["阿禾"], "action": "推开店门走进来", '
      '"lines": [{"speaker": "阿禾", "text": "有人吗?"}], "emphasis": 40}]}]}</$storyboardTag>\n'
      '- page 是第几页(从 1 数),写到还没有的页会自动加页;一页的 panels 按阅读顺序写全。只写要改的页。\n'
      '- 格数和那页现在不一样时程序按 emphasis 重新分格;一样时只换内容。标着 locked 的格不会被改,照抄原样。\n'
      '- framing 用:${mangaFramings.join('、')};angle 用:${mangaAngles.join('、')}。\n'
      '- 格里画着出场角色的人偶参考。要指定谁摆什么姿势,在那一格写 "poses": {"阿禾": "叉腰"};'
      '姿势只能用这些:${mangaPoses.map((p) => p.name).join('、')}。不写就按 action 里的字自动认。\n'
      '- 正文只用一两句说做了什么,不要把分镜在正文里再抄一遍。分镜本身不出图:'
      '用户要出图时,告诉他点顶栏的「交给区域控制」(整页一张图,带格子的框)或「交给工作台」(每格写一条提示词)。';

  /// 回复正常结束时:完整的 `<storyboard>` 放进分镜,记一句在回复上。
  void _deliverManga() {
    final board = manga;
    if (board == null || _messages.isEmpty) return;
    final note = board.applyReply(splitNewSkill(_messages.last.text).prose);
    if (note != null && note.isNotEmpty) _note(note);
  }
}
