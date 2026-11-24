/// Lora Manager(ComfyUI 插件)里的 LoRA 库:列表、文件夹、预览图和触发词。
///
/// 只读它的 HTTP 接口，不依赖插件内部实现:
/// - `GET /api/lm/loras/list`  分页、搜索、排序、按文件夹、只看收藏
/// - `GET /api/lm/loras/folders` 文件夹树
library;

/// 库里的一条 LoRA。
typedef LoraEntry = ({
  /// 显示名(model_name;没有时退回文件名)。
  String name,

  /// 写进工作流的名字:相对 loras 目录的路径，带扩展名，反斜杠分隔。
  String file,

  /// 文件名，不带目录和后缀。文本标签(`<lora:名字:权重>`)里用的就是它。
  String stem,

  /// 所在文件夹，用 `/` 分隔;根是空串。
  String folder,

  /// 底模(Illustrious、Flux…)，没有是空串。
  String baseModel,

  /// 预览图地址(相对 ComfyUI 的)，没有是空串。
  String preview,

  /// Civitai 的触发词。
  List<String> triggers,

  bool favorite,

  /// 用过几次(排序用)。
  int usage,
});

/// 一页结果。
typedef LoraPage = ({
  List<LoraEntry> entries,
  int total,
  int page,
  int totalPages,
});

LoraEntry? _entry(Map<String, Object?> m) {
  final file = '${m['file_path'] ?? ''}';
  final fileName = '${m['file_name'] ?? ''}';
  final folder = '${m['folder'] ?? ''}';
  final name = '${m['model_name'] ?? ''}'.trim().isEmpty
      ? fileName
      : '${m['model_name']}'.trim();
  if (fileName.isEmpty && file.isEmpty) return null;
  final civitai = m['civitai'];
  final words = civitai is Map ? civitai['trainedWords'] : null;
  return (
    name: name,
    file: _relative(file, fileName, folder),
    stem: fileName,
    folder: folder,
    baseModel: '${m['base_model'] ?? ''}',
    preview: '${m['preview_url'] ?? ''}',
    triggers: [if (words is List) for (final w in words) '$w'],
    favorite: m['favorite'] == true,
    usage: (m['usage_count'] as num?)?.toInt() ?? 0,
  );
}

/// 工作流里认的名字:file_path 里 `loras/` 之后那一段，换成反斜杠。
/// 不在 loras 目录里(额外路径)时，用文件夹 + 文件名拼一个。
String _relative(String file, String fileName, String folder) {
  final lower = file.toLowerCase();
  final at = lower.lastIndexOf('/loras/');
  if (at >= 0) return file.substring(at + 7).replaceAll('/', '\\');
  final tail = folder.replaceAll('/', '\\');
  final withExt = file.endsWith('.safetensors') || file.isEmpty
      ? fileName
      : fileName;
  return tail.isEmpty ? withExt : '$tail\\$withExt';
}

/// 读 `/api/lm/loras/list` 的结果。
LoraPage parseLoraPage(Object? json) {
  final map = json is Map ? json : const {};
  final items = map['items'];
  return (
    entries: [
      if (items is List)
        for (final raw in items)
          if (raw is Map) ?_entry(raw.cast<String, Object?>()),
    ],
    total: (map['total'] as num?)?.toInt() ?? 0,
    page: (map['page'] as num?)?.toInt() ?? 1,
    totalPages: (map['total_pages'] as num?)?.toInt() ?? 1,
  );
}

/// 读 `/api/lm/loras/folders` 的结果(第一项一般是空串 = 根)。
List<String> parseLoraFolders(Object? json) {
  final folders = json is Map ? json['folders'] : null;
  if (folders is! List) return const [];
  return [for (final f in folders) '$f'];
}

/// 名字的比较用键:去掉目录、后缀，小写。
/// 工作流里的 `MOSS\tool\x.safetensors` 和标签里的 `x` 要能对上。
String loraKey(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  return base.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '').toLowerCase();
}
