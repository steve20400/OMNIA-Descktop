import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_preferences.dart';
import '../../core/providers.dart';
import '../theme/omnia_theme.dart';

/// Le thème « Mixte » est-il choisi ?
final mixedThemeProvider = Provider<bool>(
  (ref) => ref.watch(preferencesProvider.select((p) => p.themeMode == AppThemeMode.mixed)),
);

/// L'espace où s'affiche un média — vidéo, image, pages d'un PDF, son —,
/// habillé du thème sombre quand le thème « Mixte » est choisi.
///
/// En thème clair, tout ce que le média ne couvrait pas devenait blanc : les
/// bandes autour d'une vidéo plus large que l'écran, le tour d'une photo, le
/// fond entre les pages d'un PDF. Le thème Mixte garde l'interface claire —
/// barre de titre, panneau, commandes — et rend cet espace noir, comme dans
/// une salle de projection (retour du 24 novembre).
class MediaStageTheme extends ConsumerWidget {
  const MediaStageTheme({super.key, required this.child});

  final Widget child;

  static final ThemeData _dark = buildOmniaTheme(Brightness.dark);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Toujours un [Theme], même inchangé : changer de thème dans les
    // paramètres ne démonte pas la scène, ni la vidéo qu'elle montre.
    return Theme(
      data: ref.watch(mixedThemeProvider) ? _dark : Theme.of(context),
      child: child,
    );
  }
}
