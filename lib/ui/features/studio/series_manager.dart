import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/settings_sections.dart';
import 'studio_view_model.dart';

/// 批量管理系列:勾几个,一起归档(给了 [onArchive] 时)或删掉。
Future<void> showSeriesManager(
  BuildContext context,
  StudioViewModel vm, {
  void Function(Set<int> series)? onArchive,
}) => showDialog<void>(
  context: context,
  builder: (context) => _SeriesManager(vm: vm, onArchive: onArchive),
);

class _SeriesManager extends StatefulWidget {
  const _SeriesManager({required this.vm, this.onArchive});

  final StudioViewModel vm;
  final void Function(Set<int> series)? onArchive;

  @override
  State<_SeriesManager> createState() => _SeriesManagerState();
}

class _SeriesManagerState extends State<_SeriesManager> {
  final _picked = <int>{};

  StudioViewModel get vm => widget.vm;

  int _pagesOf(int s) => vm.pages.where((p) => p.series == s).length;

  Future<void> _delete() async {
    final names = [for (final s in _picked) vm.seriesName(s)];
    if (!await confirmDelete(
      context,
      tr('删除 {0} 个系列?', [names.length]),
      tr('{0}\n每一页都会删掉,对话收进历史。', [names.join(tr('、'))]),
    )) {
      return;
    }
    if (!mounted) return;
    final problem = vm.removeSeriesMany(_picked);
    Navigator.pop(context);
    if (problem != null) showToast(context, problem, warn: true);
  }

  void _archive() {
    final picked = {..._picked};
    Navigator.pop(context);
    widget.onArchive!(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ids = vm.seriesIds;
    final all = ids.isNotEmpty && _picked.length == ids.length;
    return AlertDialog(
      title: Text(tr('批量管理系列'), style: const TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: all,
              title: Text(
                tr('全选 · 已选 {0} 个', [_picked.length]),
                style: TextStyle(fontSize: 12, color: PennaColors.slate500),
              ),
              onChanged: (on) => setState(() {
                _picked.clear();
                if (on ?? false) _picked.addAll(ids);
              }),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final s in ids)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _picked.contains(s),
                      title: Text(
                        vm.seriesName(s),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        tr('{0} 页', [_pagesOf(s)]),
                        style: const TextStyle(fontSize: 11),
                      ),
                      onChanged: (on) => setState(
                        () =>
                            (on ?? false) ? _picked.add(s) : _picked.remove(s),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        if (widget.onArchive != null)
          TextButton(
            onPressed: _picked.isEmpty ? null : _archive,
            child: Text(tr('归档')),
          ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: PennaColors.diffDelText),
          onPressed: _picked.isEmpty ? null : _delete,
          child: Text(tr('删除')),
        ),
      ],
    );
  }
}
