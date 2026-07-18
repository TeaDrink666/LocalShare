import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/dynamic_colors.dart';
import 'package:localsend_app/widget/localshare_design/design_tokens.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:yaru/yaru.dart' as yaru;

final _borderRadius = BorderRadius.circular(LocalShareRadii.medium);
final _buttonRadius = BorderRadius.circular(LocalShareRadii.medium);
final _cardRadius = BorderRadius.circular(LocalShareRadii.large);
final _dialogRadius = BorderRadius.circular(LocalShareRadii.extraLarge);

/// On desktop, we need to add additional padding to achieve the same visual appearance as on mobile.
double get desktopPaddingFix => checkPlatformIsDesktop() ? 8 : 0;

ThemeData getTheme(
    ColorMode colorMode, Brightness brightness, DynamicColors? dynamicColors) {
  if (colorMode == ColorMode.yaru) {
    return _getYaruTheme(brightness);
  }

  final colorScheme =
      _determineColorScheme(colorMode, brightness, dynamicColors);
  return _buildTheme(
    colorScheme: colorScheme,
    fontFamily: _resolveFontFamily(),
    isOled: colorMode == ColorMode.oled,
  );
}

ThemeData _buildTheme({
  required ColorScheme colorScheme,
  required String? fontFamily,
  bool isOled = false,
  ThemeData? baseTheme,
}) {
  final isDark = colorScheme.brightness == Brightness.dark;
  final isDesktop = checkPlatformIsDesktop();
  final foundation = baseTheme ??
      ThemeData(
        brightness: colorScheme.brightness,
        colorScheme: colorScheme,
        useMaterial3: true,
        fontFamily: fontFamily,
      );
  final textTheme = _buildTextTheme(foundation.textTheme, fontFamily);
  final surface = isOled ? Colors.black : colorScheme.surface;
  final raisedSurface = isOled
      ? const Color(0xFF090909)
      : Color.alphaBlend(
          colorScheme.primary.withOpacity(isDark ? 0.035 : 0.018),
          colorScheme.surface,
        );
  final mutedSurface = isOled
      ? const Color(0xFF111111)
      : Color.alphaBlend(
          colorScheme.primary.withOpacity(isDark ? 0.07 : 0.045),
          colorScheme.surface,
        );
  final inputFill = isOled
      ? const Color(0xFF121212)
      : Color.alphaBlend(
          colorScheme.primary.withOpacity(isDark ? 0.075 : 0.04),
          colorScheme.surface,
        );
  final borderColor =
      colorScheme.outlineVariant.withOpacity(isDark ? 0.8 : 0.75);

  final inputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: borderColor),
    borderRadius: _borderRadius,
  );
  final focusedInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
    borderRadius: _borderRadius,
  );
  final errorInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.error, width: 1.3),
    borderRadius: _borderRadius,
  );
  final disabledInputBorder = OutlineInputBorder(
    borderSide: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
    borderRadius: _borderRadius,
  );
  final buttonPadding = EdgeInsets.symmetric(
    horizontal: LocalShareSpacing.lg,
    vertical: isDesktop ? 14 : 13,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: _buttonRadius);
  final buttonTextStyle =
      textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600);
  final selectedNavigationLabel = textTheme.labelMedium?.copyWith(
    color: colorScheme.primary,
    fontWeight: FontWeight.w700,
  );
  final unselectedNavigationLabel = textTheme.labelMedium?.copyWith(
    color: colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w500,
  );

  return foundation.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    cardColor: raisedSurface,
    dividerColor: colorScheme.outlineVariant.withOpacity(0.65),
    disabledColor: colorScheme.onSurface.withOpacity(0.38),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[
      LocalShareDesignTheme.from(colorScheme, isOled: isOled),
    ],
    iconTheme: IconThemeData(
      color: colorScheme.onSurfaceVariant,
      size: 22,
    ),
    primaryIconTheme: IconThemeData(
      color: colorScheme.onPrimary,
      size: 22,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: isDesktop ? 64 : 60,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant, size: 22),
      actionsIconTheme:
          IconThemeData(color: colorScheme.onSurfaceVariant, size: 22),
      titleTextStyle:
          textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardTheme(
      color: raisedSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withOpacity(isDark ? 0.28 : 0.09),
      elevation: isDark ? 0 : 0.6,
      margin: const EdgeInsets.all(LocalShareSpacing.xs),
      shape: RoundedRectangleBorder(
        borderRadius: _cardRadius,
        side: BorderSide(
            color:
                colorScheme.outlineVariant.withOpacity(isDark ? 0.48 : 0.62)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: raisedSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow.withOpacity(isDark ? 0.48 : 0.18),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: _dialogRadius,
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      titleTextStyle:
          textTheme.headlineSmall?.copyWith(color: colorScheme.onSurface),
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: raisedSurface,
      modalBackgroundColor: raisedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      modalElevation: 12,
      showDragHandle: true,
      dragHandleColor: colorScheme.outline.withOpacity(0.65),
      dragHandleSize: const Size(36, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(LocalShareRadii.extraLarge)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withOpacity(0.65),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: focusedInputBorder,
      errorBorder: errorInputBorder,
      focusedErrorBorder: errorInputBorder,
      disabledBorder: disabledInputBorder,
      contentPadding: EdgeInsets.symmetric(
        horizontal: LocalShareSpacing.md,
        vertical: isDesktop ? 14 : 15,
      ),
      floatingLabelStyle:
          TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle:
          TextStyle(color: colorScheme.onSurfaceVariant.withOpacity(0.7)),
      prefixIconColor: colorScheme.onSurfaceVariant,
      suffixIconColor: colorScheme.onSurfaceVariant,
      errorStyle:
          TextStyle(color: colorScheme.error, fontWeight: FontWeight.w500),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(buttonPadding),
        shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(buttonTextStyle),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withOpacity(0.38);
          }
          return colorScheme.primary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withOpacity(0.08);
          }
          return states.contains(WidgetState.pressed)
              ? mutedSurface
              : raisedSurface;
        }),
        overlayColor: _interactionOverlay(colorScheme.primary),
        elevation: WidgetStateProperty.resolveWith<double>((states) {
          if (states.contains(WidgetState.disabled)) return 0;
          if (states.contains(WidgetState.pressed)) return 0;
          if (states.contains(WidgetState.hovered)) return 2;
          return isDark ? 0 : 0.8;
        }),
        shadowColor:
            WidgetStatePropertyAll<Color>(colorScheme.shadow.withOpacity(0.12)),
        surfaceTintColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        animationDuration: LocalShareDurations.quick,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(buttonPadding),
        shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(buttonTextStyle),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.disabled)
              ? colorScheme.onSurface.withOpacity(0.38)
              : colorScheme.onPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.disabled)
              ? colorScheme.onSurface.withOpacity(0.1)
              : colorScheme.primary;
        }),
        overlayColor: _interactionOverlay(colorScheme.onPrimary),
        elevation: const WidgetStatePropertyAll<double>(0),
        animationDuration: LocalShareDurations.quick,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(buttonPadding),
        shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(buttonTextStyle),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.disabled)
              ? colorScheme.onSurface.withOpacity(0.38)
              : colorScheme.primary;
        }),
        side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
          final color = states.contains(WidgetState.disabled)
              ? colorScheme.outline.withOpacity(0.3)
              : states.contains(WidgetState.focused)
                  ? colorScheme.primary
                  : colorScheme.outlineVariant;
          return BorderSide(
              color: color,
              width: states.contains(WidgetState.focused) ? 1.5 : 1);
        }),
        overlayColor: _interactionOverlay(colorScheme.primary),
        animationDuration: LocalShareDurations.quick,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(40, 44)),
        padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(
              horizontal: LocalShareSpacing.md, vertical: isDesktop ? 12 : 10),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(buttonShape),
        textStyle: WidgetStatePropertyAll<TextStyle?>(buttonTextStyle),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.disabled)
              ? colorScheme.onSurface.withOpacity(0.38)
              : colorScheme.primary;
        }),
        overlayColor: _interactionOverlay(colorScheme.primary),
        animationDuration: LocalShareDurations.quick,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
        iconSize: const WidgetStatePropertyAll<double>(22),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          return states.contains(WidgetState.disabled)
              ? colorScheme.onSurface.withOpacity(0.38)
              : colorScheme.onSurfaceVariant;
        }),
        overlayColor: _interactionOverlay(colorScheme.primary),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
        animationDuration: LocalShareDurations.quick,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 1,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      splashColor: colorScheme.onPrimaryContainer.withOpacity(0.1),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.large)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: raisedSurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      indicatorColor:
          colorScheme.primaryContainer.withOpacity(isDark ? 0.72 : 0.82),
      indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.medium)),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          size: selected ? 24 : 22,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        return states.contains(WidgetState.selected)
            ? selectedNavigationLabel
            : unselectedNavigationLabel;
      }),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      elevation: 0,
      backgroundColor: raisedSurface,
      useIndicator: true,
      indicatorColor:
          colorScheme.primaryContainer.withOpacity(isDark ? 0.72 : 0.82),
      indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.medium)),
      minWidth: 76,
      minExtendedWidth: 224,
      selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 24),
      unselectedIconTheme:
          IconThemeData(color: colorScheme.onSurfaceVariant, size: 22),
      selectedLabelTextStyle: selectedNavigationLabel,
      unselectedLabelTextStyle: unselectedNavigationLabel,
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: raisedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      indicatorColor: colorScheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.medium)),
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        return states.contains(WidgetState.selected)
            ? selectedNavigationLabel
            : unselectedNavigationLabel;
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      selectedColor: colorScheme.primary,
      selectedTileColor:
          colorScheme.primaryContainer.withOpacity(isDark ? 0.36 : 0.46),
      contentPadding: const EdgeInsets.symmetric(
          horizontal: LocalShareSpacing.md, vertical: LocalShareSpacing.xxs),
      minLeadingWidth: 24,
      minVerticalPadding: LocalShareSpacing.sm,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.medium)),
      titleTextStyle: textTheme.bodyLarge
          ?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
      subtitleTextStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: raisedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: colorScheme.shadow.withOpacity(isDark ? 0.4 : 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LocalShareRadii.medium),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.55)),
      ),
      textStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedInputBorder,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: LocalShareSpacing.md, vertical: 14),
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(raisedSurface),
        surfaceTintColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double>(8),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LocalShareRadii.medium)),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.all(LocalShareSpacing.xs)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: mutedSurface,
      selectedColor: colorScheme.primaryContainer,
      disabledColor: colorScheme.onSurface.withOpacity(0.08),
      labelStyle:
          textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
      side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.full)),
      padding: const EdgeInsets.symmetric(
          horizontal: LocalShareSpacing.sm, vertical: LocalShareSpacing.xs),
      showCheckmark: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: colorScheme.onInverseSurface),
      actionTextColor: colorScheme.inversePrimary,
      elevation: 8,
      insetPadding: const EdgeInsets.all(LocalShareSpacing.md),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LocalShareRadii.medium)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 4),
      preferBelow: true,
      padding: const EdgeInsets.symmetric(
          horizontal: LocalShareSpacing.sm, vertical: LocalShareSpacing.xs),
      margin: const EdgeInsets.all(LocalShareSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(LocalShareRadii.small),
      ),
      textStyle:
          textTheme.labelMedium?.copyWith(color: colorScheme.onInverseSurface),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor:
          colorScheme.primaryContainer.withOpacity(isDark ? 0.3 : 0.5),
      circularTrackColor:
          colorScheme.primaryContainer.withOpacity(isDark ? 0.3 : 0.5),
      linearMinHeight: 6,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: colorScheme.outline, width: 1.5),
      fillColor: _selectionFill(colorScheme),
      checkColor: WidgetStatePropertyAll<Color>(colorScheme.onPrimary),
    ),
    radioTheme: RadioThemeData(
      fillColor: _selectionFill(colorScheme),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withOpacity(0.38);
        }
        return states.contains(WidgetState.selected)
            ? colorScheme.onPrimary
            : colorScheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withOpacity(0.1);
        }
        return states.contains(WidgetState.selected)
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : colorScheme.outline;
      }),
    ),
    sliderTheme: foundation.sliderTheme.copyWith(
      activeTrackColor: colorScheme.primary,
      inactiveTrackColor: colorScheme.primaryContainer.withOpacity(0.48),
      thumbColor: colorScheme.primary,
      overlayColor: colorScheme.primary.withOpacity(0.12),
      valueIndicatorColor: colorScheme.inverseSurface,
      valueIndicatorTextStyle:
          textTheme.labelMedium?.copyWith(color: colorScheme.onInverseSurface),
      trackHeight: 4,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith<double?>(
          (states) => states.contains(WidgetState.hovered) ? 8 : 5),
      radius: const Radius.circular(LocalShareRadii.full),
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return colorScheme.onSurfaceVariant
            .withOpacity(states.contains(WidgetState.hovered) ? 0.55 : 0.32);
      }),
      trackColor: WidgetStatePropertyAll<Color>(
          colorScheme.surfaceContainerHighest.withOpacity(0.2)),
      trackBorderColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colorScheme.primary,
      selectionColor: colorScheme.primary.withOpacity(isDark ? 0.35 : 0.22),
      selectionHandleColor: colorScheme.primary,
    ),
  );
}

TextTheme _buildTextTheme(TextTheme base, String? fontFamily) {
  final themed = base.copyWith(
    displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1.08),
    displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.1),
    displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.45, height: 1.14),
    headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.35, height: 1.2),
    headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.22),
    headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: -0.1, height: 1.25),
    titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: -0.15, height: 1.28),
    titleMedium: base.titleMedium
        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0, height: 1.35),
    titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: 0.05, height: 1.35),
    bodyLarge: base.bodyLarge
        ?.copyWith(fontWeight: FontWeight.w400, letterSpacing: 0, height: 1.5),
    bodyMedium: base.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400, letterSpacing: 0.05, height: 1.45),
    bodySmall: base.bodySmall?.copyWith(
        fontWeight: FontWeight.w400, letterSpacing: 0.1, height: 1.4),
    labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: 0.1, height: 1.25),
    labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: 0.2, height: 1.25),
    labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600, letterSpacing: 0.25, height: 1.25),
  );

  return fontFamily == null ? themed : themed.apply(fontFamily: fontFamily);
}

WidgetStateProperty<Color?> _interactionOverlay(Color color) {
  return WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed)) return color.withOpacity(0.12);
    if (states.contains(WidgetState.focused)) return color.withOpacity(0.1);
    if (states.contains(WidgetState.hovered)) return color.withOpacity(0.07);
    return null;
  });
}

WidgetStateProperty<Color?> _selectionFill(ColorScheme colorScheme) {
  return WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.disabled)) {
      return colorScheme.onSurface.withOpacity(0.12);
    }
    if (states.contains(WidgetState.selected)) return colorScheme.primary;
    return Colors.transparent;
  });
}

String? _resolveFontFamily() {
  // https://github.com/localsend/localsend/issues/52
  if (!checkPlatform([TargetPlatform.windows])) {
    return null;
  }

  return switch (LocaleSettings.currentLocale) {
    AppLocale.ja => 'Yu Gothic UI',
    AppLocale.ko => 'Malgun Gothic',
    AppLocale.zhCn => 'Microsoft YaHei UI',
    AppLocale.zhHk || AppLocale.zhTw => 'Microsoft JhengHei UI',
    _ => 'Segoe UI Variable Display',
  };
}

Future<void> updateSystemOverlayStyle(BuildContext context) async {
  final brightness = Theme.of(context).brightness;
  await updateSystemOverlayStyleWithBrightness(brightness);
}

Future<void> updateSystemOverlayStyleWithBrightness(
    Brightness brightness) async {
  if (checkPlatform([TargetPlatform.android])) {
    // See https://github.com/flutter/flutter/issues/90098
    final darkMode = brightness == Brightness.dark;
    final androidSdkInt =
        RefenaScope.defaultRef.read(deviceInfoProvider).androidSdkInt ?? 0;
    final bool edgeToEdge = androidSdkInt >= 29;

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          brightness == Brightness.light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: edgeToEdge
          ? Colors.transparent
          : (darkMode ? Colors.black : Colors.white),
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness:
          darkMode ? Brightness.light : Brightness.dark,
    ));
  } else {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarBrightness: brightness, // iOS
      statusBarColor: Colors.transparent, // Not relevant to this issue
    ));
  }
}

extension ThemeDataExt on ThemeData {
  /// This is the actual [cardColor] being used.
  Color get cardColorWithElevation {
    return ElevationOverlay.applySurfaceTint(
        cardColor, colorScheme.surfaceTint, 1);
  }
}

extension ColorSchemeExt on ColorScheme {
  Color get warning {
    return brightness == Brightness.dark
        ? LocalSharePalette.darkWarning
        : LocalSharePalette.lightWarning;
  }

  Color? get secondaryContainerIfDark {
    return brightness == Brightness.dark ? secondaryContainer : null;
  }

  Color? get onSecondaryContainerIfDark {
    return brightness == Brightness.dark ? onSecondaryContainer : null;
  }
}

extension InputDecorationThemeExt on InputDecorationTheme {
  BorderRadius get borderRadius => _borderRadius;
}

ColorScheme _determineColorScheme(
    ColorMode mode, Brightness brightness, DynamicColors? dynamicColors) {
  final defaultColorScheme = LocalSharePalette.scheme(brightness);

  final colorScheme = switch (mode) {
    ColorMode.system => brightness == Brightness.light
        ? dynamicColors?.light
        : dynamicColors?.dark,
    ColorMode.localsend => null,
    ColorMode.oled =>
      (dynamicColors?.dark ?? LocalSharePalette.scheme(Brightness.dark))
          .copyWith(
        surface: Colors.black,
        surfaceContainerHighest: const Color(0xFF151515),
        surfaceTint: Colors.transparent,
      ),
    ColorMode.yaru => throw 'Should reach here',
  };

  return colorScheme ?? defaultColorScheme;
}

ThemeData _getYaruTheme(Brightness brightness) {
  final baseTheme =
      brightness == Brightness.light ? yaru.yaruLight : yaru.yaruDark;
  return _buildTheme(
    colorScheme: baseTheme.colorScheme,
    fontFamily: _resolveFontFamily(),
    baseTheme: baseTheme,
  );
}
