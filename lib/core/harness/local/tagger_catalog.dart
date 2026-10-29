// 「Tag 反推」能用的打标模型,照 BooruDatasetTagManagerPlus 的清单(OnnxTaggerCatalog 等)。
// 名字带系列前缀,阈值取 BDTM 用的默认值,大小取自 HuggingFace(只用来显示)。

/// 几种模型各自的看图方式和标签表格式,见 tagger.dart 的 [prepareTaggerInput]。
enum TaggerKind {
  /// SmilingWolf 的 WD14:白底居中、不放大,BGR 0~255,标签表 selected_tags.csv。
  wd,

  /// PixAI v0.9:直接拉成 448,RGB 归一化到 -1~1,标签表是 PixAI 自己的 csv。
  pixai09,

  /// PixAI v1.0:等比缩放(可放大)、白底、居中在黑色方块上,RGB,输出要过 sigmoid,标签表 tags.json。
  pixai10,

  /// CL tagger v1:白色正方形居中,BGR 归一化,输出要过 sigmoid,标签表 tag_mapping.json。
  clV1,

  /// CL tagger v2(SigLIP2):直接拉伸,RGB 归一化,输出要过 sigmoid,标签表 model_vocabulary.json。
  clV2,

  /// OppaiOracle:不放大、灰底(114)居中,RGB 归一化,另给一张「哪里是填充」的掩码;只有一个阈值。
  oppai,
}

/// 一个打标模型。[files] 是要下载的文件(仓库里的路径),第一个是模型本体,
/// [labels] 是其中的标签表;[size] 是大约多大(显示用)。
/// [gated] 的仓库要先在 HuggingFace 上申请访问,下载时带上 Token。
typedef TaggerModel = ({
  String id,
  String series,
  String name,
  String repo,
  String note,
  TaggerKind kind,
  List<String> files,
  String labels,
  int size,
  double general,
  double character,
  bool gated,
});

TaggerModel _wd(
  String repo,
  String name,
  double general,
  int size, {
  double character = 0.85,
  String note = '',
}) => (
  id: 'SmilingWolf/$repo',
  series: 'WD14',
  name: '[WD14] $name',
  repo: 'SmilingWolf/$repo',
  note: note,
  kind: TaggerKind.wd,
  files: const ['model.onnx', 'selected_tags.csv'],
  labels: 'selected_tags.csv',
  size: size,
  general: general,
  character: character,
  gated: false,
);

/// 内置的打标模型,按系列排好。WD14 的 id 就是仓库名(和以前存的设置对得上)。
final taggerModels = <TaggerModel>[
  _wd('wd-v1-4-convnext-tagger', 'convnext v1', 0.35, 377430976),
  _wd('wd-v1-4-convnext-tagger-v2', 'convnext v2', 0.35, 388074311),
  _wd('wd-v1-4-convnextv2-tagger-v2', 'convnextv2 v2', 0.35, 388733784),
  _wd('wd-v1-4-swinv2-tagger-v2', 'swinv2 v2', 0.35, 455663058),
  _wd('wd-v1-4-vit-tagger', 'vit v1', 0.35, 365661552),
  _wd('wd-v1-4-vit-tagger-v2', 'vit v2', 0.35, 373541865),
  _wd('wd-v1-4-moat-tagger-v2', 'moat v2', 0.35, 326451246),
  _wd('wd-vit-tagger-v3', 'vit v3', 0.25, 378844778, note: '最快'),
  _wd('wd-swinv2-tagger-v3', 'swinv2 v3', 0.25, 467769446),
  _wd('wd-convnext-tagger-v3', 'convnext v3', 0.25, 395299200),
  _wd('wd-vit-large-tagger-v3', 'vit-large v3', 0.26, 1260954141),
  _wd(
    'wd-eva02-large-tagger-v3',
    'eva02-large v3',
    0.52,
    1260744467,
    note: '最准',
  ),
  (
    id: 'Misaka41Z/wd-eva02-tagger-2026-canary-onnx-v2',
    series: 'WD14',
    name: '[WD14] eva02-large 2026 canary',
    repo: 'Misaka41Z/wd-eva02-tagger-2026-canary-onnx-v2',
    note: '词表更新到 2026-05',
    kind: TaggerKind.wd,
    files: const ['model.onnx', 'selected_tags.csv'],
    labels: 'selected_tags.csv',
    size: 1309715819,
    general: 0.61,
    character: 0.61,
    gated: false,
  ),
  (
    id: 'pixai:v0.9',
    series: 'PixAI',
    name: '[PixAI] pixai-tagger v0.9',
    repo: 'deepghs/pixai-tagger-v0.9-onnx',
    note: '',
    kind: TaggerKind.pixai09,
    files: const ['model.onnx', 'selected_tags.csv'],
    labels: 'selected_tags.csv',
    size: 1271962722,
    general: 0.3,
    character: 0.85,
    gated: false,
  ),
  (
    id: 'pixai:v1.0',
    series: 'PixAI',
    name: '[PixAI] pixai-tagger v1.0',
    repo: 'noaione/pixai-tagger-v1.0-onnx',
    note: '',
    kind: TaggerKind.pixai10,
    files: const ['model.onnx', 'model.onnx.data', 'tags.json'],
    labels: 'tags.json',
    size: 1958572964,
    general: 0.17,
    character: 0.27,
    gated: false,
  ),
  (
    id: 'cl:Nonene/cl_tagger:1_02',
    series: 'CL',
    name: '[CL] cl_tagger v1.02',
    repo: 'Nonene/cl_tagger',
    note: '',
    kind: TaggerKind.clV1,
    files: const [
      'cl_tagger_1_02/model.onnx',
      'cl_tagger_1_02/tag_mapping.json',
    ],
    labels: 'cl_tagger_1_02/tag_mapping.json',
    size: 1429949053,
    general: 0.45,
    character: 0.45,
    gated: false,
  ),
  for (final v in ['v2_00', 'v2_01a'])
    (
      id: 'cl:cella110n/cl_tagger_v2:$v',
      series: 'CL',
      name: '[CL] cl_tagger_v2 ${v.replaceFirst('v2_0', 'v2.0')} 🔒',
      repo: 'cella110n/cl_tagger_v2',
      note: '需要在 HuggingFace 申请访问',
      kind: TaggerKind.clV2,
      files: [
        '$v/model.onnx',
        '$v/model.onnx.data',
        '$v/model_vocabulary.json',
      ],
      labels: '$v/model_vocabulary.json',
      size: 2213000000,
      general: 0.55,
      character: 0.55,
      gated: true,
    ),
  for (final (v, px, size, threshold) in [
    ('V1', 320, 992126951, 0.55),
    ('V1.1', 448, 993699817, 0.65),
  ])
    (
      id: 'oo:Grio43/OppaiOracle:${v.toLowerCase()}',
      series: 'OppaiOracle',
      name: '[OO] OppaiOracle $v ($px)',
      repo: 'Grio43/OppaiOracle',
      note: '',
      kind: TaggerKind.oppai,
      files: ['${v}_onnx/model.onnx', '${v}_onnx/selected_tags.csv'],
      labels: '${v}_onnx/selected_tags.csv',
      size: size,
      general: threshold,
      character: threshold,
      gated: false,
    ),
];
