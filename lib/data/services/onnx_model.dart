import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../l10n/l10n.dart';

class OnnxException implements Exception {
  const OnnxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 输出名按这个先后挑(打标模型常见的几种叫法),都没有就用第一个输出。
const _outputNames = [
  'probabilities',
  'output',
  'predictions',
  'prediction',
  'probs',
  'logits',
];

/// 一个加载好的打标模型。输入可以有好几个(OppaiOracle 另要一张填充掩码)。
// ponytail: 插件在 Windows 的平台线程上同步跑模型,大模型加载和推理时窗口会停顿一两秒;
// 要完全不卡得换成能在 isolate 里跑的 FFI 版 onnxruntime。也只用 CPU,要用显卡得换 DirectML 版运行库。
class OnnxModel {
  OnnxModel._(this._session, this.inputs, this._output);

  final OrtSession _session;

  /// 各个输入的名字和形状(动态的维度是 -1),按模型里的先后。
  final List<({String name, List<int> shape})> inputs;
  final String _output;

  static Future<OnnxModel> load(String path) async {
    OrtSession? created;
    try {
      final session = await OnnxRuntime().createSession(path);
      created = session;
      final outputs = [
        for (final o in await session.getOutputInfo()) o['name'] as String,
      ];
      final model = OnnxModel._(
        session,
        [
          for (final i in await session.getInputInfo())
            (
              name: i['name'] as String,
              shape: [for (final d in i['shape'] as List) (d as num).toInt()],
            ),
        ],
        _outputNames
                .map(
                  (want) =>
                      outputs.where((o) => o.toLowerCase() == want).firstOrNull,
                )
                .nonNulls
                .firstOrNull ??
            outputs.first,
      );
      created = null;
      return model;
    } on PlatformException catch (e) {
      throw OnnxException(tr('模型加载失败:{0}', [_brief(e.message)]));
    } on MissingPluginException {
      throw OnnxException(tr('这个版本没有带 ONNX 运行库'));
    } finally {
      // 完整构建成功才把所有权交给模型,读取 metadata 失败也要释放 session。
      await created?.close();
    }
  }

  /// 跑一次,返回选中的那个输出摊平后的数。[feeds] 是输入名 → (数据, 形状)。
  Future<List<double>> run(
    Map<String, ({Object data, List<int> shape})> feeds,
  ) async {
    final made = <OrtValue>[];
    try {
      final inputs = <String, OrtValue>{};
      for (final e in feeds.entries) {
        final v = await OrtValue.fromList(e.value.data, e.value.shape);
        made.add(v);
        inputs[e.key] = v;
      }
      final outputs = await _session.run(inputs);
      made.addAll(outputs.values);
      final values = await (outputs[_output] ?? outputs.values.first)
          .asFlattenedList();
      return [for (final v in values) (v as num).toDouble()];
    } on PlatformException catch (e) {
      throw OnnxException(tr('推理失败:{0}', [_brief(e.message)]));
    } finally {
      for (final v in made) {
        await v.dispose();
      }
    }
  }

  Future<void> close() => _session.close();
}

/// 运行库的报错可能很长,截一截。
String _brief(String? message) {
  final text = (message ?? tr('未知错误')).trim();
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
