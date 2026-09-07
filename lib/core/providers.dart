import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'commands/player_command.dart';
import 'commands/player_command_bus.dart';
import 'controllers/av_controller.dart';
import 'controllers/media_router.dart';
import 'models/playback_state.dart';
import 'services/playback_service.dart';
import 'services/settings_store.dart';
import 'services/window_service.dart';

/// Câblage Riverpod du core. L'interface ne lit que ces providers.

/// Arguments de la ligne de commande (chemin à ouvrir au démarrage).
final launchArgumentsProvider = Provider<List<String>>((_) => const []);

/// Préférences persistantes. Surchargé dans `main()` après l'ouverture de Hive.
final settingsStoreProvider = Provider<SettingsStore>(
  (_) => throw UnimplementedError('settingsStoreProvider doit être surchargé'),
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

final avControllerProvider = Provider<AvController>((ref) => AvController());

/// Surface vidéo à afficher par le widget `Video`.
final videoControllerProvider =
    Provider<VideoController>((ref) => ref.watch(avControllerProvider).videoController);

final mediaRouterProvider = Provider<MediaRouter>(
  (ref) => MediaRouter([ref.watch(avControllerProvider)]),
);

final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService(
    bus: ref.watch(commandBusProvider),
    router: ref.watch(mediaRouterProvider),
    window: ref.watch(windowServiceProvider),
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

/// Raccourci d'émission pour les widgets : `ref.dispatch(const TogglePlay())`.
extension DispatchX on WidgetRef {
  void dispatch(PlayerCommand command, {CommandSource source = CommandSource.ui}) {
    read(commandBusProvider).dispatch(command, source: source);
  }
}
