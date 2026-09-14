import 'package:flutter/widgets.dart';

/// Dimensions, rayons et espacements (aucune valeur en dur dans les widgets).
abstract final class OmniaMetrics {
  // Espacements.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space8 = 48;

  // Rayons.
  static const double radiusSmall = 6;
  static const double radiusMedium = 10;
  static const double radiusLarge = 14;
  static const BorderRadius overlayRadius = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius controlRadius = BorderRadius.all(Radius.circular(radiusMedium));

  // Flou et ombre des surfaces flottantes.
  static const double overlayBlur = 18;
  static const double overlayShadowBlur = 24;
  static const double overlayShadowAlpha = 0.35;

  // Barre de titre et contrôles.
  static const double titleBarHeight = 40;
  static const double windowButtonWidth = 46;
  static const double controlBarMargin = 16;
  static const double controlBarPadding = 12;
  static const double controlBarMaxWidth = 1120;
  static const double iconButtonSize = 34;
  static const double iconSize = 20;
  static const double iconSizeLarge = 26;
  static const double playButtonSize = 44;

  // Faisceau (barre de progression).
  static const double beamHitHeight = 28;
  static const double beamRestThickness = 2;
  static const double beamHoverThickness = 6;
  static const double beamLampRadiusRest = 3;
  static const double beamLampRadiusHover = 6;
  static const double beamGlowSigmaRest = 6;
  static const double beamGlowSigmaHover = 9;
  static const double beamTooltipHeight = 24;

  // Curseur de volume.
  static const double volumeSliderWidth = 88;
  static const double volumeSliderThickness = 3;
  static const double volumeThumbRadius = 5;

  // Panneau latéral (Phase 2).
  static const double panelDefaultWidth = 300;
  static const double panelMinWidth = 220;
  static const double panelMaxWidth = 520;

  // OSD (Phase 3).
  static const double osdLevelWidth = 96;

  // Menus (contextuel, récents).
  static const double menuMinWidth = 220;
  static const double menuMaxWidth = 380;
  static const double menuItemHeight = 34;

  // Écran Paramètres (Phase 6).
  static const double settingsMaxWidth = 940;
  static const double settingsMaxHeight = 680;
  static const double settingsNavWidth = 208;
  static const double settingsRowBreakpoint = 520;
  static const double settingsSliderWidth = 160;
  static const double settingsValueWidth = 64;
  static const double switchWidth = 38;
  static const double switchHeight = 22;
  static const double keyCapMinWidth = 28;

  /// Invite de reprise : au-dessus de la barre de contrôles.
  static const double resumePromptBottom = 128;

  // Fenêtre.
  static const Size defaultWindowSize = Size(1200, 760);
  static const Size minimumWindowSize = Size(720, 460);
}
