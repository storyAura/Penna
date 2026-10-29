// 本地反推下模型的几个来源。清单里记的都是 HuggingFace 上的仓库,下载时按设置换成别的地址。

/// 模型的下载来源(存在 local.json 的 `source`)和名字;名字显示时再翻译。
const modelSources = {
  'huggingface': '官方源',
  'mirror': 'HuggingFace 加速',
  'modelscope': 'ModelScope',
  'custom': '自定义',
};

/// 选中的来源下不了时,接着按这个顺序试别的。
const _fallback = ['huggingface', 'modelscope', 'mirror', 'custom'];

const _hf = 'https://huggingface.co';
const _hfMirror = 'https://hf-mirror.com';

/// ModelScope 上有同样文件的仓库(HuggingFace 仓库 → ModelScope 仓库)。
/// 2026-10-29 逐个文件对过 SHA256;没列的 ModelScope 上没有,或文件对不上
/// (wd-v1-4-swinv2-tagger-v2 的模型、OppaiOracle 的标签表不一样)。
const modelscopeRepos = {
  'SmilingWolf/wd-v1-4-convnext-tagger': 'fireicewolf/wd-v1-4-convnext-tagger',
  'SmilingWolf/wd-v1-4-convnext-tagger-v2':
      'fireicewolf/wd-v1-4-convnext-tagger-v2',
  'SmilingWolf/wd-v1-4-convnextv2-tagger-v2':
      'fireicewolf/wd-v1-4-convnextv2-tagger-v2',
  'SmilingWolf/wd-v1-4-vit-tagger': 'fireicewolf/wd-v1-4-vit-tagger',
  'SmilingWolf/wd-v1-4-vit-tagger-v2': 'fireicewolf/wd-v1-4-vit-tagger-v2',
  'SmilingWolf/wd-v1-4-moat-tagger-v2': 'fireicewolf/wd-v1-4-moat-tagger-v2',
  'SmilingWolf/wd-vit-tagger-v3': 'fireicewolf/wd-vit-tagger-v3',
  'SmilingWolf/wd-swinv2-tagger-v3': 'fireicewolf/wd-swinv2-tagger-v3',
  'SmilingWolf/wd-convnext-tagger-v3': 'fireicewolf/wd-convnext-tagger-v3',
  'SmilingWolf/wd-vit-large-tagger-v3': 'fireicewolf/wd-vit-large-tagger-v3',
  'SmilingWolf/wd-eva02-large-tagger-v3':
      'fireicewolf/wd-eva02-large-tagger-v3',
  'deepghs/pixai-tagger-v0.9-onnx': 'deepghs/pixai-tagger-v0.9-onnx',
  'Nonene/cl_tagger': 'nikoovo/cl-tagger',
  'unsloth/gemma-4-E2B-it-GGUF': 'unsloth/gemma-4-E2B-it-GGUF',
  'unsloth/gemma-4-E4B-it-GGUF': 'unsloth/gemma-4-E4B-it-GGUF',
  'unsloth/gemma-4-12b-it-GGUF': 'unsloth/gemma-4-12b-it-GGUF',
  'unsloth/gemma-4-26B-A4B-it-GGUF': 'unsloth/gemma-4-26B-A4B-it-GGUF',
  'unsloth/gemma-4-31B-it-GGUF': 'unsloth/gemma-4-31B-it-GGUF',
  'onnx-community/Florence-2-base': 'onnx-community/Florence-2-base',
  'onnx-community/Florence-2-base-ft': 'onnx-community/Florence-2-base-ft',
  'onnx-community/Florence-2-large': 'onnx-community/Florence-2-large',
  'onnx-community/Florence-2-large-ft': 'onnx-community/Florence-2-large-ft',
};

/// HuggingFace 上一个文件的地址(清单里的文件都记成这种)。
String hfFileUrl(String repo, String file) => '$_hf/$repo/resolve/main/$file';

final _hfFile = RegExp(
  r'^https://huggingface\.co/([^/]+/[^/]+)/resolve/main/(.+)$',
);

/// 自定义来源的地址能不能用:http(s) 开头、有主机名。能用时返回去掉末尾斜杠的样子。
String? sourceBase(String custom) {
  final base = custom.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(base);
  final ok =
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
  return ok ? base : null;
}

/// 下 HuggingFace 上的 [url] 时依次试的地址:选中的来源 [source] 先试,下不了再按
/// 官方源、ModelScope、HuggingFace 加速、自定义的顺序试别的。ModelScope 上没有的、
/// [custom] 不能用的跳过。[gated] 的模型要带 Token,只发给 HuggingFace 和它的加速站。
/// 不是 HuggingFace 文件地址的原样返回。
List<String> modelUrls(
  String url,
  String source, {
  String custom = '',
  bool gated = false,
}) {
  final m = _hfFile.firstMatch(url);
  if (m == null) return [url];
  final (repo, file) = (m[1]!, m[2]!);
  final ms = modelscopeRepos[repo];
  final base = sourceBase(custom);
  final all = {
    'huggingface': url,
    'mirror': '$_hfMirror/$repo/resolve/main/$file',
    if (!gated && ms != null)
      'modelscope': 'https://modelscope.cn/models/$ms/resolve/master/$file',
    if (!gated && base != null) 'custom': '$base/$repo/resolve/main/$file',
  };
  return {?all[source], for (final s in _fallback) ?all[s]}.toList();
}
