part of 'characters_page.dart';

/// 一个系列占的那一格:名字,和它名下有几个角色。
class _SeriesTile extends StatelessWidget {
  const _SeriesTile({
    required this.name,
    required this.count,
    required this.onTap,
    required this.favorite,
    required this.onFavorite,
  });

  final String name;
  final int count;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Bouncy(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: PennaCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: SizedBox(
              height: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _star(favorite, onFavorite),
                      ],
                    ),
                  ),
                  Text(
                    tr('{0} 个角色', [count]),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: PennaColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.note);

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 8),
      Text(note, style: TextStyle(fontSize: 11, color: PennaColors.slate500)),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: PennaColors.slate400),
      ),
    ),
  );
}

/// 角色的图;没有、或读不了时是一个占位的小人。
class _Portrait extends StatelessWidget {
  const _Portrait({required this.path, this.size = 76});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final blank = ColoredBox(
      color: PennaColors.slate100,
      child: Icon(Icons.person_outline, color: PennaColors.slate400),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: path.isEmpty
            ? blank
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                // 只按缩略图的大小解码,大图不占内存。
                cacheWidth: (size * 2).round(),
                errorBuilder: (_, _, _) => blank,
              ),
      ),
    );
  }
}

/// 「我的」里一个角色上的几个操作。
typedef _MineActions = ({
  VoidCallback onEdit,
  VoidCallback onDelete,
  VoidCallback onUpload,
});

/// 收藏的星标:收藏着是实心的。
Widget _star(bool on, VoidCallback onPressed) => SizedBox.square(
  dimension: 22,
  child: IconButton(
    tooltip: on ? tr('取消收藏') : tr('收藏'),
    iconSize: 16,
    padding: EdgeInsets.zero,
    color: on ? PennaColors.amber : PennaColors.slate400,
    icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded),
    onPressed: onPressed,
  ),
);

/// 一个只有图标的小按钮。
Widget _iconButton(IconData icon, String tip, VoidCallback onPressed) =>
    IconButton(
      tooltip: tip,
      iconSize: 15,
      visualDensity: VisualDensity.compact,
      color: PennaColors.slate500,
      icon: Icon(icon),
      onPressed: onPressed,
    );

/// 大缩略图里的一个角色:上面是图,下面是名字和几个小按钮。
class _MineTile extends StatelessWidget {
  const _MineTile({required this.card, required this.actions});

  final CharacterCard card;
  final _MineActions actions;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => PreviewImage(
              path: card.image,
              width: box.maxWidth,
              height: box.maxWidth * 4 / 3,
              blank: ColoredBox(
                color: PennaColors.slate100,
                child: Icon(
                  Icons.person_outline,
                  size: 40,
                  color: PennaColors.slate400,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _iconButton(
                Icons.add_photo_alternate_outlined,
                tr('上传图片'),
                actions.onUpload,
              ),
              _iconButton(
                Icons.content_copy,
                tr('复制'),
                () => copyWithToast(context, card.prompt, tr('已复制')),
              ),
              _iconButton(Icons.edit_outlined, tr('修改'), actions.onEdit),
              _iconButton(Icons.delete_outline, tr('删除'), actions.onDelete),
            ],
          ),
        ],
      ),
    );
  }
}

class _MineCard extends StatelessWidget {
  const _MineCard({required this.card, required this.actions});

  final CharacterCard card;
  final _MineActions actions;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Portrait(path: card.image),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: card.name,
                          children: [
                            if (card.alias.isNotEmpty)
                              TextSpan(
                                text: '  ${card.alias}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w400,
                                  color: PennaColors.slate400,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _iconButton(
                      Icons.add_photo_alternate_outlined,
                      tr('上传图片'),
                      actions.onUpload,
                    ),
                    PennaButton(
                      label: tr('复制'),
                      icon: Icons.content_copy,
                      onPressed: () =>
                          copyWithToast(context, card.prompt, tr('已复制')),
                    ),
                    PennaButton(
                      label: tr('修改'),
                      icon: Icons.edit_outlined,
                      onPressed: actions.onEdit,
                    ),
                    IconButton(
                      tooltip: tr('删除'),
                      iconSize: 15,
                      visualDensity: VisualDensity.compact,
                      color: PennaColors.slate400,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: actions.onDelete,
                    ),
                  ],
                ),
                if (card.intro.isNotEmpty)
                  Text(
                    card.intro,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: PennaColors.slate500),
                  ),
                const SizedBox(height: 4),
                Text(
                  card.prompt,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontSize: 11.5),
                ),
                if (card.outfits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr('服装:{0}', [
                        card.outfits
                            .map((o) => o.name.isEmpty ? tr('未命名') : o.name)
                            .join(tr('、')),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: PennaColors.slate500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuiltinCard extends StatelessWidget {
  const _BuiltinCard({
    required this.hit,
    required this.onSave,
    required this.favorite,
    required this.onFavorite,
  });

  final CharacterHit hit;
  final bool favorite;
  final VoidCallback onFavorite;

  /// 存一份到「我的」,之后可以自己改。
  final VoidCallback onSave;

  Widget _line(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PennaColors.slate500,
            ),
          ),
          TextSpan(text: text, style: monoStyle.copyWith(fontSize: 11.5)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final trigger = characterTrigger(hit);
    return PennaCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  trigger,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _star(favorite, onFavorite),
              const SizedBox(width: 4),
              PennaButton(
                label: tr('复制'),
                icon: Icons.content_copy,
                tooltip: tr('触发词、外貌和服装'),
                onPressed: () =>
                    copyWithToast(context, _fullPrompt(hit), tr('已复制')),
              ),
              if (hit.looks.isNotEmpty && hit.outfit.isNotEmpty)
                PennaButton(
                  label: tr('只要外貌'),
                  icon: Icons.face_outlined,
                  tooltip: tr('不带服装的词'),
                  onPressed: () => copyWithToast(
                    context,
                    '$trigger, ${hit.looks}',
                    tr('已复制(不带服装)'),
                  ),
                ),
              PennaButton(
                label: tr('存到我的'),
                icon: Icons.bookmark_add_outlined,
                onPressed: onSave,
              ),
            ],
          ),
          if (hit.alias.isNotEmpty)
            Text(
              hit.alias,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: PennaColors.slate500),
            ),
          if (hit.looks.isNotEmpty) _line(tr('外貌'), hit.looks),
          if (hit.outfit.isNotEmpty) _line(tr('服装'), hit.outfit),
        ],
      ),
    );
  }
}
