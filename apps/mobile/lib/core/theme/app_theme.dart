import 'package:flutter/material.dart';

abstract final class AppColors {
  static const indigo = Color(0xff6658d9);
  static const mint = Color(0xffd9f3e8);
  static const ink = Color(0xff242334);
}

abstract final class Motion {
  static const quick = Duration(milliseconds: 160);
  static const standard = Duration(milliseconds: 240);
  static const delight = Duration(milliseconds: 320);
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

ThemeData nextbellTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.indigo,
    brightness: brightness,
    surface: dark ? const Color(0xff171621) : const Color(0xfff8f8fc),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Manrope',
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    textTheme: Typography.material2021(platform: TargetPlatform.iOS).black
        .apply(
          fontFamily: 'Manrope',
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 34,
            height: 1.12,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            height: 1.2,
            letterSpacing: -.8,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          titleLarge: TextStyle(
            fontSize: 21,
            letterSpacing: -.5,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xff22212f) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.indigo,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontFamily: 'Manrope',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .5),
      thickness: 1,
      space: 1,
    ),
  );
}
