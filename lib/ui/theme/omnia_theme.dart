import 'package:flutter/material.dart';

import 'omnia_colors.dart';
import 'omnia_metrics.dart';
import 'omnia_typography.dart';

export 'omnia_colors.dart';
export 'omnia_metrics.dart';
export 'omnia_motion.dart';
export 'omnia_typography.dart';

/// Construit le [ThemeData] d'OMNIA pour une luminosité donnée.
///
/// Le thème Material n'est qu'un support : les composants Flutter bruts ne sont
/// jamais utilisés tels quels, et les ondulations (ripples) sont désactivées.
ThemeData buildOmniaTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? OmniaColors.dark : OmniaColors.light;
  final typography = OmniaTypography.standard(primary: colors.screen, muted: colors.dust);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.projector,
    onPrimary: colors.velvet,
    secondary: colors.ember,
    onSecondary: colors.velvet,
    error: colors.alert,
    onError: colors.screen,
    surface: colors.velvet,
    onSurface: colors.screen,
    surfaceContainerHighest: colors.curtain,
    outline: colors.seam,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: OmniaFonts.ui,
    scaffoldBackgroundColor: colors.velvet,
    canvasColor: colors.velvet,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: colors.hover,
    focusColor: colors.projector.withValues(alpha: 0.25),
    dividerColor: colors.seam,
    iconTheme: IconThemeData(color: colors.dust, size: OmniaMetrics.iconSize),
    textTheme: TextTheme(
      bodySmall: typography.caption,
      bodyMedium: typography.body,
      bodyLarge: typography.bodyStrong,
      titleSmall: typography.secondary,
      titleMedium: typography.sectionTitle,
      titleLarge: typography.viewTitle,
      headlineMedium: typography.heroTitle,
      labelSmall: typography.shortcut,
      labelMedium: typography.timecode,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: colors.curtain,
        borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
        border: Border.all(color: colors.seam),
      ),
      textStyle: typography.secondary.copyWith(color: colors.screen),
      padding: const EdgeInsets.symmetric(
        horizontal: OmniaMetrics.space3,
        vertical: OmniaMetrics.space2,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.projector,
      linearTrackColor: colors.seam,
      circularTrackColor: colors.seam,
    ),
    extensions: [colors, typography],
  );
}

/// Accès direct aux jetons de design depuis n'importe quel widget.
extension OmniaThemeX on BuildContext {
  OmniaColors get colors => Theme.of(this).extension<OmniaColors>()!;
  OmniaTypography get type => Theme.of(this).extension<OmniaTypography>()!;
}
