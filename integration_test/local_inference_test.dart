// 端到端跑一遍本地看图反推:真 llama-server + 真 GGUF 模型 + 真图片。
// 这条只有真的起得来服务、真的能推理才会过,`test/` 里跑不到。
//
// 跑法(模型按应用下载后的位置放好,或者用 PENNA_TEST_MODEL_DIR 指一个现成的文件夹):
//
//   PENNA_HOME=/tmp/penna_it \
//   PENNA_TEST_LLAMA_SERVER=/path/to/llama-server \
//   PENNA_TEST_MODEL_DIR=/path/to/dir-with-gguf \
//   flutter test integration_test/local_inference_test.dart -d linux
//
// 两个环境变量缺一个就跳过,所以放在仓库里不会影响别人。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/main.dart' as app;
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/local/local_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final home = Directory(Platform.environment['PENNA_HOME']!);
  final server = Platform.environment['PENNA_TEST_LLAMA_SERVER'];
  final models = Platform.environment['PENNA_TEST_MODEL_DIR'];
  const id = 'toriigate-0.5';

  setUpAll(() {
    if (models == null) return;
    // 摆到应用下载会放的位置(「文档\Penna\models\gguf\<模型 id>」),省得再下一遍。
    final dir = Directory(
      [home.path, 'models', 'gguf', id].join(Platform.pathSeparator),
    );
    dir.parent.createSync(recursive: true);
    if (!dir.existsSync()) Link(dir.path).createSync(models);
    // 界面上的「选择 llama-server」落盘就是这个样子。
    home.createSync(recursive: true);
    File([home.path, 'local.json'].join(Platform.pathSeparator))
        .writeAsStringSync(jsonEncode({'exePath': server}));
  });

  testWidgets('放一张图,本地模型给出一段描述', (tester) async {
    if (server == null || models == null) {
      markTestSkipped('没给 PENNA_TEST_LLAMA_SERVER / PENNA_TEST_MODEL_DIR');
      return;
    }
    await app.main();
    await tester.pumpAndSettle();

    // 用界面用的那个 LocalModel,和手动点「NL 反推」是同一条路。
    final model = tester.widget<LocalPage>(find.byType(LocalPage)).model;
    final torii = captionModels.firstWhere((m) => m.id == id);
    expect(model.useCaption(torii), isTrue, reason: '模型文件没就位');
    expect(model.modelPath, endsWith('ToriiGate-0.5-Q4_K_M.gguf'));
    expect(model.mmprojPath, endsWith('ToriiGate-0.5-fp16.mmproj.gguf'));

    final bytes = (await rootBundle.load('assets/avatar.png')).buffer
        .asUint8List();
    model.setImage(
      Attachment.image(name: 'avatar.png', mime: 'image/png', bytes: bytes),
    );

    addTearDown(model.stopServer);
    expect(await model.startServer(), isNull, reason: 'llama-server 没起来');
    expect(model.serverRunning, isTrue);
    expect(await model.runCaption(), isNull, reason: '反推失败');
    debugPrint('=== 反推结果 ===\n${model.caption}');
    expect(model.caption.trim(), isNotEmpty, reason: '模型没返回内容');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
