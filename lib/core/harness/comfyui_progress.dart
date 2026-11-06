import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 出图进度:HTTP 只能问到「做完没有」,步数要从 ComfyUI 的 WebSocket(`/ws?clientId=…`)听。
// 用到的消息(文字帧;二进制帧是预览图,不要):
//   execution_cached {nodes}          这些节点用了缓存,算做完
//   executing        {node}           开始跑某个节点(node 为 null 是整单做完)
//   progress         {node,value,max} 采样器这类节点里的步数
// 照 Loomic 的 comfyui-progress.ts。听不到只是没有进度条,不影响出图。

/// 进度:0 到 1。
typedef ComfyProgress = double;

/// 时间几乎都花在采样器上,别的节点很快:进度条大半按采样步数算,小半按做完的节点数。
// ponytail: 按类名猜哪些是采样器;要准就按节点类型给权重,或参考上一次跑同一个工作流的耗时。
final _samplerNode = RegExp('sampler|detailer|upscale', caseSensitive: false);
const _nodeShare = 0.1;

/// 把一条条消息折算成整单的进度。
class ComfyProgressTracker {
  ComfyProgressTracker(Map<String, Object?> workflow)
    : _ids = workflow.keys.toList(),
      _samplers = workflow.values
          .where((n) => n is Map && _samplerNode.hasMatch('${n['class_type']}'))
          .length;

  final List<String> _ids;
  final int _samplers;
  final _done = <String>{};
  final _steps = <String, double>{};
  String? _current;

  /// 喂一条消息;进度没变时返回 null。
  ComfyProgress? handle(String type, Map data) {
    switch (type) {
      case 'execution_cached':
        for (final id in data['nodes'] as List? ?? const []) {
          _done.add('$id');
        }
      case 'executing':
        if (_current != null) _done.add(_current!);
        final node = data['node'];
        _current = node == null ? null : '$node';
      case 'progress':
        final max = data['max'], value = data['value'];
        // 只有一步的(读模型)算不上采样器。
        if (data['node'] == null || max is! num || max < 2 || value is! num) {
          return null;
        }
        _steps['${data['node']}'] = (value / max).clamp(0, 1).toDouble();
      default:
        return null;
    }
    final slots = _samplers > _steps.length ? _samplers : _steps.length;
    final steps = slots == 0
        ? 0.0
        : _steps.values.fold(0.0, (a, b) => a + b) / slots;
    final nodes = _ids.isEmpty ? 0.0 : (_done.length / _ids.length).clamp(0, 1);
    return _nodeShare * nodes + (1 - _nodeShare) * steps;
  }
}

/// 连上进度的 WebSocket,连上(或 3 秒没连上)才返回,好在排队之前就开始听。
/// 返回的函数用来断开。只报 [promptId] 那一单的(同一条连接上也有别人的)。
Future<void Function()> watchComfyProgress(
  String root,
  String clientId,
  Map<String, Object?> workflow, {
  required String? Function() promptId,
  required void Function(ComfyProgress) onProgress,
  String key = '',
}) async {
  final tracker = ComfyProgressTracker(workflow);
  final WebSocket socket;
  try {
    socket = await WebSocket.connect(
      '${root.replaceFirst(RegExp('^http'), 'ws')}/ws?clientId=$clientId',
      headers: {
        if (key.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $key',
      },
    ).timeout(const Duration(seconds: 3));
  } on Object {
    return () {};
  }
  final sub = socket.listen(
    (frame) {
      if (frame is! String) return;
      try {
        final message = jsonDecode(frame);
        if (message is! Map || message['data'] is! Map) return;
        final data = message['data'] as Map;
        final mine = promptId();
        if (mine != null &&
            data['prompt_id'] != null &&
            data['prompt_id'] != mine) {
          return;
        }
        final p = tracker.handle('${message['type']}', data);
        if (p != null) onProgress(p);
      } on FormatException {
        // 不是 JSON:不管。
      }
    },
    onError: (Object _) {},
    cancelOnError: true,
  );
  return () {
    unawaited(sub.cancel());
    unawaited(socket.close());
  };
}
