import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../l10n/app_localizations.dart';
import 'screens/player_screen.dart';
import 'theme/omnia_theme.dart';

/// Racine de l'application : thème, localisation, écran unique.
///
/// Mémorise aussi la géométrie de fenêtre et met à jour le titre natif.
class OmniaApp extends ConsumerStatefulWidget {
  const OmniaApp({super.key});

  @override
  ConsumerState<OmniaApp> createState() => _OmniaAppState();
}

class _OmniaAppState extends ConsumerState<OmniaApp> {
  StreamSubscription<void>? _geometrySub;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    final window = ref.read(windowServiceProvider);
    _geometrySub = window.geometryChanges.listen((_) {
      _saveDebounce?.cancel();
      _saveDebounce = Timer(const Duration(milliseconds: 400), _saveGeometry);
    });
  }

  Future<void> _saveGeometry() async {
    final window = ref.read(windowServiceProvider);
    final settings = ref.read(settingsStoreProvider);
    final maximized = await window.isMaximized();
    await settings.setWindowMaximized(maximized);
    if (!maximized && !await window.isFullscreen()) {
      await settings.setWindowBounds(await window.getBounds());
    }
  }

  @override
  void dispose() {
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

    return MaterialApp(
      title: 'OMNIA',
      debugShowCheckedModeBanner: false,
      theme: buildOmniaTheme(Brightness.light),
      darkTheme: buildOmniaTheme(Brightness.dark),
      // Le thème sombre est le thème d'OMNIA ; le clair devient sélectionnable
      // dans les paramètres (Phase 6).
      themeMode: ThemeMode.dark,
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
