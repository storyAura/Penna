<p align="center">
  <img src="assets/wordmark.png" height="80" alt="Penna">
</p>

<p align="center"><b>羽毛笔</b> · Windows / Linux 桌面端的文生图提示词工作台</p>

<p align="center"><a href="README.en.md">English</a> · <b>简体中文</b></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011%20%7C%20Linux-4F7CF7" alt="platform">
  <img src="https://img.shields.io/badge/Flutter-desktop-4F7CF7?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.13%2B-F26D7D?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/version-1.0.3--261031--1--dev-F26D7D" alt="version">
  <img src="https://img.shields.io/badge/license-MIT-4F7CF7" alt="license">
</p>

---

Penna 是面向文生图**正面提示词**的创作工具,覆盖撰写、修改、润色与翻译的完整流程。

界面分为两栏:左侧为成稿,右侧为 Agent 对话。Agent 的每一处修改以待确认改动的形式呈现,**经用户确认后写入成稿**。

<p align="center">
  <img src="docs/promo.png" alt="Penna 功能一览">
</p>

## 功能

- **成稿与确认**:Agent 与润色的结果按行红绿对比,可逐段采纳或驳回。
- **分段与固定**:以【主体】【光影】这样的标注分段,每段可单独复制、润色、翻译和固定;交付时自动去掉标注与对照译文。
- **分页与系列**:每页一条提示词,同一系列共用一场对话,Agent 一条回复可写好几页。
- **Agent 对话**:流式输出、消息排队、选项提问、图片与文本附件、`@` 引用 Skill,多场对话以标签页并列。
- **副聊天**:半透明浮窗另开一场对话,使用单独的模型和穿甲弹开关,两边可读取对方的记录。
- **本地反推**:内置 20 个 Tag 模型和 15 个看图模型,并可让两个在线模型同时反推、并排比较;下载来源可选,失败时自动换用其他来源;可直接使用本机已有的模型。
- **区域控制工作台**:框选区域逐块描述,生成 MOSS-Image 布局 JSON;提供形状工具、透视辅助、3D 摄像机和打光辅助。
- **漫画**:按分格表排多格漫画页,角色特征跨格、跨页保持一致。
- **Danbooru 标签**:内置约 7.6 万个标签,可接入在线语义搜索;Agent 写标签前自动查询并在成稿后核对。
- **角色库**:内置约 7.4 万个 Danbooru 角色,外貌与服装分开取用,一并列出变身、换装后的形态;自己的角色可保存别名、简介和多套服装。
- **润色与翻译**:可针对整页、某一段或选中的文字;机器翻译支持 Google、百度和阿里,自动重试并切换引擎。
- **Skills**:内置 14 个写法说明,支持导入 `.md` / `.zip`,也可让 Agent 在对话中写新的 Skill。
- **API 管理**:支持 OpenAI 兼容接口和 Google 接口(含 Vertex AI),多个模型按顺序组成后备链。
- **档案与记录**:档案库、记事本、历史提示词;操作记录是一棵树,可回到任意一步之前或之后,各分支都保留。
- **软件设置与更新**:简体中文、繁體中文、English、日本語四种界面语言,深色模式,应用内一键更新。
- **MCP**:添加 HTTP 或 stdio 方式的服务,测试连接并列出工具。

每项功能的完整说明见[功能说明](docs/features.md)。

用 Penna 排版、MOSS-Image 出图的三页连续漫画:

<p align="center">
  <img src="docs/comic-1.webp" width="32%" alt="漫画第 1 页">
  <img src="docs/comic-2.webp" width="32%" alt="漫画第 2 页">
  <img src="docs/comic-3.webp" width="32%" alt="漫画第 3 页">
</p>

## 目录

- [快速开始](#快速开始)
- [数据与隐私](#数据与隐私)
- [开发](#开发)
- [更新记录](#更新记录)
- [参与贡献](#参与贡献)
- [致谢](#致谢)
- [许可](#许可)

## 快速开始

从 [Releases](https://github.com/storyAura/Penna/releases) 下载对应平台的安装包:

- **Windows 10 / 11**:`Penna-v<版本>-windows-x64.zip`,解压后运行 `penna.exe`。
- **Linux**:`Penna-v<版本>-linux-x86_64.AppImage`,赋予执行权限(`chmod +x`)后直接运行。

首次启动后,在「设置 → API 管理」中填入模型接口的 Base URL 与 API Key 即可使用。各服务的填写方法见 [API 配置指南](docs/api-setup.md),该文档可直接交给 AI 助手,由它协助完成配置。

[Penna 使用指南](docs/agent-guide.md)介绍软件的功能、界面位置、用法与全部设置,同样可以直接交给 AI 助手,由它带你上手。

从源码运行需要 [Flutter](https://flutter.dev)(Dart 3.13 及以上):

```bash
flutter pub get
flutter run -d windows     # Windows
flutter run -d linux       # Linux
```

## 数据与隐私

所有数据保存在本机「文档\Penna」(Linux 上为 `~/Documents/Penna`)。API Key 在 Windows 上经 DPAPI 加密,在 Linux 上存入系统钥匙串,都只有本机当前用户能解。各文件的内容见[数据文件](docs/features.md#数据文件)。

## 开发

```bash
dart analyze lib test            # 静态检查
flutter test                     # 全部测试
dart format lib test             # 格式化
pwsh tool/build_release.ps1      # 打包(Windows)
bash tool/build_release.sh       # 打包(Linux AppImage)
```

以上命令适用于含中文的项目路径。

重新生成内置数据(仅在原始表或分类规则变动时需要):

```bash
python tool/make_tag_dict.py <CSV 所在文件夹>                                            # 标签词库
python tool/make_character_dict.py dataset/danbooru_character_appearance_corrected.csv   # 角色库
python tool/l10n.py keys                                                                 # 各语言译文的缺失数量
```

代码分三层,依赖方向自上而下:`lib/ui`(界面)→ `lib/core/harness`(模型调用、成稿格式、Skills、标签、角色库、本地反推)→ `lib/data`(配置、存盘、翻译、加密);`lib/l10n` 不依赖其他代码,各层均可使用。

## 更新记录

每个版本的更新内容见 [Releases](https://github.com/storyAura/Penna/releases)。

## 参与贡献

问题与建议请提交 [Issue](https://github.com/storyAura/Penna/issues)。提交 Pull Request 前请运行 `dart analyze lib test` 与 `flutter test`。

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

- `assets/danbooru_characters.tsv.gz`:由 [StoryAura/Danbooru-Dataset-csv](https://huggingface.co/datasets/StoryAura/Danbooru-Dataset-csv) 的 `danbooru_character_appearance_corrected.csv` 打包而成。该表在 [Laxhar/noob-wiki](https://huggingface.co/datasets/Laxhar/noob-wiki)(Apache-2.0)的基础上扩充,扩充部分为 MIT,原有标签遵循 Apache-2.0。角色的形态关系(`base_character` 列)整理自 Danbooru 的标签蕴含和角色 wiki。
- `font/MapleMono-Regular.ttf`:SIL OFL 1.1,见 [font/MapleMono-LICENSE.txt](font/MapleMono-LICENSE.txt)。
- `font/LXGW975YuanSC-500W.ttf`:SIL OFL 1.1,见 [font/LXGW975Yuan-LICENSE.txt](font/LXGW975Yuan-LICENSE.txt)。
- `onnxruntime.dll`:[ONNX Runtime](https://github.com/microsoft/onnxruntime),MIT。
