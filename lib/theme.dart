import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EchoMark design system, translated from the website's oklch palette:
/// deep dark teal-slate, signal-cyan primary, emerald "verified" accent.
class EmColors {
  static const background = Color(0xFF0B151B);
  static const surface = Color(0xFF111F27);
  static const card = Color(0xFF15242E);
  static const foreground = Color(0xFFF1F6F8);
  static const mutedForeground = Color(0xFF8FA4AE);
  static const primary = Color(0xFF57D9EC);
  static const primaryForeground = Color(0xFF07222B);
  static const accent = Color(0xFF37D69C);
  static const accentForeground = Color(0xFF03301F);
  static const destructive = Color(0xFFE5533D);
  static const border = Color(0x14FFFFFF);
  static const input = Color(0x1FFFFFFF);
}

ThemeData buildEchoMarkTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: EmColors.background,
    colorScheme: const ColorScheme.dark(
      surface: EmColors.background,
      surfaceContainer: EmColors.card,
      surfaceContainerHighest: EmColors.surface,
      primary: EmColors.primary,
      onPrimary: EmColors.primaryForeground,
      secondary: EmColors.accent,
      onSecondary: EmColors.accentForeground,
      tertiary: EmColors.accent,
      error: EmColors.destructive,
      onError: EmColors.foreground,
      onSurface: EmColors.foreground,
      onSurfaceVariant: EmColors.mutedForeground,
      outline: EmColors.border,
      outlineVariant: EmColors.border,
    ),
  );

  final body = GoogleFonts.dmSansTextTheme(base.textTheme);
  final display = GoogleFonts.spaceGrotesk(
    color: EmColors.foreground,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
  );

  return base.copyWith(
    textTheme: body.copyWith(
      displayLarge: display.copyWith(fontSize: 44, height: 1.05),
      displayMedium: display.copyWith(fontSize: 34, height: 1.1),
      headlineMedium: display.copyWith(fontSize: 26, height: 1.15),
      titleLarge: display.copyWith(fontSize: 20),
      titleMedium: display.copyWith(fontSize: 17),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: EmColors.background.withValues(alpha: 0.85),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: EmColors.border)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: EmColors.surface,
      indicatorColor: EmColors.primary.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? EmColors.primary
              : EmColors.mutedForeground,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? EmColors.primary
              : EmColors.mutedForeground,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EmColors.background.withValues(alpha: 0.6),
      hintStyle: const TextStyle(color: EmColors.mutedForeground),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: EmColors.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: EmColors.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            BorderSide(color: EmColors.primary.withValues(alpha: 0.6)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EmColors.primary,
        foregroundColor: EmColors.primaryForeground,
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: EmColors.foreground,
        side: const BorderSide(color: EmColors.border),
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: EmColors.background.withValues(alpha: 0.5),
        foregroundColor: EmColors.mutedForeground,
        selectedForegroundColor: EmColors.primaryForeground,
        selectedBackgroundColor: EmColors.primary,
        side: const BorderSide(color: EmColors.border),
        textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: EmColors.card,
      contentTextStyle: GoogleFonts.dmSans(color: EmColors.foreground),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EmColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: EmColors.border, space: 1),
  );
}

/// Monospace style used for the site's `em-mono-label` utility.
TextStyle emMonoLabel({Color color = EmColors.primary, double size = 11}) =>
    GoogleFonts.jetBrainsMono(
      fontSize: size,
      letterSpacing: 2.2,
      fontWeight: FontWeight.w500,
      color: color,
    );

TextStyle emMono({Color color = EmColors.foreground, double size = 12}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color);
