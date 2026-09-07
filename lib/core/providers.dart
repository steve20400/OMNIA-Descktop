import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'commands/player_command.dart';
import 'commands/player_command_bus.dart';
import 'controllers/av_controller.dart';
import 'controllers/media_router.dart';
import 'models/playback_state.dart';
import 'models/playlist_state.dart';
import 'services/folder_scanner.dart';
import 'services/history_store.dart';
import 'services/playback_service.dart';
import 'services/playlist_service.dart';
import 'services/settings_store.dart';
import 'services/system_integration.dart';
import 'services/window_service.dart';

/// Câblage Riverpod du core. L'interface ne lit que ces providers.

/// Arguments de la ligne de commande (chemin à ouvrir au démarrage).
final launchArgumentsProvider = Provider<List<String>>((_) => const []);

/// Préférences persistantes. Surchargé dans `main()` après l'ouverture de Hive.
final settingsStoreProvider = Provider<SettingsStore>(
  (_) => throw UnimplementedError('settingsStoreProvider doit être surchargé'),
);

/// Positions de lecture et fichiers récents. Surchargé dans `main()`.
final historyStoreProvider = Provider<HistoryStore>(
  (_) => throw UnimplementedError('historyStoreProvider doit être surchargé'),
);

final commandBusProvider = Provider<PlayerCommandBus>((ref) {
  final bus = PlayerCommandBus();
  ref.onDispose(bus.dispose);
  return bus;
});

final windowServiceProvider = Provider<WindowService>((ref) {
  final service = WindowManagerService();
  ref.onDispose(service.dispose);
  return service;
});

final systemIntegrationProvider =
    Provider<SystemIntegration>((_) => const DesktopSystemIntegration());

final folderScannerProvider =
    Provider<FolderScanner>((_) => const IsolateFolderScanner());

/// Moteur audio/vidéo. Ce provider possède le cycle de vie de mpv : il est le
/// seul à le libérer.
final avControllerProvider = Provider<AvController>((ref) {
  final controller = AvController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Surface vidéo à afficher par le widget `Video`.
final videoControllerProvider =
    Provider<VideoController>((ref) => ref.watch(avControllerProvider).videoController);

final mediaRouterProvider = Provider<MediaRouter>(
  (ref) => MediaRouter([ref.watch(avControllerProvider)]),
);

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  final router = ref.watch(mediaRouterProvider);
  final service = PlaylistService(
    bus: ref.watch(commandBusProvider),
    scanner: ref.watch(folderScannerProvider),
    history: ref.watch(historyStoreProvider),
    settings: ref.watch(settingsStoreProvider),
    // Le panneau liste tout le dossier ; la navigation n'enchaîne que sur ce
    // qu'un contrôleur sait réellement ouvrir.
    isPlayable: (path) => router.controllerForPath(path) != null,
  );
  ref.onDispose(service.dispose);
  return service;
});

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService(
    bus: ref.watch(commandBusProvider),
    router: ref.watch(mediaRouterProvider),
    window: ref.watch(windowServiceProvider),
    playlist: ref.watch(playlistServiceProvider),
    history: ref.watch(historyStoreProvider),
    settings: ref.watch(settingsStoreProvider),
    system: ref.watch(systemIntegrationProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// État de lecture observable par l'interface.
final playbackStateProvider =
    NotifierProvider<PlaybackStateNotifier, PlaybackState>(PlaybackStateNotifier.new);

class PlaybackStateNotifier extends Notifier<PlaybackState> {
  @override
  PlaybackState build() {
    final service = ref.watch(playbackServiceProvider);
    final sub = service.stream.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return service.state;
  }
}

/// État du panneau de dossier observable par l'interface.
final playlistStateProvider =
    NotifierProvider<PlaylistStateNotifier, PlaylistState>(PlaylistStateNotifier.new);

class PlaylistStateNotifier extends Notifier<PlaylistState> {
  @override
  PlaylistState build() {
    // On dépend du service de lecture pour garantir qu'il est instancié : sans
    // lui, personne n'écouterait le bus de commandes.
    ref.watch(playbackServiceProvider);
    final service = ref.watch(playlistServiceProvider);
    final sub = service.stream.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return service.state;
  }
}

/// Raccourci d'émission pour les widgets : `ref.dispatch(const TogglePlay())`.
extension DispatchX on WidgetRef {
  void dispatch(PlayerCommand command, {CommandSource source = CommandSource.ui}) {
    read(commandBusProvider).dispatch(command, source: source);
  }
}
