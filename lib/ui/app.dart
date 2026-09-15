import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_preferences.dart';
import '../core/providers.dart';
import '../core/utils/platform_session.dart';
import '../l10n/app_localizations.dart';
import 'screens/player_screen.dart';
import 'theme/omnia_theme.dart';

/// Racine de l'application : thème, localisation, écran unique.
///
/// Mémorise aussi la géométrie de fenêtre et met à jour le titre natif.
class OmniaApp extends ConsumerStatefulWidget {
  const OmniaApp({super.key, this.onExit});

  /// Appelé quand le système demande la fermeture de l'application : libère
  /// ce qui doit l'être (verrou d'instance unique) avant de quitter.
  final Future<void> Function()? onExit;

  @override
  ConsumerState<OmniaApp> createState() => _OmniaAppState();
}

class _OmniaAppState extends ConsumerState<OmniaApp> {
  StreamSubscription<void>? _geometrySub;
  Timer? _saveDebounce;
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    final window = ref.read(windowServiceProvider);
    _geometrySub = window.geometryChanges.listen((_) {
      _saveDebounce?.cancel();
      _saveDebounce = Timer(const Duration(milliseconds: 400), _saveGeometry);
    });
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.onExit?.call();
        return AppExitResponse.exit;
      },
    );
  }

  Future<void> _saveGeometry() async {
    // Le mini-lecteur n'est pas la fenêtre principale : l'enregistrer comme
    // telle ferait rouvrir OMNIA en vignette. La géométrie principale,
    // agrandissement compris, reste celle d'avant (le mini-lecteur la rend à
    // sa sortie) ; lui retient à part sa place et sa taille.
    if (ref.read(playbackStateProvider).miniPlayer) {
      await _saveMiniGeometry();
      return;
    }

    final window = ref.read(windowServiceProvider);
    final settings = ref.read(settingsStoreProvider);
    final maximized = await window.isMaximized();
    await settings.setWindowMaximized(maximized);
    if (maximized || await window.isFullscreen()) return;

    final bounds = await window.getBounds();
    // Sous Wayland, la position rapportée est toujours (0, 0) : l'enregistrer
    // ferait revenir la fenêtre dans le coin à chaque démarrage. On ne garde
    // alors que la taille, et le compositeur choisit la place.
    await settings.setWindowBounds(
      isWaylandSession
          ? Rect.fromLTWH(0, 0, bounds.width, bounds.height)
          : bounds,
    );
  }

  /// Place (coin haut-gauche) et grand côté du mini-lecteur, repris à sa
  /// prochaine ouverture.
  Future<void> _saveMiniGeometry() async {
    final window = ref.read(windowServiceProvider);
    final settings = ref.read(settingsStoreProvider);
    final bounds = await window.getBounds();
    // Un mini-lecteur agrandi par le système (Win+↑, double clic) n'a rien à
    // retenir : place et taille seraient celles de l'écran, reprises à
    // l'entrée suivante.
    final maximized = await window.isMaximized();
    // Relu après l'attente : pendant la sortie du mini-lecteur, la fenêtre a
    // déjà repris sa taille.
    if (!mounted || maximized) return;
    final state = ref.read(playbackStateProvider);
    if (!state.miniPlayer) return;
    // Sous Wayland, la position rapportée est toujours (0, 0).
    if (!isWaylandSession) await settings.setMiniPosition(bounds.topLeft);
    // Le grand côté ne vaut que pour l'image (le bandeau audio a une taille
    // fixe), et seulement si la fenêtre en a bien la forme.
    final aspect = state.videoAspect;
    if (aspect != null &&
        bounds.height > 0 &&
        (bounds.width / bounds.height / aspect - 1).abs() < 0.02) {
      await settings.setMiniLongSide(bounds.longestSide);
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _saveDebounce?.cancel();
    _geometrySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Titre natif de la fenêtre : « fichier — OMNIA ».
    ref.listen(playbackStateProvider.select((s) => s.file?.name), (_, name) {
      final title = name == null ? 'OMNIA' : '$name — OMNIA';
      ref.read(windowServiceProvider).setTitle(title);
    });

    final themeMode = ref.watch(preferencesProvider.select((p) => p.themeMode));
    final language = ref.watch(preferencesProvider.select((p) => p.language));

    return MaterialApp(
      title: 'OMNIA',
      debugShowCheckedModeBanner: false,
      theme: buildOmniaTheme(Brightness.light),
      darkTheme: buildOmniaTheme(Brightness.dark),
      // Le sombre est le thème d'OMNIA ; clair et système se choisissent
      // dans les paramètres.
      themeMode: switch (themeMode) {
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.system => ThemeMode.system,
      },
      // Langue imposée par les paramètres, sinon celle du système.
      locale: switch (language) {
        AppLanguage.system => null,
        AppLanguage.fr => const Locale('fr'),
        AppLanguage.en => const Locale('en'),
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Français par défaut si la langue du système n'est pas prise en charge.
      localeResolutionCallback: (locale, supported) {
        if (locale == null) return const Locale('fr');
        for (final s in supported) {
          if (s.languageCode == locale.languageCode) return s;
        }
        return const Locale('fr');
      },
      home: const PlayerScreen(),
    );
  }
}
