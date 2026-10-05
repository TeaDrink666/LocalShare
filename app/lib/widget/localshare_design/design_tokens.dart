import 'package:flutter/material.dart';

/// Shared geometry used by the LocalShare visual language.
///
/// Keeping these values in one place makes desktop and mobile layouts feel
/// related, even when their density and navigation patterns differ.
abstract final class LocalShareRadii {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 18;
  static const double extraLarge = 24;
  static const double hero = 28;
  static const double full = 999;
}

abstract final class LocalShareSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class LocalShareDurations {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration emphasized = Duration(milliseconds: 360);
}

/// Brand colors which stay recognizable across dynamic-color and Yaru modes.
abstract final class LocalSharePalette {
  static const Color teal = Color(0xFF0F766E);
  static const Color tealLight = Color(0xFF5EEAD4);
  static const Color indigo = Color(0xFF5965A8);
  static const Color indigoLight = Color(0xFFBDC5FF);

  static const Color lightSurface = Color(0xFFF7F9FC);
  static const Color lightSurfaceRaised = Color(0xFFFFFFFF);
  static const Color darkSurface = Color(0xFF0F151C);
  static const Color darkSurfaceRaised = Color(0xFF171E27);

  static const Color lightSuccess = Color(0xFF16805D);
  static const Color darkSuccess = Color(0xFF66D6A7);
  static const Color lightWarning = Color(0xFFB45F06);
  static const Color darkWarning = Color(0xFFFFBD69);
  static const Color lightInfo = Color(0xFF4263A8);
  static const Color darkInfo = Color(0xFFAFC6FF);

  static ColorScheme scheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: isDark ? tealLight : teal,
      brightness: brightness,
    );

    if (isDark) {
      return base.copyWith(
        primary: const Color(0xFF73D9CC),
        onPrimary: const Color(0xFF003731),
        primaryContainer: const Color(0xFF155E56),
        onPrimaryContainer: const Color(0xFFAAF3E9),
        secondary: indigoLight,
        onSecondary: const Color(0xFF252E5D),
        secondaryContainer: const Color(0xFF343D70),
        onSecondaryContainer: const Color(0xFFDDE1FF),
        tertiary: const Color(0xFFB8C5FF),
        onTertiary: const Color(0xFF202F60),
        tertiaryContainer: const Color(0xFF354576),
        onTertiaryContainer: const Color(0xFFDCE1FF),
        surface: darkSurface,
        onSurface: const Color(0xFFE5E9F0),
        surfaceContainerHighest: const Color(0xFF3E464F),
        onSurfaceVariant: const Color(0xFFC2C8D0),
        outline: const Color(0xFF8C949E),
        outlineVariant: const Color(0xFF3E4751),
        inverseSurface: const Color(0xFFE5E9F0),
        onInverseSurface: const Color(0xFF283039),
        inversePrimary: teal,
        surfaceTint: const Color(0xFF73D9CC),
      );
    }

    return base.copyWith(
      primary: teal,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFCCFBF1),
      onPrimaryContainer: const Color(0xFF134E4A),
      secondary: indigo,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE2E6FF),
      onSecondaryContainer: const Color(0xFF29315F),
      tertiary: const Color(0xFF536DB2),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFDCE4FF),
      onTertiaryContainer: const Color(0xFF172B57),
      surface: lightSurface,
      onSurface: const Color(0xFF18212C),
      surfaceContainerHighest: const Color(0xFFE3E8ED),
      onSurfaceVariant: const Color(0xFF46515B),
      outline: const Color(0xFF717B85),
      outlineVariant: const Color(0xFFC5CDD5),
      inverseSurface: const Color(0xFF2C333B),
      onInverseSurface: const Color(0xFFF1F4F7),
      inversePrimary: const Color(0xFF73D9CC),
      surfaceTint: teal,
    );
  }
}

/// Extra semantic colors and branded decoration which do not belong in
/// Material's [ColorScheme].
@immutable
class LocalShareDesignTheme extends ThemeExtension<LocalShareDesignTheme> {
  const LocalShareDesignTheme({
    required this.success,
    required this.warning,
    required this.info,
    required this.surfaceRaised,
    required this.pageGradient,
    required this.brandGradient,
    required this.heroGradient,
  });

  factory LocalShareDesignTheme.from(ColorScheme scheme, {bool isOled = false}) {
    final isDark = scheme.brightness == Brightness.dark;
    final background = scheme.surface;
    final primaryGlow = scheme.primary.withOpacity(isDark ? 0.09 : 0.07);
    final secondaryGlow = scheme.secondary.withOpacity(isDark ? 0.06 : 0.045);

    return LocalShareDesignTheme(
      success: isDark ? LocalSharePalette.darkSuccess : LocalSharePalette.lightSuccess,
      warning: isDark ? LocalSharePalette.darkWarning : LocalSharePalette.lightWarning,
      info: isDark ? LocalSharePalette.darkInfo : LocalSharePalette.lightInfo,
      surfaceRaised: isOled
          ? Colors.black
          : isDark
              ? LocalSharePalette.darkSurfaceRaised
              : LocalSharePalette.lightSurfaceRaised,
      heroGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isOled
            ? const <Color>[Color(0xFF10221F), Color(0xFF141B2E)]
            : <Color>[
                scheme.primary,
                Color.lerp(scheme.primary, scheme.tertiary, 0.55)!,
              ],
      ),
      pageGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isOled
            ? const <Color>[Colors.black, Colors.black, Colors.black]
            : <Color>[
                Color.alphaBlend(primaryGlow, background),
                background,
                Color.alphaBlend(secondaryGlow, background),
              ],
        stops: const <double>[0, 0.52, 1],
      ),
      brandGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[scheme.primary, scheme.secondary],
      ),
    );
  }

  final Color success;
  final Color warning;
  final Color info;
  final Color surfaceRaised;
  final LinearGradient pageGradient;
  final LinearGradient brandGradient;
  final LinearGradient heroGradient;

  @override
  LocalShareDesignTheme copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? surfaceRaised,
    LinearGradient? pageGradient,
    LinearGradient? brandGradient,
    LinearGradient? heroGradient,
  }) {
    return LocalShareDesignTheme(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      pageGradient: pageGradient ?? this.pageGradient,
      brandGradient: brandGradient ?? this.brandGradient,
      heroGradient: heroGradient ?? this.heroGradient,
    );
  }

  @override
  LocalShareDesignTheme lerp(covariant ThemeExtension<LocalShareDesignTheme>? other, double t) {
    if (other is! LocalShareDesignTheme) {
      return this;
    }

    return LocalShareDesignTheme(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      pageGradient: LinearGradient.lerp(pageGradient, other.pageGradient, t)!,
      brandGradient: LinearGradient.lerp(brandGradient, other.brandGradient, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
    );
  }
}

extension LocalShareDesignContext on BuildContext {
  LocalShareDesignTheme get localShareDesign {
    return Theme.of(this).extension<LocalShareDesignTheme>() ?? LocalShareDesignTheme.from(Theme.of(this).colorScheme);
  }
}
