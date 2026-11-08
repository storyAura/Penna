// 人偶的内置姿势:每个姿势是一组关节角度(纯数据,不依赖 Flutter)。
//
// 角度都是度,按世界方向量(不跟着躯干转):每节胳膊腿有两个角——
// f 是往前抬(0 朝下,90 朝前,180 朝上,负的往后),o 是往外张(0 贴着身体,
// 90 平举,180 朝上,负的往里收)。注意 f 过了 90(往上举)以后,o 的里外是反的:
// 要手往回收到下巴、额头,o 写正的。A 是朝向那一侧的胳膊腿,B 是另一侧。
// 躯干:lean 往前弯、tilt 往侧歪;roll 是整个人转过去(躺、摔);
// headTurn 是头比身体多转多少(回头),headTilt 是低头(正)抬头(负)。

/// 一节胳膊或腿:上一节(上臂、大腿)和下一节(前臂、小腿)各自的 f、o。
typedef MangaLimb = ({double f1, double o1, double f2, double o2});

const _armRest = (f1: 0.0, o1: 8.0, f2: 6.0, o2: 5.0);
const _legRest = (f1: 0.0, o1: 3.0, f2: 0.0, o2: 2.0);

/// 一个姿势。[name] 存中文原文(显示时翻译),[group] 是分类,
/// [words] 是动作文字里出现就用它的字。
class MangaPoseDef {
  const MangaPoseDef(
    this.name,
    this.group, {
    this.armA = _armRest,
    this.armB = _armRest,
    this.legA = _legRest,
    this.legB = _legRest,
    this.lean = 0,
    this.tilt = 0,
    this.roll = 0,
    this.headTurn = 0,
    this.headTilt = 0,
    this.words = const [],
  });

  final String name, group;
  final MangaLimb armA, armB, legA, legB;
  final double lean, tilt, roll, headTurn, headTilt;
  final List<String> words;
}

/// 姿势的分类(显示时翻译)。
const mangaPoseGroups = ['站姿', '手势', '动作', '坐姿', '跪蹲', '躺倒'];

/// 内置的姿势,第一个是默认的站姿。
const mangaPoses = <MangaPoseDef>[
  // 站姿
  MangaPoseDef('站立', '站姿'),
  MangaPoseDef(
    '稍息',
    '站姿',
    legA: (f1: 8, o1: 10, f2: 5, o2: 8),
    tilt: 4,
    words: ['站着', '伫立', '站在'],
  ),
  MangaPoseDef(
    '叉腰',
    '站姿',
    armA: (f1: 5, o1: 45, f2: 10, o2: -55),
    armB: (f1: 5, o1: 45, f2: 10, o2: -55),
    legA: (f1: 0, o1: 8, f2: 0, o2: 6),
    legB: (f1: 0, o1: 8, f2: 0, o2: 6),
    words: ['叉腰'],
  ),
  MangaPoseDef(
    '抱臂',
    '站姿',
    armA: (f1: 25, o1: 5, f2: 80, o2: -80),
    armB: (f1: 25, o1: 5, f2: 80, o2: -75),
    words: ['抱臂', '抱胸', '双手抱'],
  ),
  MangaPoseDef(
    '背手',
    '站姿',
    armA: (f1: -25, o1: 5, f2: -40, o2: -30),
    armB: (f1: -25, o1: 5, f2: -40, o2: -30),
    words: ['背着手', '背手'],
  ),
  MangaPoseDef('回头', '站姿', headTurn: 110, tilt: -3, words: ['回头', '转身', '回望']),
  MangaPoseDef('鞠躬', '站姿', lean: 50, headTilt: 20, words: ['鞠躬', '行礼', '低头致意']),
  MangaPoseDef(
    '倚靠',
    '站姿',
    tilt: -8,
    armB: (f1: 0, o1: 35, f2: 0, o2: 20),
    legA: (f1: 15, o1: 15, f2: 5, o2: 10),
    words: ['倚', '靠在'],
  ),
  // 手势
  MangaPoseDef(
    '挥手',
    '手势',
    armA: (f1: 0, o1: 125, f2: 0, o2: 160),
    words: ['挥手', '招手', '打招呼'],
  ),
  MangaPoseDef(
    '指向',
    '手势',
    armA: (f1: 85, o1: 18, f2: 88, o2: 18),
    words: ['指'],
  ),
  MangaPoseDef(
    '举双手',
    '手势',
    armA: (f1: 0, o1: 160, f2: 0, o2: 172),
    armB: (f1: 0, o1: 160, f2: 0, o2: 172),
    words: ['举起双手', '欢呼', '投降', '举手'],
  ),
  MangaPoseDef(
    '托腮',
    '手势',
    armA: (f1: 35, o1: 5, f2: 150, o2: 25),
    armB: (f1: 20, o1: 5, f2: 90, o2: -70),
    headTilt: 10,
    words: ['托腮', '思考', '沉思'],
  ),
  MangaPoseDef(
    '扶额',
    '手势',
    armA: (f1: 30, o1: 30, f2: 120, o2: 60),
    headTilt: 18,
    words: ['扶额', '捂脸', '头疼'],
  ),
  MangaPoseDef(
    '抚胸',
    '手势',
    armA: (f1: 15, o1: 5, f2: 70, o2: -78),
    words: ['抚胸', '捂胸', '按着胸口', '握拳于胸'],
  ),
  MangaPoseDef(
    '伸手',
    '手势',
    armA: (f1: 75, o1: 10, f2: 80, o2: 8),
    lean: 8,
    words: ['伸手', '递', '拉住', '抓住'],
  ),
  MangaPoseDef(
    '拥抱',
    '手势',
    armA: (f1: 70, o1: 25, f2: 85, o2: -45),
    armB: (f1: 70, o1: 25, f2: 85, o2: -45),
    lean: 6,
    words: ['拥抱', '抱住', '抱紧'],
  ),
  // 动作
  MangaPoseDef(
    '行走',
    '动作',
    armA: (f1: -22, o1: 6, f2: -10, o2: 4),
    armB: (f1: 22, o1: 6, f2: 35, o2: 4),
    legA: (f1: 22, o1: 2, f2: 5, o2: 0),
    legB: (f1: -15, o1: 2, f2: -35, o2: 0),
    words: ['走', '迈步', '踏入'],
  ),
  MangaPoseDef(
    '奔跑',
    '动作',
    armA: (f1: -45, o1: 8, f2: 20, o2: 5),
    armB: (f1: 55, o1: 8, f2: 130, o2: 5),
    legA: (f1: 65, o1: 3, f2: -5, o2: 0),
    legB: (f1: -30, o1: 3, f2: -95, o2: 0),
    lean: 18,
    words: ['跑', '冲', '奔', '追'],
  ),
  MangaPoseDef(
    '跳跃',
    '动作',
    armA: (f1: 20, o1: 140, f2: 30, o2: 165),
    armB: (f1: 20, o1: 140, f2: 30, o2: 165),
    legA: (f1: 55, o1: 6, f2: -40, o2: 0),
    legB: (f1: 20, o1: 6, f2: -80, o2: 0),
    words: ['跳', '跃'],
  ),
  MangaPoseDef(
    '出拳',
    '动作',
    armA: (f1: 90, o1: 0, f2: 90, o2: 0),
    armB: (f1: 45, o1: 15, f2: 135, o2: 20),
    legA: (f1: 25, o1: 12, f2: 0, o2: 8),
    legB: (f1: -25, o1: 12, f2: -10, o2: 8),
    lean: 10,
    words: ['拳', '打', '揍', '攻击'],
  ),
  MangaPoseDef(
    '踢腿',
    '动作',
    armA: (f1: 10, o1: 50, f2: 20, o2: 40),
    armB: (f1: 10, o1: 50, f2: 20, o2: 40),
    legA: (f1: 85, o1: 5, f2: 80, o2: 5),
    lean: -12,
    words: ['踢'],
  ),
  MangaPoseDef(
    '挥砍',
    '动作',
    armA: (f1: 40, o1: 120, f2: 60, o2: 140),
    armB: (f1: 40, o1: 110, f2: 60, o2: 130),
    legA: (f1: 30, o1: 10, f2: 0, o2: 8),
    legB: (f1: -25, o1: 10, f2: -15, o2: 8),
    lean: -5,
    words: ['砍', '挥剑', '劈'],
  ),
  MangaPoseDef(
    '投掷',
    '动作',
    armA: (f1: -30, o1: 100, f2: 20, o2: 150),
    armB: (f1: 70, o1: 20, f2: 75, o2: 15),
    legA: (f1: -20, o1: 10, f2: -10, o2: 5),
    legB: (f1: 25, o1: 10, f2: 0, o2: 5),
    tilt: -6,
    words: ['扔', '投', '丢'],
  ),
  MangaPoseDef(
    '防御',
    '动作',
    armA: (f1: 60, o1: 10, f2: 150, o2: 30),
    armB: (f1: 60, o1: 10, f2: 150, o2: 30),
    legA: (f1: 20, o1: 15, f2: -15, o2: 10),
    legB: (f1: 20, o1: 15, f2: -15, o2: 10),
    lean: 12,
    headTilt: 15,
    words: ['挡', '护住', '防御', '抱头'],
  ),
  // 坐姿
  MangaPoseDef(
    '坐椅子',
    '坐姿',
    armA: (f1: 25, o1: 8, f2: 70, o2: 4),
    armB: (f1: 25, o1: 8, f2: 70, o2: 4),
    legA: (f1: 88, o1: 8, f2: 0, o2: 5),
    legB: (f1: 88, o1: 8, f2: 0, o2: 5),
    words: ['坐在椅', '坐在长椅', '坐下', '坐'],
  ),
  MangaPoseDef(
    '盘腿',
    '坐姿',
    armA: (f1: 20, o1: 15, f2: 55, o2: 10),
    armB: (f1: 20, o1: 15, f2: 55, o2: 10),
    legA: (f1: 85, o1: 50, f2: 80, o2: -70),
    legB: (f1: 85, o1: 50, f2: 80, o2: -70),
    words: ['盘腿', '席地而坐'],
  ),
  MangaPoseDef(
    '抱膝',
    '坐姿',
    armA: (f1: 55, o1: 10, f2: 70, o2: -25),
    armB: (f1: 55, o1: 10, f2: 70, o2: -25),
    legA: (f1: 130, o1: 8, f2: -15, o2: 4),
    legB: (f1: 130, o1: 8, f2: -15, o2: 4),
    lean: 18,
    headTilt: 15,
    words: ['抱膝', '缩成一团'],
  ),
  MangaPoseDef(
    '后仰坐',
    '坐姿',
    armA: (f1: -35, o1: 20, f2: -30, o2: 15),
    armB: (f1: -35, o1: 20, f2: -30, o2: 15),
    legA: (f1: 85, o1: 6, f2: 75, o2: 4),
    legB: (f1: 95, o1: 6, f2: 40, o2: 4),
    lean: -22,
    words: ['后仰', '撑着坐'],
  ),
  // 跪蹲
  MangaPoseDef(
    '跪坐',
    '跪蹲',
    armA: (f1: 25, o1: 5, f2: 60, o2: -10),
    armB: (f1: 25, o1: 5, f2: 60, o2: -10),
    legA: (f1: 15, o1: 6, f2: -100, o2: 0),
    legB: (f1: 15, o1: 6, f2: -100, o2: 0),
    words: ['跪坐', '跪'],
  ),
  MangaPoseDef(
    '单膝跪',
    '跪蹲',
    armA: (f1: 40, o1: 10, f2: 70, o2: 5),
    legA: (f1: 90, o1: 8, f2: 0, o2: 4),
    legB: (f1: 0, o1: 6, f2: -90, o2: 0),
    words: ['单膝', '跪下'],
  ),
  MangaPoseDef(
    '蹲下',
    '跪蹲',
    armA: (f1: 45, o1: 15, f2: 60, o2: 8),
    armB: (f1: 45, o1: 15, f2: 60, o2: 8),
    legA: (f1: 115, o1: 22, f2: -35, o2: 10),
    legB: (f1: 115, o1: 22, f2: -35, o2: 10),
    lean: 25,
    words: ['蹲'],
  ),
  // 躺倒
  MangaPoseDef(
    '躺下',
    '躺倒',
    armA: (f1: 0, o1: 20, f2: 0, o2: 15),
    armB: (f1: 0, o1: 20, f2: 0, o2: 15),
    roll: 90,
    words: ['躺', '睡'],
  ),
  MangaPoseDef(
    '摔倒',
    '躺倒',
    armA: (f1: 20, o1: 120, f2: 30, o2: 150),
    armB: (f1: 10, o1: 80, f2: 20, o2: 100),
    legA: (f1: 60, o1: 15, f2: 20, o2: 10),
    roll: 55,
    words: ['摔', '倒下', '跌倒', '被击飞'],
  ),
];

/// 按名字找姿势;找不到是 null。
MangaPoseDef? poseNamed(String name) =>
    mangaPoses.where((p) => p.name == name).firstOrNull;

/// 从动作文字里认姿势:长的词先比(「坐在长椅」先于「坐」);都没有是站立。
MangaPoseDef poseFromAction(String action) {
  MangaPoseDef? best;
  var length = 0;
  for (final p in mangaPoses) {
    for (final w in p.words) {
      if (w.length > length && action.contains(w)) {
        best = p;
        length = w.length;
      }
    }
  }
  return best ?? mangaPoses.first;
}
