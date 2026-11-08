import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// 左边图标栏的功能分组:相邻两页分组不同时中间画一道线。
enum NavGroup { create, reference, keep }

/// 图标栏上的一页([id] 存进 `AppConfig.navOrder`,别改)。
typedef NavPage = ({String id, IconData icon, NavGroup group});

/// 默认顺序:按功能分组(2026-11-08 用户要求),写 → 参考 → 存。「设置」固定在最下面,不在这里。
const navPages = <NavPage>[
  (id: 'studio', icon: Icons.space_dashboard_outlined, group: NavGroup.create),
  (id: 'layout', icon: Icons.crop_free, group: NavGroup.create),
  (id: 'manga', icon: Icons.auto_stories_outlined, group: NavGroup.create),
  (
    id: 'characters',
    icon: Icons.face_retouching_natural_outlined,
    group: NavGroup.reference,
  ),
  (id: 'poses', icon: Icons.accessibility_new, group: NavGroup.reference),
  (id: 'local', icon: Icons.memory_outlined, group: NavGroup.reference),
  (id: 'archive', icon: Icons.inventory_2_outlined, group: NavGroup.keep),
  (id: 'notebook', icon: Icons.sticky_note_2_outlined, group: NavGroup.keep),
];

String navName(String id) => switch (id) {
  'studio' => tr('工作台'),
  'layout' => tr('区域控制工作台'),
  'manga' => tr('漫画分镜工作台'),
  'characters' => tr('角色库'),
  'poses' => tr('姿势图库'),
  'local' => tr('本地反推'),
  'archive' => tr('档案库'),
  'notebook' => tr('记事本'),
  _ => id,
};

/// 按用户排的顺序([order] 里认得的 id);没排到的(以后新加的页)照默认顺序接在后面。
List<NavPage> orderedNav(List<String> order) {
  final byId = {for (final p in navPages) p.id: p};
  final picked = [
    for (final id in order.toSet())
      if (byId[id] != null) byId[id]!,
  ];
  return [
    ...picked,
    for (final p in navPages)
      if (!picked.contains(p)) p,
  ];
}
