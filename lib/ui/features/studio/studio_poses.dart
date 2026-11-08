part of 'studio_view_model.dart';

/// Agent 要姿势参考图时写的标签:`<pose-ref>分类 视角</pose-ref>`。
const poseRefTag = 'pose-ref';

/// 一次最多附几张。
const _poseRefCount = 3;

/// 发给模型的分类、视角名(不翻译)。
const _poseCategoryZh = {
  'standing': '站姿',
  'sitting': '坐姿',
  'kneel_squat': '跪姿/蹲姿',
  'lying': '卧姿',
  'inverted_acrobatic': '倒立/高难度',
  'duo_mixed_level': '双人高低组合',
  'upper_body_gesture': '半身手势',
};
const _poseAngleZh = {
  'front': '正面',
  'diag': '斜侧',
  'side': '侧面',
  'above': '俯视',
  'below': '仰视',
};

/// 姿势图库接到对话里(2026-11-08 用户要求):用户描述里的姿势对得上图库的某一类时,
/// Agent 先问要不要附参考图,用户同意了才写 [poseRefTag],程序挑几张附在工具结果里给它看。
// ponytail: 「先问」只靠系统提示,程序不拦;副聊天不接。
extension StudioPoses on StudioViewModel {
  bool get _posesReady => poses?.installed ?? false;

  /// 系统提示里的【姿势图库】;没装图库时是空串。
  String get _posePrompt {
    if (!_posesReady) return '';
    final counts = <String, int>{};
    for (final p in poses!.poses) {
      if (!isSuggestive(p)) counts[p.category] = (counts[p.category] ?? 0) + 1;
    }
    final cats = [
      for (final MapEntry(:key, :value) in counts.entries)
        '$key ${_poseCategoryZh[key] ?? key}($value)',
    ].join('、');
    final angles = [
      for (final MapEntry(:key, :value) in _poseAngleZh.entries) '$key $value',
    ].join('、');
    return '【姿势图库】本机装了无脸人偶的姿势线稿。分类:$cats;视角:$angles。'
        '用户描述的画面里有明确的姿势或机位(跪坐、躺着、俯视角……),和某一类对得上时,'
        '先用 <options> 问用户要不要附上这类姿势参考图(例如「附上几张跪姿参考」「不用」),不要直接附。'
        '用户同意后,这条回复只写 <$poseRefTag>分类 视角</$poseRefTag>(写英文名,视角可省),'
        '程序会附上最多 $_poseRefCount 张线稿给你看;拿到图后照着写体态、肢体朝向和机位,'
        '提示词里不写人偶、线稿这些字。用户没同意就不写这个标签。';
  }

  /// 回复里的 [poseRefTag]:挑几张图,拼成交还给模型的话([text])、
  /// 回复上的一行记录([note])和附上的图([images])。没写这个标签时是 null。
  ({String text, String note, List<Attachment> images})? _poseRefs(
    String prose,
  ) {
    if (!_posesReady) return null;
    final ask = splitToolTag(prose, poseRefTag).queries.firstOrNull;
    if (ask == null) return null;
    final words = ask.toLowerCase().split(RegExp(r'[\s,,、]+'));
    bool said(String id, String zh) =>
        words.contains(id) || zh.split('/').any(ask.contains);
    final category = _poseCategoryZh.entries
        .where((e) => said(e.key, e.value))
        .firstOrNull
        ?.key;
    if (category == null) {
      return (
        text: '【姿势参考】「$ask」对不上图库的分类,能用的分类见【姿势图库】。',
        note: tr('姿势参考没对上分类'),
        images: const [],
      );
    }
    final angle = _poseAngleZh.entries
        .where((e) => said(e.key, e.value))
        .firstOrNull
        ?.key;
    final picked = [
      for (final p in poses!.poses)
        if (p.category == category && !isSuggestive(p)) p,
    ]..shuffle(_poseRandom);
    final images = <Attachment>[];
    final names = <String>[];
    for (final p in picked) {
      if (images.length >= _poseRefCount) break;
      final v =
          p.views.where((v) => v.angle == angle).firstOrNull ?? p.views.first;
      try {
        images.add(
          Attachment.image(
            name: '${p.id}_${v.angle}.webp',
            mime: 'image/webp',
            bytes: File(v.path).readAsBytesSync(),
          ),
        );
        names.add('${p.id}(${_poseAngleZh[v.angle] ?? v.angle})');
      } on FileSystemException {
        continue;
      }
    }
    final what = _poseCategoryZh[category]!;
    return (
      text: images.isEmpty
          ? '【姿势参考】「$what」这一类的图读不了,照用户的描述写。'
          : '【姿势参考】用户同意后附上了 ${images.length} 张「$what」的线稿(图在这条消息里):'
                '${names.join('、')}。只参考体态、肢体朝向和机位,提示词里不写人偶、线稿。',
      note: tr('附上了姿势参考 · {0} 张', [images.length]),
      images: List.unmodifiable(images),
    );
  }
}

final _poseRandom = Random();
