<p align="center">
  <img src="assets/wordmark.png" height="80" alt="Penna">
</p>

<p align="center"><b>羽毛笔</b> · Windows 桌面端的文生图提示词工作台</p>

<p align="center"><a href="README.en.md">English</a> · <b>简体中文</b></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-4F7CF7" alt="platform">
  <img src="https://img.shields.io/badge/Flutter-desktop-4F7CF7?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.13%2B-F26D7D?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/version-1.0.3--261026--1--dev-F26D7D" alt="version">
  <img src="https://img.shields.io/badge/license-MIT-4F7CF7" alt="license">
</p>

---

Penna 是面向文生图**正面提示词**的创作工具,覆盖撰写、修改、润色与翻译的完整流程。

界面分为两栏:左侧为成稿,右侧为 Agent 对话。Agent 的每一处修改以待确认改动的形式呈现,**经用户确认后写入成稿**。

界面提供简体中文、繁體中文、English、日本語四种语言,并支持深色模式。

<p align="center">
  <img src="docs/promo.png" alt="Penna 功能一览">
</p>

## 目录

- [功能](#功能)
- [快速开始](#快速开始)
- [数据与隐私](#数据与隐私)
- [开发](#开发)
- [仓库结构](#仓库结构)
- [致谢](#致谢)
- [许可](#许可)

## 功能

### 成稿与确认

Agent 与润色的结果以待确认改动的形式提交。改动按行以红绿对比显示,可逐段采纳或驳回;待确认期间成稿为只读。成稿为空时,新内容直接填入。

### 分段

成稿按【主体】【光影】这样的行首标注分段,每段显示为一个独立的彩色框,并可附带一行对照译文(语言随界面设置)。交付用的「最终提示词」会自动去掉标注和对照。

- 每段可单独复制、润色、翻译、固定、删除,或带着这一段去和 Agent 讨论。
- 段可以拖动换位,也可以脱离分段变回普通文字;选中普通文字可以建成新的一段。
- 右键段的标注可以修改段名。
- 「合并」把整页的分段还原成一段连续的文字。
- Agent 只改了几段时,只对这几段提出改动,其余原样保留。

### 固定区

选中的文字或整段可以固定。固定区对润色和 Agent 都只读,可以拖动到成稿的任意位置。

### 分页与系列

每页是一条独立的提示词,页可以归入系列。系列最多 20 个,页签一层排 5 个、最多 4 层,用左右箭头翻层;每个系列的页数不限。系列满了而 Agent 还要另起系列时,页签下方提示清理。

- 同一系列共用一场对话,Agent 可参照系列内其他页的内容;各系列相互独立。
- Agent 一条回复可以同时写好几页,换主题时自动另起一个系列。
- 双击页签或系列名即可改名;页可以调整顺序、脱离系列,整个系列可以一次存入档案库。

### Agent 对话

- 回复流式输出,可随时停止或重新运行。
- 生成期间继续发送的消息进入队列,依次自动发出,也可以插队立刻发送。
- Agent 的提问以竖排选项列出,支持单选和多选;选择成稿中的段落时,直接列出当前页的各段。
- 要求 Tag 反推或指定本地模型反推时,Agent 调用本机模型处理对话中的图片;所需模型尚未安装时,由用户选择下载或改用已安装的模型。
- 要求把成稿转成 JSON 或按位置排版时,Agent 把任务交给区域控制工作台的 Agent;布局写好后显示在区域控制工作台,JSON 同时放入成稿区新建的系列。
- 图片(最大 10 MB)和文本文件可以通过按钮、拖放或 Ctrl+V 作为附件发送。
- 输入 `@` 引用某个 Skill;输入框上方的快捷操作接在已输入的内容之后,可以自定义。
- 多场对话以标签页并列,关闭的对话保留在历史中。
- 每个 Preset 有独立的系统提示、温度和 Top P。

### 本地反推

放入一张图片,由模型反推出标签或提示词,分为三类:

- **Tag 反推**:内置 20 个 ONNX 打标模型,分为 WD14、PixAI、CL 与 OppaiOracle 四个系列,生成 Danbooru 标签;角色与通用标签各有阈值,调整后即时重新筛选。结果中的标签可逐个点选,默认全选。
- **NL 反推**:内置 15 个看图模型,覆盖 Gemma 4(E2B 至 31B)、Gemma 4 Heretic、ToriiGate、JoyCaption 与 Florence-2,每个模型可选量化档。GGUF 模型由 llama.cpp 运行,运行中的服务可以加入 API 管理,供 Agent 与润色使用;Florence-2 在程序内直接运行,按指令输出标签、各级描述或构图分析。
- **LLM 反推**:从 API 管理中已启用的模型里选择一个或两个,同时反推并排显示结果,便于比较;写法跟随当前 Preset。
- 开启「压缩大图」时,大图放入后自动缩小并转为 WebP。
- 两类模型均按系列折叠显示,系列与模型都可以拖动调整顺序。
- 模型与运行时可从 HuggingFace 或国内镜像下载,支持断点续传与完整性校验;需要申请访问的模型使用设置中的 HuggingFace Token 下载。
- 在「设置 → 本地反推」中可以添加模型文件夹:连同子文件夹一起查找已有的模型(兼容 BooruDatasetTagManagerPlus、NLapt 与 HuggingFace 缓存的目录结构),找到的模型直接使用;llama.cpp 运行时、运行参数与看图要求也在这里设置。
- 看图描述的要求可以像 Preset 一样保存多条,命名并随时切换。
- 结果可以复制、发送给 Agent 或放到成稿。

### 区域控制工作台

在画布上框出各个区域并逐块描述,生成 MOSS-Image 布局 JSON;右侧有独立的布局对话。画布上方的形状工具选择拖出的区域是方框、椭圆还是多边形,钢笔可以逐点勾出任意轮廓,拖动顶点即可改形状;导出时仍按外框写成方框,形状由 Agent 写进描述,Agent 排布局时也会画形状。3D 视图的摄像机栏带打光辅助:22 个打光预设、灯光球上拖动调整每盏灯的方向、强度、软硬与色温,环境光与体积光、薄雾等氛围;灯光在导出时写成一句光影描述接在整体描述之后,Agent 也能读取和调整;打开光影预览时,体块和画布按灯光显示明暗。布局可以保存到档案库的「区域控制」分区,从档案库放回时回到区域控制工作台。

- 布局按系列和分页组织,Agent 换主题时自动另起一个系列。
- 画风固定:Agent 依据参考图或描述反推一段画风(含主色),同一系列的布局沿用这一段,改布局时保持不变;导出的 JSON 在整体描述前依次加上质量词和画风,质量词默认为 `best quality, highres, newest, year 2026, 8k resolution, masterpiece, ultra-detailed`,可在属性栏修改。
- 角色卡固定:同一系列的每个角色有一张英文角色卡(发色、瞳色、发型、标志物、服装),在属性栏可修改;导出时角色卡原样加在该角色每个人物块的描述前,整体描述末尾列出本页角色,多格多页中角色特征保持一致。
- 各块以图层列表呈现,分前景、中景、后景,拖动调整前后;支持一点、两点、三点透视辅助线。
- 发给 Agent 时附带程序算出的位置关系(各块在画面中的位置、贴边裁切、前后遮挡及遮挡比例;3D 视图中按离镜头远近、体块的实际投影轮廓和可见的面计算),Agent 据此把空间关系写进描述;给参考图时先分析图中的遮挡、裁切与机位再排布局。
- 参考图与画布一横一竖时,画布可随之横竖对调;Agent 按其他比例写的布局等比缩放后摆进画布正中。
- 3D 视图:每块带有体块(远近、厚度、朝向),由 Agent 估计;摄像机可水平环绕、俯仰、滚转、推拉和平移,框随视角重新计算,前后顺序按远近重排,描述可交给 Agent 按新视角改写,镜头调整后会提示这一步。平面视图与 3D 视图之间切换时各块的状态保留。
- 3D 视图的操作参照 Blender:中键拖动环绕,Shift+中键平移,Ctrl+中键或滚轮推拉;小键盘 1、3、7 切换正面、侧面、顶视,2、4、6、8 逐步旋转;Shift+` 进入自由镜头,WASD 走动、QE 升降。摄像机栏位于画布右侧,可收起为窄边;选中一块后,可在摄像机栏中直接调整它体块的位置、宽高厚与朝向。
- 3D 视图中透视辅助线由摄像机算出,拖动消失点即调整镜头(俯仰、环绕,两点透视时连同视角);开着透视切换到 3D 时,镜头先按透视线确定,布局保持不变;一点、两点透视用移轴保持竖线竖直,三点透视按三个消失点确定俯仰。消失点可以拖到画面外,画面外的消失点在画布边缘显示可拖动的标记。
- 自由摄像机:3D 视图中在画布旁另开一个视口,主镜头保持不动,视口可任意环绕、平移、推拉,显示地面网格、各块体块以及主镜头和它的取景范围;在视口里拖动体块即在地面上移动它,画布上的框随之更新。画布与视口按画布比例上下或左右排布。
- 画布可以全屏摆放:画布与摄像机栏铺满整个窗口,方便调整镜头和挪动各块,按 Esc 返回。
- 程序估计体块远近时,站在地面上的物体按框底边到地平线的距离推算。
- 图层可在画布上暂时屏蔽,不影响导出的 JSON;3D 视图中文字图层默认屏蔽。
- 操作记录列出画框、移动、转镜头、Agent 放上布局等每一步,可回滚到任意一步之前。

### 漫画

区域控制工作台可以排多格漫画页。Agent 按「漫画分格」Skill 先定分格表,版面分主格与小格,可斜切分格;每格一块,格里的每个人物、每个对话气泡各占一块。在画布上手画好的分格原样保留,Agent 逐格补全内容。角色卡跟着系列走,同一角色在每格、每页的发色、瞳色、发型与服装保持一致。

下面是用 Penna 排版、MOSS-Image 出图的三页连续漫画:

<p align="center">
  <img src="docs/comic-1.webp" width="32%" alt="漫画第 1 页">
  <img src="docs/comic-2.webp" width="32%" alt="漫画第 2 页">
  <img src="docs/comic-3.webp" width="32%" alt="漫画第 3 页">
</p>

### Danbooru 标签

- 内置约 7.6 万个常用标签,附使用次数和中文含义,离线可查。
- 可接入在线语义搜索,用中文描述即可找到对应标签。
- Agent 写标签前自动查询,并在成稿给出后对照词库核对,存疑的标签单独列出。

### 角色库

- 内置约 7.4 万个 Danbooru 角色,按热门程度排列,可按英文名或中文、日文译名搜索,也可以按系列(作品)名搜索。
- 每个角色的特征词分为「外貌」和「服装与其他」两组,可单独取用外貌特征。
- 「我的」「内置」「收藏」分页显示。「我的」保存自己的角色(名称、提示词和一张图),可拖动排序。
- 内置的系列和角色都可以加入收藏,在「收藏」页集中查看。
- Agent 在对话中可以查询角色库,也可以把角色存进去。

### 润色与翻译

- 润色可以针对整页、某一段或选中的一截文字,可单独指定模型。
- 翻译支持 Google、百度和阿里机翻,按设定的顺序调用,自动重试并切换引擎。
- 整段翻译写成该段的对照译文;选中文字的翻译显示在翻译卡片中。

### Skills

Skill 是一份写法说明(`SKILL.md`),决定 Agent 按什么方式写提示词。

- 内置 14 个,默认全部启用,可逐个开关。其中「漫画分格」处理一张图里的多格漫画页(分格、气泡与台词归属、跨格一致),也能把漫画页排成区域控制布局:版面有主次、可斜切分格,在画布上手画好的分格会原样保留并逐格补全内容。
- 支持导入 `.md` 或 `.zip`,也可以在设置中直接填写。
- 可以在对话中让 Agent 写一个新的 Skill,写完自动加入。

### API 管理

- 支持 OpenAI 兼容接口和 Google 接口(含 Vertex AI)。
- 「常用服务」预填 DeepSeek、智谱 GLM、Kimi、阿里云百炼及其 Coding Plan 的地址与模型,填入 Key 即可使用。
- 接口的名称、地址、模型与 Key 修改后点「保存」生效。
- 一个接口可以配置多个模型,所有模型按顺序组成后备链,自动切换。
- Agent 和润色可以分别指定首选模型。

### 档案、历史与回滚

- **档案库**:手动保存的成稿与区域控制布局,分为两个分区,带名称和分类。
- **记事本**:侧栏里随手记录的本子,每个本子包含多条记录,每条有名字和内容,输入即保存。
- **历史提示词**:采纳改动、复制、清空时自动记录,最多 100 条,可以展开全文或放回成稿。
- **操作记录**:记录页面、固定、采纳驳回等结构性操作,可以回滚到任意一步之前。

### 软件设置

「设置 → 软件设置」集中管理界面语言、深色模式、字体与头像、版本与更新,以及软件信息。

- **界面语言**:简体中文、繁體中文、English、日本語,切换后立即生效。成稿每段的对照译文与机器翻译随界面语言使用简体中文、繁體中文或日文;English 界面直接对照英文原文。
- **深色模式**:一键切换,新配色从开关处以圆形扩散展开。
- **字体与头像**:英文与中文字体可选内置字体或任意已安装的字体;Agent 与用户的头像可以换成自己的图片。

### 检查更新

每次启动时自动检查 GitHub 上的新版本,也可以在「设置 → 软件设置」中手动检查。发现新版本时显示更新说明,确认后自动下载、替换并重新启动;安装包优先经国内加速节点下载,下载后按 SHA256 校验。

### MCP

可以添加 HTTP 或 stdio 方式的 MCP 服务,测试连接并列出其工具。

## 快速开始

环境要求:Windows 10 / 11,[Flutter](https://flutter.dev)(Dart 3.13 及以上)。

```bash
flutter pub get
flutter run -d windows
```

首次启动后,在「设置 → API 管理」中填入模型接口的 Base URL 与 API Key 即可使用。各服务的填写方法见 [API 配置指南](docs/api-setup.md),该文档可直接交给 AI 助手,由它协助完成配置。

## 数据与隐私

所有数据保存在本机「文档\Penna」。

| 类别 | 文件 | 内容 |
| --- | --- | --- |
| 设置 | `config.json` | 模型、翻译、外观等配置 |
| 机密 | `keys.dat` | 全部 API Key,经 Windows DPAPI 加密,仅本机当前用户可解 |
| 工作台 | `workspace.json` | 成稿、对话、历史提示词 |
| 档案 | `archive.json` | 档案库 |
| 记事本 | `notebooks.json` | 记事本的本子与记录 |
| 角色 | `characters.json`、`characters\` | 自存的角色及图片 |
| 反推 | `reverse.json`、`reverse.img` | 参考图及反推结果 |
| 本地反推 | `local.json`、`models\`、`runtime\` | 本地反推设置、下载的模型与 llama.cpp 运行时 |
| 扩展 | `skills\` | 导入的 Skill |

## 开发

```bash
dart analyze lib test            # 静态检查
flutter test                     # 全部测试
dart format lib test             # 格式化
pwsh tool/build_release.ps1      # 打包正式版
```

> 以上命令适用于含中文的项目路径。

重新生成内置数据(仅在原始表或分类规则变动时需要):

```bash
python tool/make_tag_dict.py <CSV 所在文件夹>            # 标签词库
python tool/make_character_dict.py dataset/danbooru_character_appearance.csv   # 角色库
python tool/l10n.py keys                                 # 各语言译文缺了哪些
```

## 仓库结构

```
lib/
  ui/              界面
  core/harness/    模型调用、成稿格式、Skills、标签、角色库、MCP、本地反推(纯 Dart)
  data/            配置、存盘、翻译、加密
  l10n/            界面多语言:以简体中文原文为键的译文表
test/              测试
assets/            随程序分发:字标、头像、内置标签词库与角色库
font/              随程序分发的字体
docs/              宣传图
tool/              打包脚本、数据与图标生成脚本
windows/           Windows 平台工程
```

依赖方向自上而下:`ui` → `core/harness` → `data`;`l10n` 不依赖其他代码,各层均可使用。

## 致谢

Penna 的每一部分都建立在开源社区的成果之上。

### 数据

| 来源 | 用途 | 许可 |
| --- | --- | --- |
| [Danbooru](https://danbooru.donmai.us) 及其标注者 | 全部标签与角色数据的源头 | — |
| [Laxhar/noob-wiki](https://huggingface.co/datasets/Laxhar/noob-wiki) | 角色特征词的原始数据 | Apache-2.0 |
| [DanbooruSearch](https://sakizuki-danboorusearch.hf.space) | 在线语义搜索标签的 MCP 服务 | — |

### 软件与模型

| 项目 | 用途 | 许可 |
| --- | --- | --- |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | 本地运行打标模型 | MIT |
| [flutter_onnxruntime](https://github.com/masicai/flutter_onnxruntime) | ONNX Runtime 的 Flutter 插件 | MIT |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | 本地运行 GGUF 看图模型(使用时下载) | MIT |
| [SmilingWolf WD14 Tagger](https://huggingface.co/SmilingWolf) | 本地打标模型(使用时下载) | Apache-2.0 |
| [PixAI Tagger](https://huggingface.co/deepghs/pixai-tagger-v0.9-onnx)、[CL Tagger](https://huggingface.co/Nonene/cl_tagger)、[OppaiOracle](https://huggingface.co/Grio43/OppaiOracle) | 本地打标模型(使用时下载) | 见各模型页 |
| [Gemma 4](https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF)、[ToriiGate](https://huggingface.co/DraconicDragon/ToriiGate-0.5-GGUF)、[JoyCaption](https://huggingface.co/concedo/llama-joycaption-beta-one-hf-llava-mmproj-gguf)、[Florence-2](https://huggingface.co/onnx-community/Florence-2-base-ft) | 本地看图模型(使用时下载) | 见各模型页 |
| [lighting-kit](https://github.com/xiang6150592/-moss-prompt-editor)(韶韵提供,迁移自 MOSS Prompt Studio) | 区域控制的打光辅助:打光预设、灯光方向换算、光影描述与光影预览 | — |

### 字体

| 字体 | 作者 | 许可 |
| --- | --- | --- |
| [Maple Mono](https://github.com/subframe7536/maple-font) | subframe7536 | SIL OFL 1.1 |
| [975 圆体](https://github.com/lxgw/975Yuan) | 落霞孤鹜 | SIL OFL 1.1 |

如有遗漏,或署名、许可信息有误,欢迎提 issue 指正。

## 许可

Penna 的源代码以 [MIT](LICENSE) 许可发布。

随程序分发的第三方内容保留各自的许可:

- `assets/danbooru_characters.tsv.gz`:由 [StoryAura/Danbooru-Dataset-csv](https://huggingface.co/datasets/StoryAura/Danbooru-Dataset-csv) 的 `danbooru_character_appearance.csv` 打包而成。该表在 [Laxhar/noob-wiki](https://huggingface.co/datasets/Laxhar/noob-wiki)(Apache-2.0)的基础上扩充,扩充部分为 MIT,原有标签遵循 Apache-2.0。
- `font/MapleMono-Regular.ttf`:SIL OFL 1.1,见 [font/MapleMono-LICENSE.txt](font/MapleMono-LICENSE.txt)。
- `font/LXGW975YuanSC-500W.ttf`:SIL OFL 1.1,见 [font/LXGW975Yuan-LICENSE.txt](font/LXGW975Yuan-LICENSE.txt)。
- `onnxruntime.dll`:[ONNX Runtime](https://github.com/microsoft/onnxruntime),MIT。
