import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfyui.dart';
import 'package:penna/ui/features/studio/comfy_runner.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('第一次启动把标准工作流都加进列表并换到第一个;删掉的不再加回来', () async {
    final service = tempConfig();
    final runner = ComfyRunner(service);
    await runner.addStandardFlows();
    final flows = service.config.comfy.flows;
    expect(
      [for (final f in flows) f.name],
      [for (final (name, _) in standardWorkflows) name],
    );
    expect(service.config.comfy.flowId, flows.first.id);

    service.update(
      service.config.copyWith(
        comfy: service.config.comfy.removeFlow(flows.first.id),
      ),
    );
    await runner.addStandardFlows();
    expect(service.config.comfy.flows, hasLength(standardWorkflows.length - 1));
  });
}
