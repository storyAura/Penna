<p align="center">
  <img src="assets/wordmark.png" height="80" alt="Penna">
</p>

<p align="center"><b>Penna</b> · A text-to-image prompt workbench for Windows and Linux</p>

<p align="center"><b>English</b> · <a href="README.md">简体中文</a></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011%20%7C%20Linux-4F7CF7" alt="platform">
  <img src="https://img.shields.io/badge/Flutter-desktop-4F7CF7?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.13%2B-F26D7D?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/license-MIT-4F7CF7" alt="license">
</p>

---

Penna is a tool for writing **positive prompts** for text-to-image models. It covers the whole process: drafting, editing, polishing and translating.

The window has two columns: the draft on the left and the Agent chat on the right. Every change the Agent makes arrives as a pending change and **is written into the draft only after you accept it**.

<p align="center">
  <img src="docs/promo-en.png" alt="Penna features">
</p>

## Features

- **Draft and review**: results from the Agent and Polish appear as a line-by-line red/green diff, accepted or rejected section by section.
- **Sections and pins**: labels such as 【Subject】 and 【Lighting】 split the draft into sections that can be copied, polished, translated and pinned on their own; the delivered prompt drops labels and translations automatically.
- **Pages and series**: each page is one prompt, pages in a series share a conversation, and one Agent reply can write several pages.
- **Agent chat**: streaming replies, message queueing, option questions, image and text attachments, `@` Skill citations, and conversations side by side as tabs.
- **Side chat**: a translucent floating panel runs a second conversation with its own model and Armor-Piercing switch, and each chat can read the other's conversation.
- **Local Interrogate**: 20 built-in taggers and 15 vision models, plus two online models interrogating side by side; a choice of download sources with automatic fallback, and direct use of models already on the PC.
- **Region Control**: draw regions, describe each one and produce MOSS-Image layout JSON, with shape tools, perspective guides, a 3D camera and a lighting assistant.
- **Comics**: multi-panel pages laid out from a panel plan, with characters consistent across panels and pages.
- **Danbooru tags**: about 76,000 built-in tags and optional online semantic search; the Agent looks tags up before writing and checks the delivered draft afterwards.
- **Characters**: about 74,000 built-in Danbooru characters with looks and outfits split apart and transformations and costumes listed together; your own characters keep aliases, a description and several outfits.
- **Polish and translate**: works on a page, a section or selected text; machine translation through Google, Baidu and Alibaba with automatic retries and engine switching.
- **Skills**: 14 built-in writing guides, import from `.md` or `.zip`, or ask the Agent to write a new one in chat.
- **API Management**: OpenAI-compatible APIs and the Google API (including Vertex AI), with models forming an ordered fallback chain.
- **Archive and history**: Archive, Notes and prompt history; Activity is a tree that can return to before or after any step and keeps every branch.
- **Settings and updates**: English, 简体中文, 繁體中文 and 日本語 interfaces, dark mode and one-click updates inside the app.
- **MCP**: add servers over HTTP or stdio, test the connection and list their tools.

The [feature guide](docs/features.en.md) covers every feature in full.

A three-page comic laid out in Penna and rendered with MOSS-Image:

<p align="center">
  <img src="docs/comic-1.webp" width="32%" alt="Comic page 1">
  <img src="docs/comic-2.webp" width="32%" alt="Comic page 2">
  <img src="docs/comic-3.webp" width="32%" alt="Comic page 3">
</p>

## Contents

- [Getting started](#getting-started)
- [Data and privacy](#data-and-privacy)
- [Development](#development)
- [Changelog](#changelog)
- [Contributing](#contributing)
- [Acknowledgements](#acknowledgements)
- [License](#license)

## Getting started

Download the package for your platform from [Releases](https://github.com/storyAura/Penna/releases):

- **Windows 10 / 11**: `Penna-v<version>-windows-x64.zip`. Unzip it and run `penna.exe`.
- **Linux**: `Penna-v<version>-linux-x86_64.AppImage`. Make it executable (`chmod +x`) and run it.

On first launch the interface is in Simplified Chinese. Click the gear icon at the bottom left, open **软件设置** (App settings) and set **界面语言** (Language) to **English**.

Then fill in the Base URL and API key of your model API in **Settings → API Management**. The [API setup guide](docs/api-setup.md) explains each service and can be handed straight to an AI assistant to help with the setup.

The [Penna guide](docs/agent-guide.md) (in Chinese) covers what the app does, where everything is, how to use it and every setting, and can also be handed to an AI assistant to walk you through it.

To run from source you need [Flutter](https://flutter.dev) (Dart 3.13 or later):

```bash
flutter pub get
flutter run -d windows     # Windows
flutter run -d linux       # Linux
```

## Data and privacy

All data is stored on this PC in `Documents\Penna` (`~/Documents/Penna` on Linux). API keys are encrypted with DPAPI on Windows and kept in the system keyring on Linux, readable only by the current user on this PC. See [Data files](docs/features.en.md#data-files) for what each file holds.

## Development

```bash
dart analyze lib test            # static analysis
flutter test                     # all tests
dart format lib test             # formatting
pwsh tool/build_release.ps1      # package (Windows)
bash tool/build_release.sh       # package (Linux AppImage)
```

These commands work with project paths that contain non-ASCII characters.

Regenerate the built-in data (only when the source tables or the classification rules change):

```bash
python tool/make_tag_dict.py <folder with the CSVs>                                      # tag dictionary
python tool/make_character_dict.py dataset/danbooru_character_appearance_corrected.csv   # character library
python tool/l10n.py keys                                                                 # missing translations per language
```

The code has three layers, with dependencies pointing downward: `lib/ui` (interface) → `lib/core/harness` (model calls, draft format, Skills, tags, characters, local interrogation) → `lib/data` (settings, storage, translation, encryption). `lib/l10n` depends on nothing else and can be used by every layer.

## Changelog

See [Releases](https://github.com/storyAura/Penna/releases) for what changed in each version.

## Contributing

Please send questions and suggestions as [Issues](https://github.com/storyAura/Penna/issues). Before opening a Pull Request, run `dart analyze lib test` and `flutter test`.

## Acknowledgements

Every part of Penna is built on the work of the open-source community.

### Data

| Source | Used for | License |
| --- | --- | --- |
| [Danbooru](https://danbooru.donmai.us) and its taggers | The origin of all tag and character data | — |
| [Laxhar/noob-wiki](https://huggingface.co/datasets/Laxhar/noob-wiki) | Original character tag data | Apache-2.0 |
| [DanbooruSearch](https://sakizuki-danboorusearch.hf.space) | MCP service for online semantic tag search | — |

### Software and models

| Project | Used for | License |
| --- | --- | --- |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | Running taggers locally | MIT |
| [flutter_onnxruntime](https://github.com/masicai/flutter_onnxruntime) | Flutter plugin for ONNX Runtime | MIT |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | Running GGUF vision models locally (downloaded on use) | MIT |
| [SmilingWolf WD14 Tagger](https://huggingface.co/SmilingWolf) | Local taggers (downloaded on use) | Apache-2.0 |
| [PixAI Tagger](https://huggingface.co/deepghs/pixai-tagger-v0.9-onnx), [CL Tagger](https://huggingface.co/Nonene/cl_tagger), [OppaiOracle](https://huggingface.co/Grio43/OppaiOracle) | Local taggers (downloaded on use) | See each model page |
| [Gemma 4](https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF), [ToriiGate](https://huggingface.co/DraconicDragon/ToriiGate-0.5-GGUF), [JoyCaption](https://huggingface.co/concedo/llama-joycaption-beta-one-hf-llava-mmproj-gguf), [Florence-2](https://huggingface.co/onnx-community/Florence-2-base-ft) | Local vision models (downloaded on use) | See each model page |
| [lighting-kit](https://github.com/xiang6150592/-moss-prompt-editor) (provided by 韶韵, ported from MOSS Prompt Studio) | Region Control lighting assistant: lighting presets, light direction math, lighting phrases and shading preview | — |

### Fonts

| Font | Author | License |
| --- | --- | --- |
| [Maple Mono](https://github.com/subframe7536/maple-font) | subframe7536 | SIL OFL 1.1 |
| [975 Yuan](https://github.com/lxgw/975Yuan) | LXGW | SIL OFL 1.1 |

If anything is missing, or an attribution or license is wrong, please open an issue.

## License

Penna's source code is released under the [MIT](LICENSE) license.

Third-party content shipped with the app keeps its own license:

- `assets/danbooru_characters.tsv.gz`: packed from `danbooru_character_appearance_corrected.csv` in [StoryAura/Danbooru-Dataset-csv](https://huggingface.co/datasets/StoryAura/Danbooru-Dataset-csv). That table extends [Laxhar/noob-wiki](https://huggingface.co/datasets/Laxhar/noob-wiki) (Apache-2.0); the extensions are MIT and the original tags remain under Apache-2.0. The links between characters and their forms (the `base_character` column) are compiled from Danbooru tag implications and character wiki pages.
- `font/MapleMono-Regular.ttf`: SIL OFL 1.1, see [font/MapleMono-LICENSE.txt](font/MapleMono-LICENSE.txt).
- `font/LXGW975YuanSC-500W.ttf`: SIL OFL 1.1, see [font/LXGW975Yuan-LICENSE.txt](font/LXGW975Yuan-LICENSE.txt).
- `onnxruntime.dll`: [ONNX Runtime](https://github.com/microsoft/onnxruntime), MIT.
