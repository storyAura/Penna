import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../l10n/l10n.dart';
import 'comfyui_progress.dart';

export 'comfyui_progress.dart' show ComfyProgress;

// 把 ComfyUI 当出图的后端:直接用它自带的 HTTP 接口,不用装插件,也不走 MCP。
// POST /prompt 排队 → 轮询 GET /history/{id} → GET /view 下载图片。
// 云端的 ComfyUI(租的显卡机器)一样是这套接口,地址换掉就行;Key 给它前面的反向代理用。
// ponytail: 官方的 Comfy Cloud(cloud.comfy.org)接口不一样,没接;要接时另写一个 client。

/// 工作流里写着这个记号的地方会换成提示词。
const comfyPromptMark = '{{prompt}}';

/// 冷启动要先把几个 GB 的模型读进显存,等久一点。
const comfyMaxWait = Duration(minutes: 10);

/// Agent 要出图时在回复里写的标签。
const generateImageTag = 'generate-image';

/// 拆出回复里的 `<generate-image>…</generate-image>`(也认 `<generate-image/>`):
/// [asked] 是写了这个标签,[prompt] 是里面写的提示词(空的是用眼前这页的最终提示词)。
/// 流式时半截的标签先不显示。
({String prose, bool asked, String prompt}) splitGenerate(String reply) {
  final full = RegExp(
    '<$generateImageTag\\s*/>|<$generateImageTag\\s*>([\\s\\S]*?)</$generateImageTag>',
  );
  final found = full.allMatches(reply).toList();
  var prose = reply.replaceAll(full, '');
  const open = '<$generateImageTag';
  final half = prose.indexOf(open);
  if (half >= 0) prose = prose.substring(0, half);
  for (var n = open.length - 1; n > 1; n--) {
    if (prose.endsWith(open.substring(0, n))) {
      prose = prose.substring(0, prose.length - n);
      break;
    }
  }
  return (
    prose: prose.trim(),
    asked: found.isNotEmpty,
    prompt: found.isEmpty ? '' : (found.last[1] ?? '').trim(),
  );
}

/// 给用户看的错误;不含 Key。
class ComfyException implements Exception {
  const ComfyException(this.message, {this.canceled = false});

  final String message;

  /// 用户点了停止。
  final bool canceled;

  @override
  String toString() => message;
}

/// 出的一张图:ComfyUI 里的文件名和内容。
typedef ComfyImage = ({String name, Uint8List bytes});

typedef _Node = Map<String, Object?>;

/// 读用户导入的工作流。只认「导出 (API)」的格式:一张"节点编号 → 节点"的表,
/// 每个节点有 class_type。普通保存的(带 nodes 列表)要重新导出。
Map<String, Object?> parseApiWorkflow(String text) {
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw ComfyException(tr('不是有效的工作流 JSON'));
  }
  if (json is! Map<String, Object?>) {
    throw ComfyException(tr('不是有效的工作流 JSON'));
  }
  if (json['nodes'] is List) {
    throw ComfyException(tr('这是普通保存的工作流,请在 ComfyUI 里用「导出 (API)」重新导出'));
  }
  final ok =
      json.isNotEmpty &&
      json.values.every((n) => n is Map && n['class_type'] is String);
  if (!ok) throw ComfyException(tr('不是 ComfyUI 的 API 格式工作流'));
  return json;
}

/// 没导入工作流时用的:最基本的文生图,模型用 ComfyUI 里的 [checkpoint]。
Map<String, Object?> defaultWorkflow(String checkpoint) => {
  '4': {
    'class_type': 'CheckpointLoaderSimple',
    'inputs': {'ckpt_name': checkpoint},
  },
  '6': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': comfyPromptMark,
      'clip': ['4', 1],
    },
  },
  '7': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'lowres, bad anatomy, bad hands, worst quality, low quality',
      'clip': ['4', 1],
    },
  },
  '5': {
    'class_type': 'EmptyLatentImage',
    'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1},
  },
  '3': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 0,
      'steps': 25,
      'cfg': 6,
      'sampler_name': 'euler_ancestral',
      'scheduler': 'normal',
      'denoise': 1,
      'model': ['4', 0],
      'positive': ['6', 0],
      'negative': ['7', 0],
      'latent_image': ['5', 0],
    },
  },
  '8': {
    'class_type': 'VAEDecode',
    'inputs': {
      'samples': ['3', 0],
      'vae': ['4', 2],
    },
  },
  '9': {
    'class_type': 'SaveImage',
    'inputs': {
      'filename_prefix': 'Penna',
      'images': ['8', 0],
    },
  },
};

int _byId(String a, String b) {
  final x = int.tryParse(a), y = int.tryParse(b);
  return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
}

_Node? _linked(Map<String, Object?> wf, Object? link) =>
    link is List && link.isNotEmpty ? wf['${link[0]}'] as _Node? : null;

_Node _inputs(Object? node) =>
    (node as Map)['inputs'] as _Node? ?? <String, Object?>{};

/// 正面提示词框:从采样器的 positive(Flux 的 BasicGuider 是 conditioning)顺着线往上找,
/// 最多走 4 个节点(中间可以隔着 FluxGuidance 这类),碰到第一个有文字框的节点。
_Node? _positiveTextNode(Map<String, Object?> wf) {
  final ids = wf.keys.toList()..sort(_byId);
  for (final id in ids) {
    final node = wf[id] as Map;
    final inputs = _inputs(node);
    var at = _linked(
      wf,
      inputs['positive'] ??
          (node['class_type'] == 'BasicGuider' ? inputs['conditioning'] : null),
    );
    for (var hops = 0; at != null && hops < 4; hops++) {
      final own = _inputs(at);
      if (own['text'] is String || own['text_g'] is String) return own;
      at = _linked(wf, own['conditioning']);
    }
  }
  return null;
}

/// 准备好排队的一份工作流(不改原来的):
/// - 提示词放进写着 `{{prompt}}` 的地方;没有这个记号就放进正面提示词框;
/// - 所有 seed / noise_seed 换成随机数,不然 ComfyUI 把重复的单子当成做过的,什么都不出。
/// 两处都找不到放提示词的地方时抛 [ComfyException]。
Map<String, Object?> prepareWorkflow(
  Map<String, Object?> workflow,
  String prompt, {
  Random? random,
}) {
  final wf = jsonDecode(jsonEncode(workflow)) as Map<String, Object?>;
  final dice = random ?? Random();
  var marked = false;
  for (final node in wf.values) {
    final inputs = _inputs(node);
    for (final key in inputs.keys.toList()) {
      final value = inputs[key];
      if (value is String && value.contains(comfyPromptMark)) {
        inputs[key] = value.replaceAll(comfyPromptMark, prompt);
        marked = true;
      } else if ((key == 'seed' || key == 'noise_seed') && value is num) {
        inputs[key] = dice.nextInt(1 << 32);
      }
    }
  }
  if (marked) return wf;
  final box = _positiveTextNode(wf);
  if (box == null) {
    throw ComfyException(
      tr('找不到正面提示词框:在那个框里写上 {0},再导出 (API)', [comfyPromptMark]),
    );
  }
  for (final key in const ['text', 'text_g', 'text_l']) {
    if (box[key] is String) box[key] = prompt;
  }
  return wf;
}

/// 一次运行的结果里要下载的图:有存下来的(SaveImage,type 是 output)就只要它们,
/// 没有才要预览图(PreviewImage,type 是 temp)。
List<Map<String, Object?>> pickOutputImages(Object? outputs) {
  final files = [
    if (outputs is Map)
      for (final out in outputs.values)
        if (out is Map && out['images'] is List)
          for (final f in out['images'] as List)
            if (f is Map && f['filename'] is String) f.cast<String, Object?>(),
  ];
  final saved = files.where((f) => f['type'] == 'output').toList();
  return saved.isNotEmpty ? saved : files;
}

/// ComfyUI 校验不过时会写明哪个节点哪个输入不对:留下这部分,截短。
String describeComfyError(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final nodes = [
        if (json['node_errors'] is Map)
          for (final n in (json['node_errors'] as Map).values)
            if (n is Map && n['errors'] is List)
              for (final e in n['errors'] as List)
                if (e is Map)
                  '${n['class_type']}:${e['message']} ${e['details'] ?? ''}'
                      .trim(),
      ];
      final error = json['error'];
      final message = error is Map ? '${error['message'] ?? ''}' : '';
      final all = [message, ...nodes].where((s) => s.isNotEmpty).join(tr(';'));
      if (all.isNotEmpty) return _cut(all, 300);
    }
  } on FormatException {
    // 不是 JSON:下面照原文截短。
  }
  return _cut(body, 160);
}

String _cut(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

/// 连一台 ComfyUI。[url] 是本机的 `http://127.0.0.1:8188` 或云端的地址。
class ComfyClient {
  ComfyClient(String url, {this.key = ''})
    : _root = url.trim().replaceAll(RegExp(r'/+$'), '');

  final String _root;
  final String key;

  /// 两次问「做好了吗」之间等多久(测试里改短)。
  Duration poll = const Duration(seconds: 1);

  Future<HttpClientResponse> _open(
    HttpClient http,
    String method,
    String path, [
    Object? body,
  ]) async {
    final uri = Uri.tryParse('$_root$path');
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      throw ComfyException(tr('地址要以 http:// 或 https:// 开头'));
    }
    try {
      final req = await http.openUrl(method, uri);
      if (key.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      }
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      return await req.close();
    } on SocketException {
      throw ComfyException(tr('连不上 ComfyUI({0}),请确认它已启动、地址正确', [_root]));
    } on HttpException {
      throw ComfyException(tr('连不上 ComfyUI({0}),请确认它已启动、地址正确', [_root]));
    }
  }

  Future<Uint8List> _send(String method, String path, [Object? body]) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final res = await _open(http, method, path, body);
      final bytes = await res.fold(BytesBuilder(), (b, d) => b..add(d));
      final data = bytes.takeBytes();
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw ComfyException(
          tr('ComfyUI 拒绝了请求({0}),请检查 Key', [res.statusCode]),
        );
      }
      if (res.statusCode >= 300) {
        throw ComfyException(
          tr('ComfyUI 返回 {0}:{1}', [
            res.statusCode,
            describeComfyError(utf8.decode(data, allowMalformed: true)),
          ]),
        );
      }
      return data;
    } finally {
      http.close(force: true);
    }
  }

  Future<Object?> _json(String method, String path, [Object? body]) async {
    final text = utf8.decode(
      await _send(method, path, body),
      allowMalformed: true,
    );
    try {
      return jsonDecode(text);
    } on FormatException {
      throw ComfyException(tr('ComfyUI 返回的不是 JSON,地址可能填错了'));
    }
  }

  /// 测试连接:能连上就返回 ComfyUI 的版本(老版本不报版本时是空串)。
  Future<String> version() async {
    final stats = await _json('GET', '/system_stats');
    final system = stats is Map ? stats['system'] : null;
    return system is Map ? '${system['comfyui_version'] ?? ''}' : '';
  }

  /// ComfyUI 里放着的大模型,内置的文生图用第一个。
  Future<List<String>> checkpoints() async {
    final info = await _json('GET', '/object_info/CheckpointLoaderSimple');
    // 老写法 [[名字…], {…}],新写法 ["COMBO", {options: [名字…]}]。
    final spec =
        (((info as Map?)?['CheckpointLoaderSimple'] as Map?)?['input']
            as Map?)?['required']?['ckpt_name'];
    final names = spec is List && spec.isNotEmpty
        ? spec[0] is List
              ? spec[0] as List
              : (spec.length > 1 && spec[1] is Map
                    ? (spec[1] as Map)['options']
                    : null)
        : null;
    return [
      if (names is List)
        for (final n in names) '$n',
    ];
  }

  /// 用 [workflow](导入的 API 格式全文;空的用内置文生图)出图,返回出的每一张。
  /// [canceled] 返回 true 时把单子从队列里撤掉(正在跑的就打断),抛 canceled 的 [ComfyException]。
  /// [onProgress] 报整单的进度(0 到 1),听不到 WebSocket 时不报。
  Future<List<ComfyImage>> run(
    String workflow,
    String prompt, {
    bool Function()? canceled,
    void Function(ComfyProgress)? onProgress,
  }) async {
    final Map<String, Object?> base;
    if (workflow.trim().isEmpty) {
      final models = await checkpoints();
      if (models.isEmpty) throw ComfyException(tr('ComfyUI 里还没有模型'));
      base = defaultWorkflow(models.first);
    } else {
      base = parseApiWorkflow(workflow);
    }
    final prepared = prepareWorkflow(base, prompt);
    // 进度按 client_id 发到对应的 WebSocket 上:先连上再排队。
    final clientId = 'penna-${Random().nextInt(1 << 32)}';
    String? id;
    final stopWatching = onProgress == null
        ? () {}
        : await watchComfyProgress(
            _root,
            clientId,
            prepared,
            promptId: () => id,
            onProgress: onProgress,
            key: key,
          );
    final Object? outputs;
    try {
      final queued = await _json('POST', '/prompt', {
        'prompt': prepared,
        'client_id': clientId,
      });
      final got = queued is Map ? queued['prompt_id'] : null;
      if (got is! String) throw ComfyException(tr('ComfyUI 没有返回任务编号'));
      id = got;
      outputs = await _wait(got, canceled);
    } finally {
      stopWatching();
    }
    final files = pickOutputImages(outputs);
    if (files.isEmpty) {
      throw ComfyException(tr('工作流跑完了,但没有出图:请确认里面有保存图像的节点'));
    }
    return [
      for (final f in files)
        (
          name: f['filename'] as String,
          bytes: await _send(
            'GET',
            '/view?${Uri(queryParameters: {'filename': f['filename'] as String, 'subfolder': '${f['subfolder'] ?? ''}', 'type': '${f['type'] ?? 'output'}'}).query}',
          ),
        ),
    ];
  }

  /// 等单子做完,返回它的 outputs。
  Future<Object?> _wait(String id, bool Function()? canceled) async {
    final deadline = DateTime.now().add(comfyMaxWait);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(poll);
      if (canceled?.call() ?? false) {
        await _cancel(id);
        throw ComfyException(tr('已停止出图'), canceled: true);
      }
      // 做完之前是空的。
      final history = await _json('GET', '/history/$id');
      final entry = history is Map ? history[id] : null;
      if (entry is! Map) continue;
      final status = entry['status'];
      if (status is Map && status['status_str'] == 'error') {
        throw ComfyException(tr('工作流执行失败:{0}', [_failure(status)]));
      }
      return entry['outputs'];
    }
    throw ComfyException(tr('ComfyUI 超过 {0} 分钟没有出图', [comfyMaxWait.inMinutes]));
  }

  String _failure(Map status) {
    for (final m in status['messages'] as List? ?? const []) {
      if (m is List && m.length > 1 && m[0] == 'execution_error') {
        final d = m[1];
        if (d is Map) {
          return _cut('${d['node_type']}:${d['exception_message']}', 300);
        }
      }
    }
    return tr('未知错误');
  }

  /// 撤掉单子:还在排队就从队列里删,正在跑的才打断(老版本的 /interrupt 会打断别人的)。
  Future<void> _cancel(String id) async {
    try {
      final queue = await _json('GET', '/queue');
      final running = [
        if (queue is Map && queue['queue_running'] is List)
          for (final item in queue['queue_running'] as List)
            if (item is List && item.length > 1) item[1],
      ].contains(id);
      await _send('POST', '/queue', {
        'delete': [id],
      });
      if (running) await _send('POST', '/interrupt', {'prompt_id': id});
    } on ComfyException {
      // 撤不掉就让它跑完,结果不要了。
    }
  }
}
