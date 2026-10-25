part of 'characters_page.dart';

/// 添加或修改一个角色:名字、别名、简介、提示词、几套服装,图可以拖进来或点一下选。
class _CharacterDialog extends StatefulWidget {
  const _CharacterDialog({
    required this.name,
    required this.prompt,
    required this.image,
    required this.editing,
    this.alias = '',
    this.intro = '',
    this.outfits = const [],
  });

  final String name;
  final String alias;
  final String intro;
  final String prompt;
  final List<CharacterOutfit> outfits;

  /// 现在的图(文件路径),没有就是空串。
  final String image;
  final bool editing;

  @override
  State<_CharacterDialog> createState() => _CharacterDialogState();
}

class _CharacterDialogState extends State<_CharacterDialog> {
  late var _name = widget.name;
  late var _alias = widget.alias;
  late var _intro = widget.intro;
  late var _prompt = widget.prompt;

  /// 几套服装;[key] 让删掉中间一套时下面的输入框不串位。
  late var _outfits = [
    for (final (i, o) in widget.outfits.indexed)
      (key: i, name: o.name, prompt: o.prompt),
  ];
  late var _nextKey = widget.outfits.length;

  void _addOutfit() => setState(() {
    _outfits = [..._outfits, (key: _nextKey++, name: '', prompt: '')];
  });

  void _editOutfit(int key, {String? name, String? prompt}) => setState(() {
    _outfits = [
      for (final o in _outfits)
        o.key == key
            ? (key: key, name: name ?? o.name, prompt: prompt ?? o.prompt)
            : o,
    ];
  });

  void _removeOutfit(int key) => setState(() {
    _outfits = _outfits.where((o) => o.key != key).toList();
  });

  /// 一套服装:和上面的名字、提示词同样的输入框,名字那行右边是删除。
  Widget _outfit(({int key, String name, String prompt}) o) => Column(
    key: ValueKey(o.key),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: PennaField(
              label: tr('服装名'),
              hint: tr('校服、泳装…'),
              value: o.name,
              onChanged: (v) => _editOutfit(o.key, name: v),
            ),
          ),
          IconButton(
            tooltip: tr('删除'),
            iconSize: 16,
            color: PennaColors.slate400,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _removeOutfit(o.key),
          ),
        ],
      ),
      const SizedBox(height: 8),
      PennaField(
        label: tr('服装提示词'),
        maxLines: 5,
        value: o.prompt,
        onChanged: (v) => _editOutfit(o.key, prompt: v),
      ),
    ],
  );

  /// 新选的图;没选就是 null,保存时留着原来的。
  CharacterImage? _image;
  late var _preview = widget.image;

  /// 正拖着文件悬在窗口上。
  var _over = false;

  void _useImage(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    if (!imageMimes.containsKey(ext)) {
      return showToast(context, tr('只能放图片(png、jpg、webp、gif)'), warn: true);
    }
    try {
      final file = File(path);
      if (file.lengthSync() > maxCharacterImageBytes) {
        return showToast(context, tr('图片太大(上限 20 MB)'), warn: true);
      }
      final bytes = file.readAsBytesSync();
      setState(() {
        _image = (bytes: bytes, ext: ext);
        _preview = path;
      });
    } on FileSystemException {
      showToast(context, tr('读不了这张图'), warn: true);
    }
  }

  Future<void> _pick() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: tr('图片'), extensions: imageMimes.keys.toList()),
      ],
    );
    if (picked != null && mounted) _useImage(picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.trim().isNotEmpty && _prompt.trim().isNotEmpty;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        if (d.files.isNotEmpty) _useImage(d.files.first.path);
      },
      child: AlertDialog(
        title: Text(
          widget.editing ? tr('修改角色') : tr('添加角色'),
          style: const TextStyle(fontSize: 16),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _pick,
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: Motion.snap,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _over
                          ? PennaColors.primaryBg
                          : PennaColors.slate50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _over ? PennaColors.primary : PennaColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        _Portrait(path: _preview, size: 64),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('拖入图片,或点击选择'),
                            style: TextStyle(
                              fontSize: 12,
                              color: PennaColors.slate500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                PennaField(
                  label: tr('名字'),
                  value: _name,
                  onChanged: (v) => setState(() => _name = v),
                ),
                const SizedBox(height: 8),
                PennaField(
                  label: tr('别名'),
                  hint: tr('多个用逗号隔开'),
                  value: _alias,
                  onChanged: (v) => _alias = v,
                ),
                const SizedBox(height: 8),
                PennaField(
                  label: tr('简介'),
                  hint: tr('身份、性格'),
                  maxLines: 2,
                  value: _intro,
                  onChanged: (v) => _intro = v,
                ),
                const SizedBox(height: 8),
                PennaField(
                  label: tr('提示词'),
                  hint: tr('这个角色的长相和标志性的穿着'),
                  maxLines: 5,
                  value: _prompt,
                  onChanged: (v) => setState(() => _prompt = v),
                ),
                for (final o in _outfits) _outfit(o),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addOutfit,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(tr('新增服装')),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          TextButton(
            onPressed: ready
                ? () => Navigator.pop<_Draft>(context, (
                    name: _name,
                    alias: _alias,
                    intro: _intro,
                    prompt: _prompt,
                    outfits: [
                      for (final o in _outfits)
                        (name: o.name, prompt: o.prompt),
                    ],
                    image: _image,
                  ))
                : null,
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
  }
}
