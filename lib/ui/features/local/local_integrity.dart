part of 'local_page.dart';

/// 「检查完整性」:核对眼前用的模型文件(2026-11-13 用户要求:反推出乱码时查查文件坏没坏),
/// 一行一个结果。换了模型旧结果就不显示。
class _IntegrityCheck extends StatefulWidget {
  const _IntegrityCheck({required this.files});

  final List<CheckFile> files;

  @override
  State<_IntegrityCheck> createState() => _IntegrityCheckState();
}

class _IntegrityCheckState extends State<_IntegrityCheck> {
  bool _busy = false;
  List<CheckFile> _checked = const [];
  List<FileCheck> _result = const [];

  Future<void> _run() async {
    final files = widget.files;
    setState(() => _busy = true);
    final result = await checkFiles(files);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checked = files;
      _result = result;
    });
  }

  static String _say(FileHealth h) => switch (h) {
    FileHealth.ok => tr('完好'),
    FileHealth.sizeOk => tr('大小对得上'),
    FileHealth.missing => tr('找不到文件'),
    FileHealth.wrongSize => tr('大小不对,文件不完整'),
    FileHealth.badHash => tr('校验没通过,文件已损坏'),
    FileHealth.unreadable => tr('读不出来,文件已损坏'),
    FileHealth.unchecked => tr('没有校验值'),
  };

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) return const SizedBox.shrink();
    final shown = listEquals(files, _checked) ? _result : const <FileCheck>[];
    final bad = shown.any(
      (c) => !const {
        FileHealth.ok,
        FileHealth.sizeOk,
        FileHealth.unchecked,
      }.contains(c.health),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PennaButton(
            label: _busy ? tr('检查中…') : tr('检查完整性'),
            icon: Icons.verified_outlined,
            borderColor: PennaColors.border,
            onPressed: _busy ? null : _run,
          ),
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${fileName(c.path)} · ${_say(c.health)}',
                style: TextStyle(
                  fontSize: 12,
                  color: switch (c.health) {
                    FileHealth.ok ||
                    FileHealth.sizeOk => PennaColors.diffAddText,
                    FileHealth.unchecked => PennaColors.slate500,
                    _ => PennaColors.diffDelText,
                  },
                ),
              ),
            ),
          if (bad)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('删掉后重新下载'),
                style: TextStyle(fontSize: 12, color: PennaColors.slate500),
              ),
            ),
        ],
      ),
    );
  }
}
