import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../core/harness/local/florence.dart';
import '../../l10n/l10n.dart';

/// 跑 Florence-2 的四个 ONNX 模型:看图 → 文字嵌入 → 编码 → 一个字一个字地解码。
/// 解码器的缓存(past_key_values)一直留在运行库那边,只把每一步的打分拿回来挑字。
// ponytail: 只做贪心解码(官方用 3 路 beam search);标签质量明显不够时再加。
class FlorenceEngine {
  FlorenceEngine._({
    required this.vision,
    required this.embed,
    required this.encoder,
    required this.decoder,
    required this.tokenizer,
    required this.past,
  });

  final OrtSession vision, embed, encoder, decoder;
  final FlorenceTokenizer tokenizer;

  /// 解码器缓存的输入名和形状(第 1 维是头数,第 3 维是每头的维度)。
  final Map<String, List<int>> past;

  /// [dir] 里放着四个 ONNX;分词器在 [dir] 或它的上一层。
  static Future<FlorenceEngine> load(String dir) async {
    final sep = Platform.pathSeparator;
    final tokenizerFile = [
      File('$dir$sep$florenceTokenizer'),
      File('${Directory(dir).parent.path}$sep$florenceTokenizer'),
    ].where((f) => f.existsSync()).firstOrNull;
    if (tokenizerFile == null) {
      throw FlorenceException(tr('缺少 tokenizer.json'));
    }
    final ort = OnnxRuntime();
    final sessions = <OrtSession>[];
    try {
      for (final name in florenceOnnx) {
        sessions.add(await ort.createSession('$dir$sep$name'));
      }
      final decoder = sessions[0];
      return FlorenceEngine._(
        decoder: decoder,
        vision: sessions[1],
        embed: sessions[2],
        encoder: sessions[3],
        tokenizer: FlorenceTokenizer.parse(await tokenizerFile.readAsString()),
        past: {
          for (final i in await decoder.getInputInfo())
            if ((i['name'] as String).startsWith('past_key_values.'))
              i['name'] as String: [
                for (final d in i['shape'] as List) (d as num).toInt(),
              ],
        },
      );
    } on Object catch (e) {
      for (final session in sessions.reversed) {
        await session.close();
      }
      if (e is PlatformException) {
        throw FlorenceException(tr('模型加载失败:{0}', [_brief(e.message)]));
      }
      rethrow;
    }
  }

  Future<void> close() async {
    for (final s in [vision, embed, encoder, decoder]) {
      await s.close();
    }
  }

  /// 用指令 [task] 看一张图([pixels] 是 [florencePixels] 的结果)。
  /// [stale] 返回 true 时中途停下(比如用户换了图),返回已经出的字。
  Future<String> caption(
    Float32List pixels,
    String task, {
    bool Function()? stale,
  }) async {
    final made = <OrtValue>[];
    Future<OrtValue> value(Object data, List<int> shape) async {
      final v = await OrtValue.fromList(data, shape);
      made.add(v);
      return v;
    }

    Future<OrtValue> one(OrtSession s, Map<String, OrtValue> feeds) async {
      final out = await s.run(feeds);
      made.addAll(out.values);
      return out.values.first;
    }

    try {
      final size = florenceImageSize;
      final image = await one(vision, {
        'pixel_values': await value(pixels, [1, 3, size, size]),
      });
      final ids = tokenizer.encodePrompt(florencePrompt(task));
      final text = await one(embed, {
        'input_ids': await value(Int64List.fromList(ids), [1, ids.length]),
      });
      // 图的特征和指令的嵌入首尾相接,一起交给编码器。
      final a = await _floats(image), b = await _floats(text);
      final width = image.shape.last;
      final length = (a.length + b.length) ~/ width;
      final joined = Float32List(a.length + b.length)
        ..setAll(0, a)
        ..setAll(a.length, b);
      final mask = await value(Int64List(length)..fillRange(0, length, 1), [
        1,
        length,
      ]);
      final hidden = await one(encoder, {
        'inputs_embeds': await value(joined, [1, length, width]),
        'attention_mask': mask,
      });
      final tokens = await _generate(hidden, mask, stale);
      return tokenizer.decode(tokens).trim();
    } on PlatformException catch (e) {
      throw FlorenceException(tr('推理失败:{0}', [_brief(e.message)]));
    } finally {
      for (final v in made) {
        await v.dispose();
      }
    }
  }

  Future<List<int>> _generate(
    OrtValue hidden,
    OrtValue mask,
    bool Function()? stale,
  ) async {
    // 一开始缓存是空的:第 2 维(已经出的字数)为 0。
    final cache = <String, OrtValue>{};
    final generated = [florenceDecoderStart];
    try {
      for (final e in past.entries) {
        cache[e.key] = await OrtValue.fromList(Float32List(0), [
          1,
          e.value[1],
          0,
          e.value[3],
        ]);
      }
      for (var step = 0; step < florenceMaxTokens; step++) {
        if (stale?.call() ?? false) break;
        final made = <OrtValue>[];
        try {
          final ids = await OrtValue.fromList(
            Int64List.fromList([generated.last]),
            [1, 1],
          );
          made.add(ids);
          final useCache = await OrtValue.fromList([step > 0], [1]);
          made.add(useCache);
          final embeds = await embed.run({'input_ids': ids});
          made.addAll(embeds.values);
          final stepEmbeds = embeds.values.first;
          final out = await decoder.run({
            'encoder_attention_mask': mask,
            'encoder_hidden_states': hidden,
            'inputs_embeds': stepEmbeds,
            'use_cache_branch': useCache,
            ...cache,
          });
          made.addAll(out.values);
          final logits = out['logits']!;
          final scores = await _floats(logits);
          for (final e in out.entries) {
            final name = e.key.replaceFirst('present.', 'past_key_values.');
            // 用缓存的那几步,交叉注意力那几个回来的是空的占位:留着第一次的真值。
            if (e.key.startsWith('present.') &&
                cache.containsKey(name) &&
                e.value.shape.every((d) => d > 0)) {
              await cache[name]!.dispose();
              cache[name] = e.value;
              made.remove(e.value);
            }
          }
          // 只要最后一个位置那一行(词表那么长)。
          final row = scores.sublist(scores.length - logits.shape.last);
          final next = generated.length == 1
              ? florenceBos
              : argmaxExcept(row, bannedNext(generated));
          generated.add(next);
          if (next == florenceEos) break;
        } finally {
          for (final v in made) {
            await v.dispose();
          }
        }
      }
    } finally {
      for (final v in cache.values) {
        await v.dispose();
      }
    }
    return generated;
  }
}

Future<List<double>> _floats(OrtValue v) async {
  final f = v.dataType == OrtDataType.float32
      ? v
      : await v.to(OrtDataType.float32);
  try {
    return [for (final x in await f.asFlattenedList()) (x as num).toDouble()];
  } finally {
    if (!identical(f, v)) await f.dispose();
  }
}

String _brief(String? message) {
  final text = (message ?? tr('未知错误')).trim();
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}
