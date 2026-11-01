part of 'settings_llm_section.dart';

const _modelRowHeight = 32.0;
const _modelListMaxHeight = 224.0;

/// 模型多于这个数才显示筛选框。
const _filterThreshold = 12;

/// 拉取到的模型列表:点一行就勾选并填进「模型名称」。
class _ModelList extends StatefulWidget {
  const _ModelList({
    required this.models,
    required this.selected,
    required this.onPick,
  });

  final List<String> models;
  final Set<String> selected;
  final ValueChanged<String> onPick;

  @override
  State<_ModelList> createState() => _ModelListState();
}

class _ModelListState extends State<_ModelList> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final needle = _filter.trim().toLowerCase();
    final shown = needle.isEmpty
        ? widget.models
        : widget.models.where((m) => m.toLowerCase().contains(needle)).toList();
    return PennaCard(
      color: PennaColors.slate50,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.models.length > _filterThreshold)
            TextField(
              contextMenuBuilder: pennaTextMenu,
              onChanged: (v) => setState(() => _filter = v),
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('筛选 {0} 个模型', [widget.models.length]),
                hintStyle: TextStyle(color: PennaColors.slate400),
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 34),
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: PennaColors.border),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: PennaColors.border),
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _modelListMaxHeight),
            child: ListView.builder(
              shrinkWrap: true,
              itemExtent: _modelRowHeight,
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final model = shown[i];
                final picked = widget.selected.contains(model);
                return InkWell(
                  onTap: () => widget.onPick(model),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          picked
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 16,
                          color: picked
                              ? PennaColors.primary
                              : PennaColors.slate400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            model,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: picked
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
