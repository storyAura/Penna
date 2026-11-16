part of 'comfyui.dart';

// 编辑、参考类的工作流要先传图(视频、音频)上去:工作流里有几个加载素材的节点
// (LoadImage、LoadVideo、VHS_LoadVideo、LoadAudio 这类),就有几个要选的文件。
// 出图前用 ComfyUI 自带的 `POST /upload/image` 传到它的 input 文件夹(这个接口不挑文件类型,
// 网页传视频、音频也走它),再把节点的输入换成传上去的文件名。

/// 一个要上传素材的节点:[kind] 是 image / video / audio,[title] 是节点在 ComfyUI 里的标题,
/// [value] 是工作流里原来写的文件名(不另选文件时用它)。
typedef UploadSlot = ({
  String node,
  String type,
  String key,
  String kind,
  String title,
  String value,
});

/// 各种素材在选文件时认的后缀。
const uploadExtensions = {
  'image': ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
  'video': ['mp4', 'webm', 'mov', 'mkv', 'avi', 'm4v', 'gif'],
  'audio': ['mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac'],
};

/// 加载节点里放文件名的输入 → 素材的种类。`file` 只在视频节点上算(官方 LoadVideo)。
const _uploadKeys = {
  'image': 'image',
  'video': 'video',
  'file': 'video',
  'audio': 'audio',
};

/// 工作流里要上传素材的节点,按节点编号排(和连线的先后不一定一样,看标题分辨)。
List<UploadSlot> uploadSlots(Map<String, Object?> wf) => [
  for (final id in wf.keys.toList()..sort(_byId))
    if (wf[id] case final Map node
        when '${node['class_type']}'.toLowerCase().contains('load'))
      for (final MapEntry(key: key, value: kind) in _uploadKeys.entries)
        if (_inputs(node)[key] is String &&
            (key != 'file' ||
                '${node['class_type']}'.toLowerCase().contains('video')))
          (
            node: id,
            type: '${node['class_type']}',
            key: key,
            kind: kind,
            title: '${(node['_meta'] as Map?)?['title'] ?? ''}',
            value: _inputs(node)[key] as String,
          ),
];

extension ComfyUploads on ComfyClient {
  /// 把 [path] 传到 ComfyUI 的 input 文件夹,返回节点里该写的名字。
  /// 文件名取内容的哈希,同一个文件传几次都是同一个名字(覆盖,不越传越多)。
  Future<String> upload(String path) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException {
      throw ComfyException(tr('读不了「{0}」', [File(path).uri.pathSegments.last]));
    }
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot).toLowerCase();
    final name = 'penna-${sha1.convert(bytes).toString().substring(0, 16)}$ext';
    final boundary = 'penna-${Random().nextInt(1 << 32)}';
    String field(String key) =>
        '--$boundary\r\nContent-Disposition: form-data; name="$key"';
    final body =
        (BytesBuilder(copy: false)
              ..add(
                utf8.encode(
                  '${field('image')}; filename="$name"\r\n'
                  'Content-Type: application/octet-stream\r\n\r\n',
                ),
              )
              ..add(bytes)
              ..add(
                utf8.encode(
                  '\r\n${field('overwrite')}\r\n\r\ntrue\r\n--$boundary--\r\n',
                ),
              ))
            .takeBytes();
    final type = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    final got = await _json('POST', '/upload/image', (type, body));
    if (got is! Map || got['name'] is! String) {
      throw ComfyException(tr('ComfyUI 没收下「{0}」', [name]));
    }
    final sub = '${got['subfolder'] ?? ''}';
    return sub.isEmpty ? got['name'] as String : '$sub/${got['name']}';
  }

  /// 传好 [uploads](节点编号 → 本机路径)里的文件,换掉那几个节点的输入(不改原来的)。
  /// 对不上节点的跳过(工作流改过了)。
  Future<Map<String, Object?>> _withUploads(
    Map<String, Object?> wf,
    Map<String, String> uploads,
  ) async {
    final out = jsonDecode(jsonEncode(wf)) as Map<String, Object?>;
    for (final slot in uploadSlots(out)) {
      final path = uploads[slot.node];
      if (path == null) continue;
      _inputs(out[slot.node])[slot.key] = await upload(path);
    }
    return out;
  }
}
