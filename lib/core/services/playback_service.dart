import 'dart:async';
import 'dart:io';

import '../commands/player_command.dart';
import '../commands/player_command_bus.dart';
import '../controllers/media_controller.dart';
import '../controllers/media_router.dart';
import '../models/media_file.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import 'window_service.dart';

/// Chef d'orchestre de la lecture.
///
/// Écoute le [PlayerCommandBus], route chaque commande vers le bon
/// destinataire (fenêtre, contrôleur de média actif, ou lui-même) et possède
/// l'unique [PlaybackState] de l'application.
class PlaybackService implements PlaybackStateSink {
  PlaybackService({
    required PlayerCommandBus bus,
    required this.router,
    required this.window,
    PlaybackState initialState = const PlaybackState(),
  }) : _state = initialState {
    _subscription = bus.stream.listen(_onCommand);
  }

  /// Routeur type → contrôleur.
  final MediaRouter router;

  /// Fenêtre native (plein écran, premier plan).
  final WindowService window;
  late final StreamSubscription<DispatchedCommand> _subscription;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _state;
  MediaController? _active;

  /// Traitement séquentiel : les commandes s'exécutent dans l'ordre reçu.
  Future<void> _queue = Future<void>.value();

  @override
  PlaybackState get state => _state;

  /// Flux des états successifs (n'émet pas l'état initial).
  Stream<PlaybackState> get stream => _states.stream;

  /// Contrôleur actuellement en charge du fichier courant.
  MediaController? get activeController => _active;

  @override
  void update(PlaybackState Function(PlaybackState) reducer) {
    if (_states.isClosed) return;
    _state = reducer(_state);
    _states.add(_state);
  }

  void _onCommand(DispatchedCommand dispatched) {
    _queue = _queue.then((_) => _handle(dispatched.command)).catchError((Object e) {
      update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.unknown, detail: e.toString()),
        ),
      );
    });
  }

  Future<void> _handle(PlayerCommand command) async {
    switch (command) {
      case OpenFile(:final path):
        await openPath(path);
      case OpenFolder(:final path):
        await openFolder(path);
      case Stop():
        await _closeActive();
      case ToggleFullscreen():
        await _setFullscreen(!_state.fullscreen);
      case ExitFullscreen():
        if (_state.fullscreen) await _setFullscreen(false);
      case ToggleAlwaysOnTop():
        final next = !_state.alwaysOnTop;
        await window.setAlwaysOnTop(next);
        update((st) => st.copyWith(alwaysOnTop: next));
      case SetLoopMode(:final mode):
        update((st) => st.copyWith(endMode: mode));
      case CycleLoopMode():
        update((st) => st.copyWith(endMode: st.endMode.nextInCycle));
      default:
        // Toute autre commande concerne le média courant.
        await _active?.handle(command);
    }
  }

  Future<void> _setFullscreen(bool value) async {
    await window.setFullscreen(value);
    update((st) => st.copyWith(fullscreen: value));
  }

  /// Ouvre un fichier : choix du contrôleur, fermeture de l'ancien si besoin,
  /// puis délégation. Le scan du dossier parent viendra en Phase 2.
  Future<void> openPath(String path) async {
    final type = MediaRouter.typeForPath(path);
    final file = MediaFile(path: path, type: type);
    final controller = router.controllerFor(type);

    if (controller == null) {
      await _closeActive();
      update(
        (st) => st.copyWith(
          file: file,
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.unsupportedFormat),
        ),
      );
      return;
    }

    if (_active != null && !identical(_active, controller)) {
      await _active!.close();
    }
    _active = controller;
    await controller.open(file, this);
  }

  /// Ouvre un dossier : en attendant le scan complet (Phase 2), lit le premier
  /// fichier lisible par ordre alphabétique.
  Future<void> openFolder(String path) async {
    final dir = Directory(path);
    List<String> candidates;
    try {
      candidates = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where(MediaRouter.isSupported)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } on FileSystemException catch (e) {
      update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.permissionDenied, detail: e.message),
        ),
      );
      return;
    }
    if (candidates.isEmpty) return;
    await openPath(candidates.first);
  }

  Future<void> _closeActive() async {
    final active = _active;
    _active = null;
    if (active != null) {
      await active.close();
    } else {
      update(
        (st) => st.copyWith(
          clearFile: true,
          status: PlaybackStatus.idle,
          clearError: true,
        ),
      );
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _states.close();
    for (final c in router.controllers) {
      await c.dispose();
    }
  }
}
