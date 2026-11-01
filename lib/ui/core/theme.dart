import 'package:flutter/material.dart';

/// 一套配色。浅色取自 design/desktop/code.html 的 tailwind 配置(浅色原型)。
class _Palette {
  const _Palette({
    required this.bg,
    required this.sidebar,
    required this.card,
    required this.editorBg,
    required this.border,
    required this.slate50,
    required this.slate100,
    required this.slate400,
    required this.slate500,
    required this.slate700,
    required this.text,
    required this.primary,
    required this.primaryBg,
    required this.primaryBorder,
    required this.accent,
    required this.amber,
    required this.lock,
    required this.lockBorder,
    required this.lockText,
    required this.diffAdd,
    required this.diffAddText,
    required this.diffDel,
    required this.diffDelText,
  });

  final Color bg;
  final Color sidebar;
  final Color card;
  final Color editorBg;
  final Color border;
  final Color slate50;
  final Color slate100;
  final Color slate400;
  final Color slate500;
  final Color slate700;
  final Color text;
  final Color primary;
  final Color primaryBg;
  final Color primaryBorder;
  final Color accent;
  final Color amber;
  final Color lock;
  final Color lockBorder;
  final Color lockText;
  final Color diffAdd;
  final Color diffAddText;
  final Color diffDel;
  final Color diffDelText;
}

const _light = _Palette(
  bg: Color(0xFFF8F9FA),
  sidebar: Color(0xFFF1F3F5),
  card: Color(0xFFFFFFFF),
  editorBg: Color(0xFFFCFDFD),
  border: Color(0xFFE2E8F0),
  slate50: Color(0xFFF8FAFC),
  slate100: Color(0xFFF1F5F9),
  slate400: Color(0xFF94A3B8),
  slate500: Color(0xFF64748B),
  slate700: Color(0xFF334155),
  text: Color(0xFF0F172A),
  primary: Color(0xFF2563EB),
  primaryBg: Color(0xFFEFF6FF),
  primaryBorder: Color(0xFFBFDBFE),
  accent: Color(0xFF059669),
  amber: Color(0xFFF59E0B),
  lock: Color(0xFFFFFBEB),
  lockBorder: Color(0xFFFDE68A),
  lockText: Color(0xFF92400E),
  diffAdd: Color(0xFFECFDF5),
  diffAddText: Color(0xFF065F46),
  diffDel: Color(0xFFFEF2F2),
  diffDelText: Color(0xFFBE123C),
);

const _dark = _Palette(
  bg: Color(0xFF111318),
  sidebar: Color(0xFF15181E),
  card: Color(0xFF1B1F27),
  editorBg: Color(0xFF171A21),
  border: Color(0xFF2B313C),
  slate50: Color(0xFF20252E),
  slate100: Color(0xFF272D37),
  slate400: Color(0xFF6B7585),
  slate500: Color(0xFF8E98A8),
  slate700: Color(0xFFC4CBD6),
  text: Color(0xFFE6E9EF),
  primary: Color(0xFF4C8DFF),
  primaryBg: Color(0xFF18263F),
  primaryBorder: Color(0xFF2D4A7C),
  accent: Color(0xFF34D399),
  amber: Color(0xFFF5B83D),
  lock: Color(0xFF2A2314),
  lockBorder: Color(0xFF5E4A18),
  lockText: Color(0xFFF3C969),
  diffAdd: Color(0xFF0F2A21),
  diffAddText: Color(0xFF6EE7B7),
  diffDel: Color(0xFF2F161B),
  diffDelText: Color(0xFFFDA4AF),
);

/// 界面用的颜色。都是取值时才读当前配色,所以不能放进 const 里;
/// 换配色后要整棵树重建一遍(`applyLook`)。
abstract final class PennaColors {
  static _Palette _p = _light;

  /// 现在是不是深色。
  static bool get isDark => identical(_p, _dark);

  /// 换成浅色 / 深色配色;之后调用方负责让界面重建。
  static void useDark(bool dark) => _p = dark ? _dark : _light;

  static Color get bg => _p.bg;
  static Color get sidebar => _p.sidebar;
  static Color get card => _p.card;
  static Color get editorBg => _p.editorBg;
  static Color get border => _p.border;
  static Color get slate50 => _p.slate50;
  static Color get slate100 => _p.slate100;
  static Color get slate400 => _p.slate400;
  static Color get slate500 => _p.slate500;
  static Color get slate700 => _p.slate700;
  static Color get text => _p.text;
  static Color get primary => _p.primary;
  static Color get primaryBg => _p.primaryBg;
  static Color get primaryBorder => _p.primaryBorder;
  static Color get accent => _p.accent;
  static Color get amber => _p.amber;
  static Color get lock => _p.lock;
  static Color get lockBorder => _p.lockBorder;
  static Color get lockText => _p.lockText;
  static Color get diffAdd => _p.diffAdd;
  static Color get diffAddText => _p.diffAddText;
  static Color get diffDel => _p.diffDel;
  static Color get diffDelText => _p.diffDelText;
}

/// 随软件打包的默认字体(见 pubspec.yaml 的 fonts 与 font/ 目录)。
const bundledLatinFont = 'Maple Mono';
const bundledCjkFont = 'LXGW 975 Yuan SC';

/// 成稿区文字:字体跟随全局(默认的 Maple Mono 本身就是等宽)。
TextStyle get monoStyle =>
    TextStyle(fontSize: 12.5, height: 1.6, color: PennaColors.slate700);

/// [latin] / [cjk] 是用户在设置里选的字体名,留空用内置字体。
ThemeData pennaTheme({String latin = '', String cjk = ''}) {
  final family = latin.trim().isEmpty ? bundledLatinFont : latin.trim();
  final fallback = [
    // 用户填的英文字体没装时,英文仍落回内置英文字体而不是中文字体。
    bundledLatinFont,
    if (cjk.trim().isNotEmpty) cjk.trim(),
    bundledCjkFont,
    'Microsoft YaHei UI',
  ];
  // 这几处主题的文字样式是整体替换的,不带上字体就会掉回系统默认字体。
  final font = TextStyle(fontFamily: family, fontFamilyFallback: fallback);
  final dark = PennaColors.isDark;
  // 提示框、提示条在两种配色下都是深底白字。
  final toast = dark ? const Color(0xFF2E3440) : PennaColors.text;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: PennaColors.primary,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: PennaColors.primary,
        surface: PennaColors.card,
        surfaceTint: Colors.transparent,
        outline: PennaColors.border,
        outlineVariant: PennaColors.border,
      );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: family,
    fontFamilyFallback: fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: PennaColors.bg,
    dividerColor: PennaColors.border,
    popupMenuTheme: PopupMenuThemeData(
      color: PennaColors.card,
      surfaceTintColor: Colors.transparent,
      // 浮层:大而淡的投影 + 一圈细描边,浮起来但不压人。
      elevation: 8,
      shadowColor: const Color(0x1F0F172A),
      menuPadding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: PennaColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: toast,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: font.copyWith(fontSize: 11.5, color: Colors.white),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: toast,
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: font.copyWith(fontSize: 12.5, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PennaColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: const Color(0x1F0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: PennaColors.border),
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: PennaColors.primary,
      inactiveTrackColor: PennaColors.border,
      thumbColor: PennaColors.primary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : PennaColors.slate400,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => !s.contains(WidgetState.selected)
            ? PennaColors.slate100
            // 点不了的开关是灰的,不能看着和能点的一样。
            : s.contains(WidgetState.disabled)
            ? PennaColors.slate400
            : PennaColors.primary,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.transparent
            : PennaColors.border,
      ),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: PennaColors.text,
      displayColor: PennaColors.text,
    ),
  );
}
