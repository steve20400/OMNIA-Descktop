import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';

import '../commands/player_command.dart';
import '../commands/player_command_bus.dart';
import '../controllers/media_controller.dart';
import '../controllers/media_router.dart';
import '../models/end_of_playback_mode.dart';
import '../models/media_file.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import 'history_store.dart';
import 'playlist_service.dart';
import 'settings_store.dart';
import 'system_integration.dart';
import 'window_service.dart';

/// Chef d'orchestre de la lecture.
///
/// Écoute le [PlayerCommandBus], route chaque commande vers le bon
/// destinataire (fenêtre, playlist, contrôleur de média actif, ou lui-même) et
/// possède l'unique [PlaybackState] de l'application.
class PlaybackService implements PlaybackStateSink {
  PlaybackService({
    required PlayerCommandBus bus,
    required this.router,
    required this.window,
    required this.playlist,
    this.history,
    this.settings,
    this.system = const NoopSystemIntegration(),
    PlaybackState initialState = const PlaybackState(),
  }) : _state = initialState {
    // Le mode de fin de lecture choisi survit d'une session à l'autre.
    final storedMode = settings?.endOfPlaybackMode;
    if (storedMode != null) {
      _state = _state.copyWith(endMode: EndOfPlaybackMode.fromJson(storedMode));
    }
    _subscription = bus.stream.listen(_onCommand);
    _playlistSubscription = playlist.stream.listen(_onPlaylistChanged);
  }

  /// Routeur type → contrôleur.
  final MediaRouter router;

  /// Fenêtre native (plein écran, premier plan).
  final WindowService window;

  /// Panneau de dossier : scan, tri, navigation suivant/précédent.
  final PlaylistService playlist;

  /// Mémoire des positions de lecture. `null` désactive la reprise.
  final HistoryStore? history;

  /// Préférences persistantes (mode de fin de lecture). `null` : rien n'est
  /// mémorisé.
  final SettingsStore? settings;

  /// Intégration système (ouvrir l'emplacement d'un fichier).
  final SystemIntegration system;

  late final StreamSubscription<DispatchedCommand> _subscription;
  late final StreamSubscription<Object?> _playlistSubscription;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _state;
  MediaController? _active;

  /// Traitement séquentiel : les commandes s'exécutent dans l'ordre reçu.
  Future<void> _queue = Future<void>.value();

  /// Évite de réagir plusieurs fois à la même fin de fichier.
  bool _endHandled = false;

  /// Position mémorisée en attente d'être appliquée à l'ouverture, et le
  /// fichier qu'elle concerne : un dernier battement de position du fichier
  /// précédent ne doit pas la consommer à sa place.
  Duration? _pendingResume;
  String? _pendingResumePath;

  @override
  PlaybackState get state => _state;

  /// Flux des états successifs (n'émet pas l'état initial).
  Stream<PlaybackState> get stream => _states.stream;

  /// Contrôleur actuellement en charge du fichier courant.
  MediaController? get activeController => _active;

  /// Se termine quand toutes les commandes déjà reçues ont été traitées.
  ///
  /// Les tests s'en servent pour attendre la fin d'un traitement ; la future
  /// télécommande pourra s'en servir pour accuser réception d'une commande.
  Future<void> get idle => _queue;

  @override
  void update(PlaybackState Function(PlaybackState) reducer) {
    if (_states.isClosed) return;
    final previous = _state;
    _state = reducer(_state);
    _states.add(_state);
    _reactToStateChange(previous, _state);
  }

  /// Réactions déclenchées par un changement d'état, et non par une commande :
  /// reprise de lecture, sauvegarde de la position, fin de fichier.
  void _reactToStateChange(PlaybackState before, PlaybackState after) {
    // Appliquer la position mémorisée dès que la durée du bon fichier est
    // connue.
    final resume = _pendingResume;
    if (resume != null &&
        after.file?.path == _pendingResumePath &&
        after.duration > Duration.zero &&
        after.status != PlaybackStatus.loading) {
      _pendingResume = null;
      _pendingResumePath = null;
      if (resume < after.duration) {
        scheduleMicrotask(() => _active?.handle(SeekAbsolute(resume)));
      }
    }

    // Sauvegarder la progression au fil de la lecture, une fois par minute
    // entamée, pour ne pas écrire à chaque battement de position.
    if (before.file?.path == after.file?.path &&
        after.file != null &&
        after.duration > Duration.zero &&
        before.position.inMinutes != after.position.inMinutes) {
      unawaited(
        history?.savePosition(
          after.file!.path,
          position: after.position,
          duration: after.duration,
        ),
      );
    }

    // On réagit à la TRANSITION vers « terminé », pas à son niveau : tant que
    // le fichier suivant n'a pas commencé, d'autres mises à jour d'état (la
    // playlist qui change de fichier courant, par exemple) arrivent avec un
    // statut encore « terminé », et ne doivent pas relancer l'enchaînement.
    final justEnded = after.status == PlaybackStatus.ended &&
        before.status != PlaybackStatus.ended;
    if (justEnded && !_endHandled) {
      _endHandled = true;
      final path = after.file?.path;
      final store = history;
      if (path != null && store != null) {
        unawaited(
          store.markCompleted(path).then((_) => playlist.refreshEntry(path)),
        );
      }
      _scheduleEndOfPlayback();
    } else if (after.status != PlaybackStatus.ended) {
      _endHandled = false;
    }
  }

  void _onPlaylistChanged(Object? _) {
    // La projection playlist de PlaybackState reste synchronisée : c'est elle
    // que la future télécommande recevra.
    final visible = playlist.state.visiblePaths;
    final index = playlist.state.currentIndex;
    if (_state.playlist.length == visible.length &&
        _state.playlistIndex == index &&
        _listEquals(_state.playlist, visible)) {
      return;
    }
    update((st) => st.copyWith(playlist: visible, playlistIndex: index));
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
      case NextFile():
        final path = playlist.nextPath();
        if (path != null) await openPath(path);
      case PreviousFile():
        final path = playlist.previousPath();
        if (path != null) await openPath(path);
      case RescanFolder():
        // Traitée par PlaylistService ; rien à faire ici.
        break;
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
        unawaited(settings?.setEndOfPlaybackMode(mode.name));
      case CycleLoopMode():
        final mode = _state.endMode.nextInCycle;
        update((st) => st.copyWith(endMode: mode));
        unawaited(settings?.setEndOfPlaybackMode(mode.name));
      case RevealInFolder(:final path):
        await system.revealInFileManager(path);
      case ClearHistory():
        await history?.clear();
        // Les pastilles du panneau reflètent l'historique : on les rafraîchit.
        for (final entry in playlist.state.entries) {
          playlist.refreshEntry(entry.path);
        }
      case SetVolume() || VolumeRelative() || ToggleMute() when _active == null:
        // Le curseur de volume reste utilisable sans fichier ouvert : le
        // réglage est mémorisé et appliqué au prochain fichier.
        _applyVolumeWithoutController(command);
      default:
        // Toute autre commande concerne le média courant.
        await _active?.handle(command);
    }
  }

  void _applyVolumeWithoutController(PlayerCommand command) {
    switch (command) {
      case SetVolume(:final volume):
        update((st) => st.copyWith(volume: _clampVolume(volume), muted: false));
      case VolumeRelative(:final delta):
        update(
          (st) => st.copyWith(
            volume: _clampVolume(st.volume + delta),
            muted: false,
          ),
        );
      case ToggleMute():
        update((st) => st.copyWith(muted: !st.muted));
      default:
        break;
    }
  }

  static double _clampVolume(double value) =>
      value.clamp(PlaybackState.minVolume, PlaybackState.maxVolume);

  Future<void> _setFullscreen(bool value) async {
    await window.setFullscreen(value);
    update((st) => st.copyWith(fullscreen: value));
  }

  /// Ouvre un fichier : scan du dossier parent, choix du contrôleur, reprise
  /// éventuelle, puis lecture.
  ///
  /// La lecture ne dépend jamais du scan : celui-ci se poursuit en arrière-plan.
  Future<void> openPath(String path) async {
    await _savePositionOfCurrentFile();

    final type = MediaRouter.typeForPath(path);
    final file = MediaFile(path: path, type: type);
    final controller = router.controllerFor(type);

    playlist.setCurrent(path);
    unawaited(playlist.ensureFolderFor(path));

    if (controller == null) {
      await _closeActive(clearCurrent: false);
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
    _pendingResume = history?.entryFor(path)?.resumePosition;
    _pendingResumePath = _pendingResume == null ? null : path;
    // Inscrit le fichier dans les récents dès maintenant, avant même que la
    // lecture ait commencé.
    await history?.touch(path);

    await controller.open(file, this);
  }

  /// Ouvre un dossier : scan, puis lecture du premier fichier de la liste, dans
  /// l'ordre affiché par le panneau.
  ///
  /// Un dossier introuvable et un dossier sans média sont deux situations
  /// différentes pour l'utilisateur : chacune a son message.
  Future<void> openFolder(String path) async {
    await playlist.scanFolder(path);
    final first = playlist.state.visiblePaths.firstOrNull;
    if (first != null) {
      await openPath(first);
      return;
    }

    final exists = await folderExists(path);
    update(
      (st) => st.copyWith(
        status: PlaybackStatus.error,
        error: PlaybackError(
          exists ? PlaybackErrorCode.emptyFolder : PlaybackErrorCode.fileNotFound,
        ),
      ),
    );
  }

  /// Isolé pour pouvoir être remplacé dans les tests.
  Future<bool> folderExists(String path) => Directory(path).exists();

  /// Décide quoi faire quand le fichier courant se termine.
  ///
  /// Passe par la file de commandes : sans cela, l'enchaînement automatique
  /// s'exécuterait en parallèle d'une commande de l'utilisateur, et deux
  /// ouvertures pourraient se chevaucher.
  void _scheduleEndOfPlayback() {
    _queue = _queue.then((_) => _handleEndOfPlayback()).catchError((Object e) {
      update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.unknown, detail: e.toString()),
        ),
      );
    });
  }

  Future<void> _handleEndOfPlayback() async {
    final mode = _state.endMode;
    final next = playlist.nextForEndMode(mode);

    // Fin de dossier, ou mode « s'arrêter » : on ne fait rien de plus.
    if (next == null) return;

    if (next == _state.file?.path && mode == EndOfPlaybackMode.repeatOne) {
      // Rejouer sans repasser par une ouverture complète.
      await _active?.handle(const SeekAbsolute(Duration.zero));
      await _active?.handle(const Play());
      _endHandled = false;
      return;
    }
    await openPath(next);
  }

  Future<void> _savePositionOfCurrentFile() async {
    final file = _state.file;
    final store = history;
    if (file == null || store == null) return;
    if (_state.status == PlaybackStatus.ended) return;
    if (_state.duration <= Duration.zero) return;
    await store.savePosition(
      file.path,
      position: _state.position,
      duration: _state.duration,
    );
    playlist.refreshEntry(file.path);
  }

  Future<void> _closeActive({bool clearCurrent = true}) async {
    await _savePositionOfCurrentFile();
    final active = _active;
    _active = null;
    _pendingResume = null;
    _pendingResumePath = null;
    if (clearCurrent) playlist.setCurrent(null);
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

  /// Libère ce service. Les contrôleurs de média ne sont pas libérés ici :
  /// leur cycle de vie appartient au provider qui les a créés.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _playlistSubscription.cancel();
    await _states.close();
  }
}
