import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/providers.dart';
import 'core/services/history_store.dart';
import 'core/services/settings_store.dart';
import 'core/utils/platform_session.dart';
import 'ui/app.dart';
import 'ui/startup_failure_app.dart';
import 'ui/theme/omnia_theme.dart';

/// Point d'entrée. [args] contient le chemin à ouvrir (« Ouvrir avec »).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Le stockage local peut échouer (dossier de données inaccessible, disque
  // plein). Plutôt que de mourir sans fenêtre, OMNIA affiche l'erreur.
  final SettingsStore settings;
  final HistoryStore history;
  try {
    settings = await HiveSettingsStore.open();
    history = await HiveHistoryStore.open();
  } on Object catch (error) {
    await _showWindow(bounds: null, maximized: false);
    runApp(StartupFailureApp(detail: error.toString()));
    return;
  }

  await _showWindow(
    bounds: settings.windowBounds,
    maximized: settings.windowMaximized,
  );

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        historyStoreProvider.overrideWithValue(history),
        launchArgumentsProvider.overrideWithValue(args),
      ],
      child: const OmniaApp(),
    ),
  );
}

/// Prépare et affiche la fenêtre sans cadre.
Future<void> _showWindow({required Rect? bounds, required bool maximized}) async {
  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: bounds?.size ?? OmniaMetrics.defaultWindowSize,
    minimumSize: OmniaMetrics.minimumWindowSize,
    center: bounds == null || isWaylandSession,
    backgroundColor: OmniaColors.dark.velvet,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'OMNIA',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // Sous Wayland, positionner une fenêtre est sans effet : on laisse le
    // compositeur choisir.
    if (bounds != null && !isWaylandSession) {
      await windowManager.setPosition(bounds.topLeft);
    }
    if (maximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });
}
