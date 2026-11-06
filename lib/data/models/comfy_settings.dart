import 'package:flutter/foundation.dart';

/// ComfyUI 默认的本机地址。
const comfyDefaultUrl = 'http://127.0.0.1:8188';

/// ComfyUI 的 Key 在 `AppConfig.secrets` 里的键(给云端前面的反向代理用,本机的不用填)。
const comfyKeyName = 'comfy.key';

/// 「设置 → ComfyUI」:接哪台 ComfyUI、用哪个工作流、出的图放哪。
@immutable
class ComfySettings {
  const ComfySettings({
    this.url = comfyDefaultUrl,
    this.workflow = '',
    this.workflowName = '',
    this.imageDir = '',
  });

  factory ComfySettings.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return ComfySettings(
      url: m['url'] as String? ?? comfyDefaultUrl,
      workflow: m['workflow'] as String? ?? '',
      workflowName: m['workflowName'] as String? ?? '',
      imageDir: m['imageDir'] as String? ?? '',
    );
  }

  final String url;

  /// 导入的「导出 (API)」工作流全文;空的用内置的文生图。
  final String workflow;
  final String workflowName;

  /// 出的图存在哪;空的是「文档\Penna\images」。
  final String imageDir;

  Map<String, Object?> toJson() => {
    'url': url,
    'workflow': workflow,
    'workflowName': workflowName,
    'imageDir': imageDir,
  };

  ComfySettings copyWith({
    String? url,
    String? workflow,
    String? workflowName,
    String? imageDir,
  }) => ComfySettings(
    url: url ?? this.url,
    workflow: workflow ?? this.workflow,
    workflowName: workflowName ?? this.workflowName,
    imageDir: imageDir ?? this.imageDir,
  );
}
