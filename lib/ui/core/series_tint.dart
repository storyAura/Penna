import 'package:flutter/material.dart';

import 'theme.dart';

// 系列的颜色:工作台的页签条和档案库共用。颜色跟着系列的名字走,所以一个系列
// 归档进档案库、再放回工作台,颜色都不变。

typedef SeriesTint = ({Color bg, Color border, Color text});

/// 能选的几种颜色,浅色、深色配色各一套。
List<SeriesTint> get seriesTints =>
    PennaColors.isDark ? _darkSeriesTints : _lightSeriesTints;

const _lightSeriesTints = <SeriesTint>[
  (bg: Color(0xFFEEF2FF), border: Color(0xFFC7D2FE), text: Color(0xFF4338CA)),
  (bg: Color(0xFFF0FDFA), border: Color(0xFF99F6E4), text: Color(0xFF0F766E)),
  (bg: Color(0xFFFFF1F2), border: Color(0xFFFECDD3), text: Color(0xFFBE123C)),
  (bg: Color(0xFFF0F9FF), border: Color(0xFFBAE6FD), text: Color(0xFF0369A1)),
  (bg: Color(0xFFFAF5FF), border: Color(0xFFE9D5FF), text: Color(0xFF7E22CE)),
  (bg: Color(0xFFFFFBEB), border: Color(0xFFFDE68A), text: Color(0xFFB45309)),
  (bg: Color(0xFFF0FDF4), border: Color(0xFFBBF7D0), text: Color(0xFF15803D)),
  (bg: Color(0xFFF8FAFC), border: Color(0xFFCBD5E1), text: Color(0xFF475569)),
];

const _darkSeriesTints = <SeriesTint>[
  (bg: Color(0xFF1B1D3A), border: Color(0xFF363A78), text: Color(0xFFA5B4FC)),
  (bg: Color(0xFF0F2826), border: Color(0xFF1F5A54), text: Color(0xFF5EEAD4)),
  (bg: Color(0xFF2C171C), border: Color(0xFF64303A), text: Color(0xFFFDA4AF)),
  (bg: Color(0xFF10233A), border: Color(0xFF1F4A70), text: Color(0xFF7DD3FC)),
  (bg: Color(0xFF261835), border: Color(0xFF4F3370), text: Color(0xFFD8B4FE)),
  (bg: Color(0xFF2A2110), border: Color(0xFF6B5320), text: Color(0xFFFCD34D)),
  (bg: Color(0xFF11281A), border: Color(0xFF25603A), text: Color(0xFF86EFAC)),
  (bg: Color(0xFF1C222B), border: Color(0xFF3B4656), text: Color(0xFFCBD5E1)),
];

/// 一共几种颜色(和配色无关)。
const seriesTintCount = 8;

/// [name] 这个系列用第几种颜色:用户在 [chosen] 里挑过就用挑的,没挑过按名字算一个
/// 固定的(同一个名字每次都是同一种)。
int seriesTintIndex(String name, Map<String, int> chosen) {
  final picked = chosen[name];
  if (picked != null && picked >= 0 && picked < seriesTintCount) return picked;
  var sum = 0;
  for (final unit in name.codeUnits) {
    sum = (sum * 31 + unit) & 0x7fffffff;
  }
  return sum % seriesTintCount;
}

SeriesTint seriesTintOf(String name, Map<String, int> chosen) =>
    seriesTints[seriesTintIndex(name, chosen)];
