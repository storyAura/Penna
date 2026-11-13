import '../../../l10n/l10n.dart';
import 'pixel_mascot.dart';

/// 教程的一步:[page] 是先切到哪一页(`navPages` 的 id 或 'settings',null 不切),
/// [spot] 是要高亮的那块(`TourSpot` 的 id,null 时不挖洞、卡片放正中),[face] 是吉祥物这一步的表情。
typedef TourStep = ({
  String? page,
  String? spot,
  MascotLook face,
  String title,
  String body,
});

/// 先细讲三个工作台,再粗略过一遍其他页,最后停在设置。
List<TourStep> get tourSteps => [
  (
    page: 'studio',
    spot: null,
    face: MascotLook.wave,
    title: tr('欢迎来到 Penna'),
    body: tr('哼,才不是特意等你的……既然来了,就带你逛一圈吧。按 ← → 翻页,Esc 随时跳过。'),
  ),
  (
    page: 'studio',
    spot: 'nav',
    face: MascotLook.point,
    title: tr('侧栏'),
    body: tr('各页的入口,分成写、参考、存三组。顺序可以在「设置 → 软件设置」里拖动调整。'),
  ),
  // —— 工作台 ——
  (
    page: 'studio',
    spot: 'studio.draft',
    face: MascotLook.write,
    title: tr('成稿'),
    body: tr('这一页的提示词,按【主体】【光影】这样的标注分段。每段能单独复制、润色、翻译、固定,或带着它去和 Agent 讨论。'),
  ),
  (
    page: 'studio',
    spot: 'studio.pages',
    face: MascotLook.point,
    title: tr('分页与系列'),
    body: tr('每页是一条提示词,页可以归进系列。双击页签改名,按住 Shift 多选,右键批量操作。'),
  ),
  (
    page: 'studio',
    spot: 'studio.summary',
    face: MascotLook.proud,
    title: tr('最终提示词'),
    body: tr('去掉标注和对照译文后的成品,一键复制。接好 ComfyUI 后点「出图」,进度和图片在「出图」页签里。'),
  ),
  (
    page: 'studio',
    spot: 'studio.chat',
    face: MascotLook.point,
    title: tr('Agent 对话'),
    body: tr(
      '说出想画什么,Agent 写好成稿交到左边。改动以红绿对比列出,采纳了才算数。它会自己查 Danbooru 标签和角色库,需要时联网搜索。',
    ),
  ),
  (
    page: 'studio',
    spot: 'studio.header',
    face: MascotLook.think,
    title: tr('模型与对话'),
    body: tr('顶上切换模型和 Preset,「新对话」另开一场。多场对话以标签页并列。'),
  ),
  (
    page: 'studio',
    spot: 'studio.composer',
    face: MascotLook.yawn,
    title: tr('输入框'),
    body: tr(
      '图片和文本文件可以拖进来或 Ctrl+V 粘贴;输入 @ 点名 Skill。上方是快捷操作,下方调思考强度,圆环显示上下文用量,副聊天另开一场小对话。',
    ),
  ),
  (
    page: 'studio',
    spot: 'studio.chat',
    face: MascotLook.think,
    title: tr('进阶:回复'),
    body: tr('不满意就重新回复,在回复下方翻看之前的几份;发过的话能编辑重发;写到一半断了点「接着写」。生成时继续发的消息会排队。'),
  ),
  (
    page: 'studio',
    spot: 'studio.activity',
    face: MascotLook.whine,
    title: tr('操作记录与出图队列'),
    body: tr('每一步都记着,能回到任意一步之前或之后。出图队列列出排队中和出好的图,结束的可以重新生成。'),
  ),
  (
    page: 'studio',
    spot: 'studio.right',
    face: MascotLook.huff,
    title: tr('右侧侧栏'),
    body: tr('ComfyUI 面板切换服务器和工作流、调 LoRA;历史对话;闪电是穿甲弹开关。'),
  ),
  // —— 区域控制工作台 ——
  (
    page: 'layout',
    spot: 'layout.canvas',
    face: MascotLook.proud,
    title: tr('区域控制工作台'),
    body: tr(
      '在画布上框出各个区域、逐块描述,生成 MOSS-Image 布局 JSON。上方的工具切换方框、椭圆、钢笔,还有 3D 视图和自由摄像机。',
    ),
  ),
  (
    page: 'layout',
    spot: 'layout.props',
    face: MascotLook.point,
    title: tr('图层与属性'),
    body: tr('各块分前景、中景、后景,拖动调整前后;选中一块写它的描述。画风和角色卡也在这里,整个系列共用。'),
  ),
  (
    page: 'layout',
    spot: 'layout.chat',
    face: MascotLook.write,
    title: tr('布局 Agent'),
    body: tr('描述画面或给一张参考图,Agent 排好布局放上画布。工作台的 Agent 遇到排版的活也会交到这里。'),
  ),
  // —— 漫画分镜工作台 ——
  (
    page: 'manga',
    spot: 'manga.inspector',
    face: MascotLook.gasp,
    title: tr('漫画分镜工作台'),
    body: tr('左边是「设定」与「本格」:作品的世界观、画风、角色,和选中那一格的景别、角度、台词。'),
  ),
  (
    page: 'manga',
    spot: 'manga.canvas',
    face: MascotLook.yawn,
    title: tr('分格'),
    body: tr('上方切换系列和页。拖动格线调大小,格线可以斜切、可以出血。格里的人偶按景别和动作自动摆好姿势。'),
  ),
  (
    page: 'manga',
    spot: 'manga.gacha',
    face: MascotLook.cheer,
    title: tr('抽卡'),
    body: tr('「抽分格」按版式切出一批候选,点缩略图预览,「用这张」才换上;「抽镜头」随机定景别和角度。'),
  ),
  (
    page: 'manga',
    spot: 'manga.chat',
    face: MascotLook.write,
    title: tr('分镜 Agent'),
    body: tr('把故事拆成一页页、一格格的分镜。写好后在顶栏「交给区域控制」或「交给工作台」去出图。'),
  ),
  // —— 其他页 ——
  (
    page: 'characters',
    spot: 'nav.characters',
    face: MascotLook.huff,
    title: tr('角色库'),
    body: tr('内置约 7.4 万个 Danbooru 角色,按中日英名字或作品搜索;「我的」存自己的角色和几套服装。'),
  ),
  (
    page: 'poses',
    spot: 'nav.poses',
    face: MascotLook.point,
    title: tr('姿势图库'),
    body: tr('人偶姿势线稿,下载或导入后使用。「附到对话」交给 Agent 当体态参考。'),
  ),
  (
    page: 'local',
    spot: 'nav.local',
    face: MascotLook.think,
    title: tr('本地反推'),
    body: tr('放进一张图,用本机模型或接口反推出标签和描述。'),
  ),
  (
    page: 'archive',
    spot: 'nav.archive',
    face: MascotLook.wave,
    title: tr('档案库'),
    body: tr('存下的成稿、布局、漫画,还有 ComfyUI 出的图。'),
  ),
  (
    page: 'notebook',
    spot: 'nav.notebook',
    face: MascotLook.write,
    title: tr('记事本'),
    body: tr('随手记的本子,Agent 也能读写。'),
  ),
  (
    page: null,
    spot: 'nav.log',
    face: MascotLook.panic,
    title: tr('模型日志'),
    body: tr('换接口、出错、截断、停止都记在这里,有新问题时按钮上带条数。'),
  ),
  (
    page: 'settings',
    spot: 'settings.tabs',
    face: MascotLook.point,
    title: tr('设置'),
    body: tr('先到「API 管理」接上模型,Agent 才能干活。ComfyUI、Skill、语言和深色模式也在这里。'),
  ),
  (
    page: 'settings',
    spot: 'settings.tutorial',
    face: MascotLook.cheer,
    title: tr('逛完啦'),
    body: tr('记住了没?想再看就点这里的「教程」……我、我才不会特意再讲一遍呢!'),
  ),
];
