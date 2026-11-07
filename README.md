<p align="center">
  <img src="assets/wordmark.png" height="80" alt="Penna">
</p>

<p align="center"><b>羽毛笔</b> · Windows / Linux 桌面端的文生图提示词工作台</p>

<p align="center"><a href="README.en.md">English</a> · <b>简体中文</b></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011%20%7C%20Linux-4F7CF7" alt="platform">
  <img src="https://img.shields.io/badge/Flutter-desktop-4F7CF7?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.13%2B-F26D7D?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/version-1.0.3--261107--1--dev-F26D7D" alt="version">
  <img src="https://img.shields.io/badge/license-MIT-4F7CF7" alt="license">
</p>

---

Penna 是面向文生图**正面提示词**的创作工具,覆盖撰写、修改、润色与翻译的完整流程。左侧为成稿,右侧为 Agent 对话,Agent 的每一处修改**经用户确认后写入成稿**。

<p align="center">
  <img src="docs/promo.png" alt="Penna 功能一览">
</p>

## 视频

- [Penna 项目介绍](https://www.bilibili.com/video/BV1PLpj62EDu) · storyAura
- [用 Penna 设计漫画分镜](https://www.bilibili.com/video/BV1yUso6AE92) · 雷昂

## 功能

- **协同写词**:Agent 的改动以红绿对比呈现,逐段采纳或驳回;提示词按【主体】【光影】等标注分段,支持分页与系列。
- **Agent 对话**:多场对话并列,副聊天浮窗,图片与文件附件,`@` 引用 Skill,联网搜索,可调思考强度。
- **区域控制工作台**:框选区域逐块描述,生成 MOSS-Image 布局 JSON;可排多格漫画页。
- **本地反推**:内置 20 个 Tag 模型与 15 个看图模型,也可调用在线模型反推。
- **标签与角色库**:内置约 7.6 万个 Danbooru 标签与 7.4 万个角色,Agent 写词前自动查询。
- **ComfyUI 出图**:接入本机或云端的 ComfyUI,最终提示词一键出图并显示进度,Agent 可在对话中出图,存档时自动生成预览图。
- **模型接入**:OpenAI 兼容接口、Google 接口与 Grok 账号登录,多个模型组成后备链。
- **更多**:Skills、档案库、记事本、操作记录树、MCP、四种界面语言、深色模式、应用内更新。

完整说明见[功能说明](docs/features.md)。用 Penna 排版、MOSS-Image 出图的三页连续漫画:

<p align="center">
  <img src="docs/comic-1.webp" width="32%" alt="漫画第 1 页">
  <img src="docs/comic-2.webp" width="32%" alt="漫画第 2 页">
  <img src="docs/comic-3.webp" width="32%" alt="漫画第 3 页">
</p>

## 快速开始

从 [Releases](https://github.com/storyAura/Penna/releases) 下载安装包,各版本的更新内容也在那里:

- **Windows 10 / 11**:`Penna-v<版本>-windows-x64.zip`,解压后运行 `penna.exe`。
- **Linux**:`Penna-v<版本>-linux-x86_64.AppImage`,`chmod +x` 后直接运行。

首次启动后,在「设置 → API 管理」填入接口的 Base URL 与 API Key。[API 配置指南](docs/api-setup.md)与 [Penna 使用指南](docs/agent-guide.md)都可以直接交给 AI 助手,由它协助配置和上手。

数据保存在本机「文档\Penna」(Linux 上为 `~/Documents/Penna`),API Key 加密存储,详见[数据文件](docs/features.md#数据文件)。

## 开发

需要 [Flutter](https://flutter.dev)(Dart 3.13 及以上):

```bash
flutter pub get
flutter run -d windows           # 或 -d linux
dart analyze lib test            # 静态检查
flutter test                     # 全部测试
pwsh tool/build_release.ps1      # 打包 Windows 版;Linux 版用 bash tool/build_release.sh
```

代码分三层,依赖自上而下:`lib/ui`(界面)→ `lib/core/harness`(模型调用、成稿格式、Skills、标签、角色库、本地反推)→ `lib/data`(配置、存盘、翻译、加密)。

## 参与贡献

问题与建议请提交 [Issue](https://github.com/storyAura/Penna/issues)。

本项目本身也是 Vibe Coding 项目,欢迎提交由 AI 编写的代码。请在本地测试无误后再提交(至少通过 `dart analyze lib test` 与 `flutter test`),并建议基于 `dev` 分支修改、向 `dev` 提交 Pull Request。

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
