import 'package:flutter/widgets.dart';

/// 动效令牌:时长四档、曲线三种,都是快起慢收。各处的动画只用这里的,
/// 不再各写各的毫秒数(参考 open-claude-ui 的拆解:克制靠的是一套统一的约束)。
abstract final class Motion {
  /// 按下、焦点环。
  static const fast = Duration(milliseconds: 60);

  /// 分段按钮、标签切换、小的颜色变化。
  static const snap = Duration(milliseconds: 120);

  /// 悬停、菜单、折叠展开、卡片变化。
  static const base = Duration(milliseconds: 200);

  /// 侧栏、面板、新出现的块。
  static const sheet = Duration(milliseconds: 300);

  /// 悬停、阴影、颜色:一下就到位,尾巴拖得很轻。
  static const swift = Cubic(0.16, 1, 0.3, 1);

  /// 折叠展开、尺寸变化。
  static const expand = Cubic(0.19, 1, 0.22, 1);

  /// 新块入场。
  static const enter = Cubic(0.22, 1, 0.36, 1);

  /// 退场:起步就走、越走越快,和入场一减一加。
  static const leave = Cubic(0.4, 0, 1, 1);

  /// 下拉菜单展开多久。依据:NN/g 建议界面动画 100–500 ms、小部件取 200 ms 上下;
  /// Material 3 的菜单落在 short4–medium1(200–250 ms)、入场减速出场加速。
  /// Flutter 默认的 300 ms 匀速展开偏慢偏硬(用户反馈),取 220 ms。
  static const menuDuration = Duration(milliseconds: 220);

  /// 所有下拉菜单(`PopupMenuButton.popUpAnimationStyle`、`showMenu`)都用这个:
  /// 入场减速;退场按 [leave] 走,大约前一半就淡完,所以收起比展开快。
  static AnimationStyle menu(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: menuDuration,
          curve: enter,
          reverseCurve: leave,
        );

  /// 悬停浮出的卡片(上下文明细这类):200 ms 浮出,120 ms 收起。
  static AnimationStyle popover(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: base,
          reverseDuration: snap,
          curve: enter,
          reverseCurve: leave,
        );

  /// 系统设置了「减少动画」时动画直接跳到结尾。
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
