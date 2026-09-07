import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/providers.dart';
import 'core/services/settings_store.dart';
import 'ui/app.dart';
import 'ui/theme/omnia_theme.dart';

/// Point d'entrée. [args] contient le chemin à ouvrir (« Ouvrir avec »).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final settings = await HiveSettingsStore.open();

  await windowManager.ensureInitialized();
  final bounds = settings.windowBounds;
  final options = WindowOptions(
    size: bounds?.size ?? OmniaMetrics.defaultWindowSize,
    minimumSize: OmniaMetrics.minimumWindowSize,
    center: bounds == null,
    backgroundColor: OmniaColors.dark.velvet,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'OMNIA',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (bounds != null) await windowManager.setPosition(bounds.topLeft);
    if (settings.windowMaximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        launchArgumentsProvider.overrideWithValue(args),
      ],
      child: const OmniaApp(),
    ),
  );
}
