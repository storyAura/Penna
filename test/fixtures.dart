import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:penna/core/harness/local/llama_server.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/services/config_service.dart';
import 'package:penna/data/services/skill_store.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

ConfigService tempConfig() =>
    ConfigService(dir: Directory.systemTemp.createTempSync('penna_test'));

SkillStore tempSkills() =>
    SkillStore(Directory.systemTemp.createTempSync('penna_skills'));

/// 一个开头有固定区、后面三块正文、一处待确认 diff 的工作台。
StudioViewModel sampleStudio({
  ConfigService? config,
  ChatStreamer? streamChat,
}) {
  final time = DateTime(2026, 10, 8, 14, 28, 10);
  return StudioViewModel(
    config: config ?? tempConfig(),
    streamChat: streamChat ?? (_) => const Stream.empty(),
    blocks: const [
      (text: 'masterpiece, titanium armor plating,', pinned: true),
      (text: 'A cybernetic android in the rain. ', pinned: false),
      (text: 'flat generic ambient lighting, ', pinned: false),
      (text: 'Shot on 35mm.', pinned: false),
    ],
    pending: DiffProposal(
      title: 'Agent 建议',
      segmentIndex: 2,
      removed: 'flat generic ambient lighting, ',
      added: 'dramatic volumetric neon rim lighting, ',
    ),
    messages: [
      ChatMessage(fromUser: true, text: '增强背光', time: time),
      ChatMessage(
        fromUser: false,
        text: '改好了:',
        time: time,
        toolSummary: '已调用技能: local-edit',
        toolDetails: const ['锁定区校验通过'],
      ),
    ],
  );
}

/// 假的 llama-server 进程:不真的起程序,[exit] 之后算退出。
class FakeProcess implements Process {
  final _exit = Completer<int>();
  final _err = StreamController<List<int>>();
  bool killed = false;

  void exit(int code, [String stderr = '']) {
    _err.add(utf8.encode(stderr));
    _err.close();
    _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => _err.stream;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_exit.isCompleted) exit(-1);
    return true;
  }
}

/// 临时文件夹里放好假的 llama-server.exe 和模型,返回启动参数。
ServerSpec fakeServerSpec(Directory dir, {int port = 8091}) {
  for (final name in ['llama-server.exe', 'm.gguf']) {
    File('${dir.path}/$name').writeAsStringSync('x');
  }
  return (
    exe: '${dir.path}/llama-server.exe',
    model: '${dir.path}/m.gguf',
    mmproj: '',
    port: port,
    context: 4096,
    gpuLayers: -1,
  );
}
