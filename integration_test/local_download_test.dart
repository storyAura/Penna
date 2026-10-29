// 真下载、真推理:从 ModelScope 下打标模型和 Florence-2,再拿它们给一张图反推。
// 验证「下载来源」换成 ModelScope 后下来的文件能直接用(要联网,下约 1.5 GB)。
//
// 跑法(Windows;路径里有中文时先 subst 到别的盘符):
//
//   $env:PENNA_HOME = "$env:TEMP\penna-dl"; $env:PENNA_TEST_DOWNLOAD = "1"
//   flutter test integration_test/local_download_test.dart -d windows
//
// 不给 PENNA_TEST_DOWNLOAD 就跳过,所以放在仓库里不会影响别人。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/core/harness/local/tagger.dart';
import 'package:penna/ui/features/local/local_model.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final on = Platform.environment['PENNA_TEST_DOWNLOAD'] == '1';
  final home = Platform.environment['PENNA_HOME'];

  Future<LocalModel> fresh() async {
    final model = LocalModel(
      dir: Directory(home!),
      streamChat: (_) => const Stream.empty(),
    )..source = 'modelscope';
    final bytes = (await rootBundle.load('assets/avatar.png')).buffer
        .asUint8List();
    model.setImage(
      Attachment.image(name: 'avatar.png', mime: 'image/png', bytes: bytes),
    );
    return model;
  }

  testWidgets('从 ModelScope 下 WD14 打标模型,给图打标', (tester) async {
    if (!on || home == null) {
      markTestSkipped('没给 PENNA_TEST_DOWNLOAD=1 / PENNA_HOME');
      return;
    }
    await tester.runAsync(() async {
      final model = await fresh();
      final vit = taggerModels.firstWhere(
        (m) => m.id == 'SmilingWolf/wd-vit-tagger-v3',
      );
      final watch = Stopwatch()..start();
      expect(await model.downloadTagger(vit), isNull, reason: '下载失败');
      debugPrint('=== 打标模型下载用了 ${watch.elapsed.inSeconds} 秒');
      model.pickTagger(vit.id);
      expect(await model.runTagger(), isNull, reason: '推理失败');
      final tags = model.tags!;
      debugPrint(
        '=== 打标结果 ===\n'
        '${[for (final t in tags.general) t.tag].join(', ')}\n'
        'rating: ${tags.rating}',
      );
      expect(tags.general, isNotEmpty);
      model.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 15)));

  testWidgets('从 ModelScope 下 Florence-2(带 SHA256 校验),写一段描述', (tester) async {
    if (!on || home == null) {
      markTestSkipped('没给 PENNA_TEST_DOWNLOAD=1 / PENNA_HOME');
      return;
    }
    await tester.runAsync(() async {
      final model = await fresh();
      final florence = captionModels.firstWhere(
        (m) => m.id == 'florence2-base-ft',
      );
      final watch = Stopwatch()..start();
      expect(await model.downloadCaption(florence), isNull, reason: '下载失败');
      debugPrint('=== Florence-2 下载用了 ${watch.elapsed.inSeconds} 秒');
      expect(model.florenceMode, isTrue);
      expect(await model.runCaption(), isNull, reason: '推理失败');
      debugPrint('=== 描述 ===\n${model.caption}');
      expect(model.caption.trim(), isNotEmpty);
      model.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
