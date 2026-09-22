import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/commands/player_command_bus.dart';
import 'core/models/app_preferences.dart';
import 'core/models/window_sizes.dart';
import 'core/providers.dart';
import 'core/services/history_store.dart';
import 'core/services/local_storage.dart';
import 'core/services/settings_store.dart';
import 'core/services/single_instance.dart';
import 'core/utils/launch_arguments.dart';
import 'core/utils/platform_session.dart';
import 'ui/app.dart';
import 'ui/startup_failure_app.dart';
import 'ui/theme/omnia_theme.dart';

/// Point d'entrée. [args] contient le chemin à ouvrir (« Ouvrir avec »).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final isNewWindow = args.contains('--new-window');
  final cleanArgs = args.where((a) => a != '--new-window').toList();

  // Instance unique (réglable) : si OMNIA tourne déjà, on lui confie le
  // fichier et on se retire, plutôt que d'ouvrir une seconde fenêtre.
  final Directory dataDirectory;
  final SingleInstanceService instance;
  final bool single;
  try {
    dataDirectory = await localStorageDirectory();
    single = singleInstanceEnabled(dataDirectory);
    instance = SingleInstanceService(directory: dataDirectory);
    if (single && !isNewWindow && await instance.delegateToExisting(cleanArgs)) {
      exit(0);
    }
  } on Object catch (error) {
    await _showWindow(bounds: null, maximized: false);
    runApp(StartupFailureApp(detail: error.toString()));
    return;
  }

  // Le stockage local peut échouer (dossier de données inaccessible, disque
  // plein). Plutôt que de mourir sans fenêtre, OMNIA affiche l'erreur.
  SettingsStore settings;
  HistoryStore history;
  try {
    settings = await HiveSettingsStore.open();
    history = await HiveHistoryStore.open(dataDirectory: dataDirectory);
  } on Object catch (error) {
    if (single && !isNewWindow) {
      await _showWindow(bounds: null, maximized: false);
      runApp(StartupFailureApp(detail: error.toString()));
      return;
    }
    // Plusieurs fenêtres autorisées ou fenêtre détachée : la première tient la base Hive.
    // Celle-ci démarre avec des réglages en mémoire relus depuis la copie en clair,
    // et son historique est persisté dans le fichier partagé history.json.
    settings = MemorySettingsStore(
      preferences: readPreferencesSnapshot(dataDirectory) ?? const AppPreferences(),
    );
    history = FileHistoryStore(dataDirectory);
  }

  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWithValue(settings),
      historyStoreProvider.overrideWithValue(history),
      launchArgumentsProvider.overrideWithValue(cleanArgs),
    ],
  );

  // Devenir la première instance : les suivantes nous enverront leurs
  // arguments, qu'on traite comme une ouverture depuis le système.
  if (single && !isNewWindow) {
    try {
      await instance.serve((remoteArgs) {
        // Fichier déposé sur l'icône, « Ouvrir avec » : même règle qu'un dépôt
        // sur la fenêtre, sous-titre sur la vidéo en cours compris.
        final state = container.read(playbackStateProvider);
        final command = commandForLaunchArguments(
          remoteArgs,
          videoPlaying: state.hasFile && state.hasVideo,
        );
        unawaited(container.read(windowServiceProvider).focus());
        if (command != null) {
          container.read(commandBusProvider).dispatch(command, source: CommandSource.system);
        }
      });
    } on Object {
      // Port local indisponible : on fonctionne sans instance unique, ce qui
      // vaut mieux que de ne pas démarrer.
    }
  }

  await _showWindow(
    bounds: settings.windowBounds,
    maximized: settings.windowMaximized,
    alwaysOnTop: settings.preferences.normalPlayerAlwaysOnTop,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: OmniaApp(
        onExit: instance.dispose,
        showSplash: cleanArgs.isEmpty,
      ),
    ),
  );
}

/// Prépare et affiche la fenêtre sans cadre.
Future<void> _showWindow({
  required Rect? bounds,
  required bool maximized,
  bool alwaysOnTop = false,
}) async {
  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: bounds?.size ?? WindowSizes.mainDefault,
    minimumSize: WindowSizes.mainMinimum,
    center: bounds == null || isWaylandSession,
    backgroundColor: OmniaColors.dark.velvet,
    alwaysOnTop: alwaysOnTop,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'OMNIA',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // Sous Wayland, positionner une fenêtre est sans effet : on laisse le
    // compositeur choisir.
    if (bounds != null && !isWaylandSession) {
      await windowManager.setPosition(bounds.topLeft);
    }
    await windowManager.setMinimumSize(WindowSizes.mainMinimum);
    if (maximized) await windowManager.maximize();
    if (alwaysOnTop) await windowManager.setAlwaysOnTop(true);
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
}
