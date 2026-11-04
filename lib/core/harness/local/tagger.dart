import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'tagger_catalog.dart';
import '../../../l10n/l10n.dart';

export 'tagger_catalog.dart';

// 打标模型的纯逻辑:读标签表、把图变成模型要的数、把模型给的把握筛成标签。
// 读图、跑模型在别处。各种模型的做法照 BooruDatasetTagManagerPlus 的几个 *OnnxService。

/// WD14 模型文件夹里的两个文件(扫描模型文件夹时靠它们认出 WD 模型)。
const taggerModelFile = 'model.onnx';
const taggerLabelsFile = 'selected_tags.csv';

/// 标签的分类(照 Danbooru):只留通用和角色,分级另外显示,版权、画风、元信息不要。
const tagGeneral = 0,
    tagCopyright = 3,
    tagCharacter = 4,
    tagStyle = 5,
    tagMeta = 7,
    tagRating = 9;

/// 不当成标签的:[category] 为 -1。
typedef TagLabel = ({String name, int category});

const _skipped = -1;

/// 文字的分类名 → 数字。
int categoryOf(String name) => switch (name.toLowerCase()) {
  'general' => tagGeneral,
  'character' => tagCharacter,
  'copyright' => tagCopyright,
  'style' || 'artist' => tagStyle,
  'meta' || 'quality' => tagMeta,
  'rating' => tagRating,
  _ => _skipped,
};

List<String> _lines(String text) => text.split(RegExp(r'\r?\n'));

final _csvField = RegExp(r'(?:^|,)(?:"((?:[^"]|"")*)"|([^,]*))');

/// 标签名可以带逗号和引号,不能用逗号直接切列,否则模型输出下标会错位。
List<String> _csvRow(String line) => [
  for (final m in _csvField.allMatches(line))
    m[1]?.replaceAll('""', '"') ?? m[2]!,
];

/// 按模型的种类读它的标签表,下标对着模型输出的位置。
List<TagLabel> parseLabels(TaggerKind kind, String text) =>
    List.unmodifiable(switch (kind) {
      TaggerKind.wd => parseSelectedTags(text),
      TaggerKind.pixai09 => _pixaiCsv(text),
      TaggerKind.pixai10 => _pixaiJson(text),
      TaggerKind.clV1 => _clMapping(text),
      TaggerKind.clV2 => _clVocabulary(text),
      TaggerKind.oppai => _oppaiCsv(text),
    });

/// WD 的 selected_tags.csv。v3 是 tag_id,name,category,count;老版本是 name,category。
List<TagLabel> parseSelectedTags(String csv) => [
  for (final line in _lines(csv)) ?_wdRow(_csvRow(line)),
];

TagLabel? _wdRow(List<String> parts) {
  if (parts.length < 2 || parts.first == 'tag_id' || parts.first == 'name') {
    return null;
  }
  if (parts.length >= 4 && int.tryParse(parts[0]) != null) {
    final category = int.tryParse(parts[2]);
    final name = parts[1].trim();
    if (category != null && name.isNotEmpty) {
      return (name: name, category: category);
    }
  }
  final category = int.tryParse(parts[1]);
  final name = parts[0].trim();
  return category == null || name.isEmpty
      ? null
      : (name: name, category: category);
}

/// PixAI v0.9 的 csv:id,tag_id,name,category,…(表头 id 开头)。
List<TagLabel> _pixaiCsv(String csv) => [
  for (final line in _lines(csv))
    if (_csvRow(line) case final p
        when p.length >= 4 && int.tryParse(p[0]) != null)
      if (int.tryParse(p[3]) case final category?)
        (name: p[2].trim(), category: category)
      else
        (name: p[2].trim(), category: _skipped),
];

/// 一串按下标排好的标签;缺的位置用跳过的空标签补上,免得后面的错位。
List<TagLabel> _aligned(Map<int, TagLabel> byIndex) {
  if (byIndex.isEmpty) throw FormatException(tr('标签表是空的'));
  final size = byIndex.keys.reduce(math.max) + 1;
  return [
    for (var i = 0; i < size; i++) byIndex[i] ?? (name: '', category: _skipped),
  ];
}

/// PixAI v1.0 的 tags.json:categories 里每类一段(offset、count、tags)。
List<TagLabel> _pixaiJson(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final byIndex = <int, TagLabel>{};
  for (final c in root['categories'] as List) {
    final category = categoryOf((c as Map)['name'] as String? ?? '');
    final offset = c['offset'] as int;
    for (final (i, tag) in (c['tags'] as List).indexed) {
      byIndex[offset + i] = (name: tag as String, category: category);
    }
  }
  return _aligned(byIndex);
}

/// CL v1 的 tag_mapping.json:{"0": {"tag": "...", "category": "General"}, ...}。
List<TagLabel> _clMapping(String json) => _aligned({
  for (final e in (jsonDecode(json) as Map<String, dynamic>).entries)
    if ((int.tryParse(e.key), e.value) case (final i?, final Map v))
      i: (
        name: v['tag'] as String? ?? '',
        category: categoryOf(v['category'] as String? ?? ''),
      ),
});

/// CL v2 的 model_vocabulary.json:idx_to_tag 加 tag_to_category(分类名,或分类的下标)。
List<TagLabel> _clVocabulary(String json) {
  final root = jsonDecode(json) as Map<String, dynamic>;
  final names = root['categories'] is Map
      ? (root['categories'] as Map).keys.cast<String>().toList()
      : const [
          'General',
          'Character',
          'Copyright',
          'Meta',
          'Rating',
          'Quality',
        ];
  final byTag = <String, int>{};
  // 有的版本按分类列出各自的标签。
  if (root['categories'] case final Map groups) {
    for (final e in groups.entries) {
      for (final tag in e.value is List ? e.value as List : const []) {
        byTag['$tag'] = categoryOf('${e.key}');
      }
    }
  }
  if (root['tag_to_category'] case final Map map) {
    for (final e in map.entries) {
      final v = e.value;
      byTag['${e.key}'] = v is String
          ? categoryOf(v)
          : v is int && v >= 0 && v < names.length
          ? categoryOf(names[v])
          : _skipped;
    }
  }
  return _aligned({
    for (final e in (root['idx_to_tag'] as Map).entries)
      ?int.tryParse('${e.key}'): (
        name: '${e.value}',
        category: byTag['${e.value}'] ?? _skipped,
      ),
  });
}

/// OppaiOracle 的 selected_tags.csv:index,name。没有分类,都算通用;
/// `<PAD>`、`<UNK>` 和 rating: 开头的不要。
List<TagLabel> _oppaiCsv(String csv) => _aligned({
  for (final line in _lines(csv))
    if (_csvRow(line) case final p when p.length >= 2)
      if (int.tryParse(p[0]) case final i? when i >= 0)
        i: (
          name: p[1].trim(),
          category:
              {'<pad>', '<unk>'}.contains(p[1].trim().toLowerCase()) ||
                  p[1].trim().toLowerCase().startsWith('rating:')
              ? _skipped
              : tagGeneral,
        ),
});

/// 模型要的输入:边长多少,通道在前(NCHW)还是在后(NHWC)。
/// SmilingWolf 的模型是 [1, 448, 448, 3];同结构从 PyTorch 转出来的可能是 [1, 3, 448, 448]。
({int size, bool nchw}) inputLayout(List<int> shape, {int fallback = 448}) {
  if (shape.length >= 4) {
    if (shape[3] == 3 && shape[1] > 0) return (size: shape[1], nchw: false);
    if (shape[1] == 3 && shape[2] > 0) return (size: shape[2], nchw: true);
    if (shape[1] > 0 && shape[1] == shape[2]) {
      return (size: shape[1], nchw: false);
    }
  }
  return (size: fallback, nchw: shape.length >= 4 && shape[1] == 3);
}

/// 各种模型没写在输入形状里时用的边长。
int taggerFallbackSize(TaggerModel m) => switch (m.kind) {
  TaggerKind.pixai10 => 1008,
  TaggerKind.clV2 => 384,
  TaggerKind.oppai => m.name.contains('320') ? 320 : 448,
  _ => 448,
};

/// 缩图后的长宽:长边不超过 [size],不放大。
({int width, int height}) fitInside(int width, int height, int size) {
  final scale = math.min(1.0, size / math.max(width, height));
  return (
    width: math.max(1, (width * scale).round()),
    height: math.max(1, (height * scale).round()),
  );
}

/// 这种模型要先把图缩成多大(之后再贴到 [size]×[size] 的画布上)。
({int width, int height}) taggerImageSize(
  TaggerKind kind,
  int width,
  int height,
  int size,
) {
  switch (kind) {
    case TaggerKind.pixai09 || TaggerKind.clV2:
      return (width: size, height: size);
    case TaggerKind.pixai10:
      // 照官方脚本:可以放大,取整时截掉小数。
      final scale = math.min(size / height, size / width);
      return (
        width: math.min(size, math.max(1, (width * scale).floor())),
        height: math.min(size, math.max(1, (height * scale).floor())),
      );
    case TaggerKind.clV1:
      final scale = size / math.max(width, height);
      return (
        width: math.max(1, (width * scale).round()),
        height: math.max(1, (height * scale).round()),
      );
    case TaggerKind.wd || TaggerKind.oppai:
      return fitInside(width, height, size);
  }
}

/// 喂给模型的东西:像素、它的形状,OppaiOracle 另有一张填充掩码(true 是填充的地方)。
typedef TaggerInput = ({
  Float32List pixels,
  List<int> shape,
  List<bool>? mask,
  bool transparent,
});

/// 把已经缩到 [taggerImageSize] 的图([rgba],宽 [width] 高 [height])变成 [kind] 要的输入。
/// [nchw] 只对 WD 有用(看模型的输入形状)。
TaggerInput prepareTaggerInput(
  TaggerKind kind,
  Uint8List rgba,
  int width,
  int height, {
  required int size,
  bool nchw = false,
}) {
  final transparent = hasTransparency(rgba);
  final (pad, matte, bgr, normalized) = switch (kind) {
    TaggerKind.wd => (255, 255, true, false),
    TaggerKind.pixai09 || TaggerKind.clV2 => (255, 255, false, true),
    TaggerKind.pixai10 => (0, 255, false, true),
    TaggerKind.clV1 => (255, 255, true, true),
    TaggerKind.oppai => (114, 114, false, true),
  };
  final first = kind == TaggerKind.wd ? nchw : true;
  final pixels = _canvas(
    rgba,
    width,
    height,
    size: size,
    pad: pad,
    matte: matte,
    bgr: bgr,
    normalized: normalized,
    nchw: first,
  );
  final left = (size - width) ~/ 2, top = (size - height) ~/ 2;
  return (
    pixels: pixels,
    shape: first ? [1, 3, size, size] : [1, size, size, 3],
    mask: kind == TaggerKind.oppai
        ? [
            for (var y = 0; y < size; y++)
              for (var x = 0; x < size; x++)
                x < left || x >= left + width || y < top || y >= top + height,
          ]
        : null,
    transparent: transparent,
  );
}

/// 图里有没有半透明的地方。
bool hasTransparency(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] < 255) return true;
  }
  return false;
}

/// 把图贴到 [size]×[size] 画布正中:画布底色 [pad],图里透明的地方混成 [matte]。
/// [normalized] 为真时每个值是 (x/255 - 0.5) / 0.5,否则 0~255。
Float32List _canvas(
  Uint8List rgba,
  int width,
  int height, {
  required int size,
  required int pad,
  required int matte,
  required bool bgr,
  required bool normalized,
  required bool nchw,
}) {
  double value(num v) => normalized ? (v / 255 - 0.5) / 0.5 : v.toDouble();
  final plane = size * size;
  final out = Float32List(plane * 3)..fillRange(0, plane * 3, value(pad));
  final left = (size - width) ~/ 2, top = (size - height) ~/ 2;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = rgba[i + 3] / 255;
      final back = matte * (1 - a);
      final at = (y + top) * size + x + left;
      for (var c = 0; c < 3; c++) {
        // BGR 时第 0 个通道放蓝色(rgba 里的第 2 个)。
        final v = value(rgba[i + (bgr ? 2 - c : c)] * a + back);
        out[nchw ? c * plane + at : at * 3 + c] = v;
      }
    }
  }
  return out;
}

/// WD 的老写法:白底居中,BGR 0~255。
Float32List letterboxBgr(
  Uint8List rgba,
  int width,
  int height, {
  required int size,
  bool nchw = false,
}) => prepareTaggerInput(
  TaggerKind.wd,
  rgba,
  width,
  height,
  size: size,
  nchw: nchw,
).pixels;

typedef TagScore = ({String tag, int category, double prob});

/// 推出来的标签:角色、通用标签各自按把握从高到低;[rating] 是把握最大的分级。
typedef TagResult = ({
  List<TagScore> characters,
  List<TagScore> general,
  String? rating,
});

/// 把模型输出的每个标签的把握按阈值筛出来。[logits] 为真,或输出里有不在 0~1 的值时,
/// 先过 sigmoid。名字在 [skip] 里的不要(比如透明图的 gray_background)。
TagResult decodeTags(
  List<double> scores,
  List<TagLabel> labels, {
  required double general,
  required double character,
  bool logits = false,
  Set<String> skip = const {},
}) {
  final raw = logits || scores.any((v) => v < 0 || v > 1);
  final characters = <TagScore>[], kept = <TagScore>[];
  TagScore? rating;
  for (var i = 0; i < math.min(scores.length, labels.length); i++) {
    final label = labels[i];
    if (label.category == _skipped || label.name.isEmpty) continue;
    if (skip.contains(label.name)) continue;
    final prob = raw ? 1 / (1 + math.exp(-scores[i])) : scores[i];
    final score = (tag: label.name, category: label.category, prob: prob);
    switch (label.category) {
      case tagRating:
        if (rating == null || prob > rating.prob) rating = score;
      case tagCharacter:
        if (prob >= character) characters.add(score);
      case tagGeneral:
        if (prob >= general) kept.add(score);
    }
  }
  int byProb(TagScore a, TagScore b) => b.prob.compareTo(a.prob);
  return (
    characters: List.unmodifiable(characters..sort(byProb)),
    general: List.unmodifiable(kept..sort(byProb)),
    rating: rating?.tag,
  );
}

/// 这些颜文字标签的下划线是字的一部分,不能换成空格。
const _kaomoji = {
  '0_0', '(o)_(o)', '+_+', '+_-', '._.', '<o>_<o>', '<|>_<|>', '=_=', //
  '>_<', '3_3', '6_9', '>_o', '@_@', '^_^', 'o_o', 'u_u', 'x_x', '|_|',
  '||_||',
};

/// 标签的写法:小写,下划线换成空格(颜文字除外)。
String tagText(String tag) =>
    _kaomoji.contains(tag) ? tag : tag.replaceAll('_', ' ');

/// 推出来的标签连成一条提示词:角色在前,通用标签在后,用英文逗号隔开。
/// 名字在 [without] 里的(用户取消勾选的)不要。
String tagPrompt(TagResult r, {Set<String> without = const {}}) => [
  ...r.characters,
  ...r.general,
].where((t) => !without.contains(t.tag)).map((t) => tagText(t.tag)).join(', ');
