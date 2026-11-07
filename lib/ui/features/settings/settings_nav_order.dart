import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import '../../core/nav_pages.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'settings_sections.dart';

/// 「软件设置」里排左边图标栏的顺序:拖着换,改完立即生效;可以恢复默认。
class NavOrderCard extends StatelessWidget {
  const NavOrderCard({super.key, required this.service});

  final ConfigService service;

  void _move(List<NavPage> pages, int from, int to) {
    final ids = [for (final p in pages) p.id];
    ids.insert(to, ids.removeAt(from));
    service.update(service.config.copyWith(navOrder: ids));
  }

  @override
  Widget build(BuildContext context) {
    final pages = orderedNav(service.config.navOrder);
    final custom = service.config.navOrder.isNotEmpty;
    return PennaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('侧栏顺序'), style: titleStyle)),
              if (custom)
                PennaButton(
                  label: tr('恢复默认'),
                  icon: Icons.restart_alt,
                  borderColor: PennaColors.border,
                  onPressed: () => service.update(
                    service.config.copyWith(navOrder: const []),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => _move(pages, from, to),
            children: [
              for (final (i, p) in pages.indexed)
                ReorderableDragStartListener(
                  key: ValueKey(p.id),
                  index: i,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Container(
                      height: 34,
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: PennaColors.slate50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: PennaColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(p.icon, size: 16, color: PennaColors.slate500),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              navName(p.id),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          Icon(
                            Icons.drag_indicator,
                            size: 16,
                            color: PennaColors.slate400,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
