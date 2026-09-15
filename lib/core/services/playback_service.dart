import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect, Size;

import 'package:collection/collection.dart';

import '../commands/player_command.dart';
import '../commands/player_command_bus.dart';
import '../controllers/frame_capturer.dart';
import '../controllers/media_controller.dart';
import '../controllers/media_router.dart';
import '../controllers/stream_recorder.dart';
import '../models/app_preferences.dart';
import '../models/end_of_playback_mode.dart';
import '../models/history_entry.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../models/resume_offer.dart';
import 'history_store.dart';
import 'playlist_service.dart';
import 'screenshot_service.dart';
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
    this.screenshots,
    this.system = const NoopSystemIntegration(),
    this.recordingCheckDelay = const Duration(milliseconds: 150),
    PlaybackState initialState = const PlaybackState(),
  }) : _state = initialState {
    final store = settings;
    if (store != null) {
      // Ce que l'utilisateur a choisi survit d'une session à l'autre : mode de
      // fin de lecture, volume, vitesse, sous-titres, égaliseur, documents.
      final storedMode = store.endOfPlaybackMode;
      final prefs = store.preferences;
      final volume = prefs.startupVolume == StartupVolume.fixed
          ? prefs.fixedVolume
          : (store.lastVolume ?? _state.volume);
      _state = _state.copyWith(
        endMode: storedMode == null ? null : EndOfPlaybackMode.fromJson(storedMode),
        volume: volume.clamp(PlaybackState.minVolume, PlaybackState.maxVolume),
        speed: prefs.defaultSpeed,
        subtitleScale: prefs.subtitleScale,
        equalizerEnabled: prefs.equalizerEnabled,
        equalizerGains: prefs.equalizerGains,
        readingDark: prefs.readingDark,
        documentLayout: prefs.pdfLayout,
      );
    }
    _subscription = bus.stream.listen(_onCommand);
    _playlistSubscription = playlist.stream.listen(_onPlaylistChanged);
  }

  /// Préférences courantes (valeurs par défaut sans stockage).
  AppPreferences get preferences => settings?.preferences ?? AppPreferences.defaults;

  /// Émet les préférences après chaque modification enregistrée.
  Stream<AppPreferences> get preferencesChanges => _preferencesChanges.stream;

  final StreamController<AppPreferences> _preferencesChanges =
      StreamController<AppPreferences>.broadcast();

  /// Sauvegarde différée des réglages suivis en direct (volume, égaliseur…) :
  /// un glissement de curseur produit des dizaines de changements.
  Timer? _preferencesSave;

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

  /// Enregistrement des captures d'écran. `null` désactive la capture.
  final ScreenshotService? screenshots;

  /// Géométrie et état de premier plan à restaurer en quittant le mini-lecteur.
  Rect? _boundsBeforeMini;
  bool _alwaysOnTopBeforeMini = false;

  /// Taille du mini-lecteur et minimum de fenêtre du lecteur principal.
  static const Size miniPlayerSize = Size(400, 132);
  static const Size mainMinimumSize = Size(720, 460);

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

  /// Même chose pour les documents : page (PDF) ou défilement (texte).
  int? _pendingResumePage;
  double? _pendingResumeScroll;

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

    // Documents : dès que le document est prêt, revenir à la dernière page ou
    // position lue.
    if (after.isDocument &&
        after.status == PlaybackStatus.playing &&
        after.file?.path == _pendingResumePath) {
      final page = _pendingResumePage;
      final scroll = _pendingResumeScroll;
      _pendingResumePath = null;
      _pendingResumePage = null;
      _pendingResumeScroll = null;
      if (page != null && after.totalPages > 0 && page <= after.totalPages) {
        scheduleMicrotask(() => _active?.handle(GoToPage(page)));
      } else if (scroll != null) {
        scheduleMicrotask(() => _active?.handle(ScrollTo(scroll)));
      }
    }

    // Documents : mémoriser page et défilement à chaque changement. Ce sont
    // des événements rares (un tour de page, une fin de défilement), pas un
    // battement continu.
    if (after.isDocument &&
        after.file != null &&
        before.file?.path == after.file!.path &&
        after.status == PlaybackStatus.playing &&
        (before.currentPage != after.currentPage ||
            before.scrollFraction != after.scrollFraction)) {
      unawaited(
        history?.saveDocumentPosition(
          after.file!.path,
          page: after.currentPage > 0 ? after.currentPage : null,
          pageCount: after.totalPages > 0 ? after.totalPages : null,
          scrollFraction: after.scrollFraction,
        ),
      );
    }

    // Sauvegarder la progression au fil de la lecture, une fois par minute
    // entamée, pour ne pas écrire à chaque battement de position.
    if (!after.isDocument &&
        before.file?.path == after.file?.path &&
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

    // Réglages suivis en direct : ce que l'utilisateur change pendant la
    // lecture devient sa préférence (dernier volume, taille des sous-titres,
    // égaliseur, mode sombre de lecture, mise en page, taille du texte).
    if (settings != null &&
        (before.volume != after.volume ||
            before.equalizerEnabled != after.equalizerEnabled ||
            !_listEquals(before.equalizerGains, after.equalizerGains) ||
            before.subtitleScale != after.subtitleScale ||
            before.readingDark != after.readingDark ||
            before.documentLayout != after.documentLayout ||
            (after.mediaType == MediaType.text && before.zoom != after.zoom))) {
      _schedulePreferencesSave();
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

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // --- Préférences -------------------------------------------------------------

  void _schedulePreferencesSave() {
    _preferencesSave?.cancel();
    _preferencesSave = Timer(const Duration(milliseconds: 500), _savePreferencesNow);
  }

  /// Recopie dans les préférences les réglages suivis en direct.
  Future<void> _savePreferencesNow() async {
    _preferencesSave?.cancel();
    _preferencesSave = null;
    final store = settings;
    if (store == null) return;

    final s = _state;
    if (store.lastVolume != s.volume) await store.setLastVolume(s.volume);

    final current = store.preferences;
    final next = current.copyWith(
      equalizerEnabled: s.equalizerEnabled,
      equalizerGains: s.equalizerGains,
      subtitleScale: s.subtitleScale,
      readingDark: s.readingDark,
      pdfLayout: s.documentLayout,
      textScale: s.mediaType == MediaType.text ? s.zoom : null,
    );
    if (next != current) {
      await store.setPreferences(next);
      if (!_preferencesChanges.isClosed) _preferencesChanges.add(next);
    }
  }

  /// Applique des préférences venues de l'écran Paramètres.
  ///
  /// Ce qui est en cours est aligné AVANT l'enregistrement : la sauvegarde
  /// différée des réglages suivis en direct recopiera alors les mêmes
  /// valeurs, au lieu d'annuler le changement.
  Future<void> _applyPreferences(AppPreferences next) async {
    await _alignLiveState(next);
    await settings?.setPreferences(next);
    if (!_preferencesChanges.isClosed) _preferencesChanges.add(next);
  }

  Future<void> _alignLiveState(AppPreferences p) async {
    final active = _active;

    Future<bool> tryHandle(PlayerCommand command) async =>
        await active?.handle(command) ?? false;

    if (_state.subtitleScale != p.subtitleScale &&
        !await tryHandle(SetSubtitleScale(p.subtitleScale))) {
      update((st) => st.copyWith(subtitleScale: p.subtitleScale));
    }

    if (!_listEquals(_state.equalizerGains, p.equalizerGains) ||
        _state.equalizerEnabled != p.equalizerEnabled) {
      var handled = await tryHandle(SetEqualizerGains(p.equalizerGains));
      if (handled && _state.equalizerEnabled != p.equalizerEnabled) {
        handled = await tryHandle(const ToggleEqualizer());
      }
      if (!handled) {
        update(
          (st) => st.copyWith(
            equalizerGains: p.equalizerGains,
            equalizerEnabled: p.equalizerEnabled,
          ),
        );
      }
    }

    if (_state.readingDark != p.readingDark &&
        !await tryHandle(const ToggleReadingDarkMode())) {
      update((st) => st.copyWith(readingDark: p.readingDark));
    }

    if (_state.documentLayout != p.pdfLayout &&
        !await tryHandle(SetDocumentLayout(p.pdfLayout))) {
      update((st) => st.copyWith(documentLayout: p.pdfLayout));
    }

    if (_state.mediaType == MediaType.text && _state.zoom != p.textScale) {
      await tryHandle(SetZoom(p.textScale));
    }
  }

  // --- Reprise de lecture --------------------------------------------------------

  /// Ce qu'il y aurait à reprendre pour ce fichier, selon son type.
  static ResumeOffer? _offerFrom(MediaType type, HistoryEntry? entry) {
    if (entry == null) return null;
    if (type.isDocument) {
      final page = entry.resumePage;
      if (page != null) return ResumeOffer(page: page);
      final scroll = entry.resumeScroll;
      return scroll == null ? null : ResumeOffer(scroll: scroll);
    }
    final position = entry.resumePosition;
    return position == null ? null : ResumeOffer(position: position);
  }

  void _clearPendingResume() {
    _pendingResume = null;
    _pendingResumePath = null;
    _pendingResumePage = null;
    _pendingResumeScroll = null;
  }

  /// Applique une reprise : tout de suite si le fichier est prêt, sinon dès
  /// qu'il le sera (voir [_reactToStateChange]).
  Future<void> _resumeTo(ResumeOffer offer) async {
    final path = _state.file?.path;
    if (path == null) return;

    if (_state.isDocument) {
      if (_state.status == PlaybackStatus.playing) {
        final page = offer.page;
        final scroll = offer.scroll;
        if (page != null && (_state.totalPages == 0 || page <= _state.totalPages)) {
          await _active?.handle(GoToPage(page));
        } else if (scroll != null) {
          await _active?.handle(ScrollTo(scroll));
        }
      } else {
        _pendingResumePage = offer.page;
        _pendingResumeScroll = offer.scroll;
        _pendingResumePath = path;
      }
      return;
    }

    final position = offer.position;
    if (position == null) return;
    final ready = _state.duration > Duration.zero && _state.status != PlaybackStatus.loading;
    if (ready) {
      if (position < _state.duration) await _active?.handle(SeekAbsolute(position));
    } else {
      _pendingResume = position;
      _pendingResumePath = path;
    }
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
        _refreshPlaylistBadges();
      case ClearRecentFiles():
        await history?.clearRecent();
      case ClearResumePositions():
        await history?.clearPositions();
        _refreshPlaylistBadges();
      case AcceptResume():
        final offer = _state.resumeOffer;
        if (offer != null) {
          update((st) => st.copyWith(clearResumeOffer: true));
          await _resumeTo(offer);
        }
      case DeclineResume():
        if (_state.resumeOffer != null) {
          update((st) => st.copyWith(clearResumeOffer: true));
        }
      case UpdatePreferences(:final changes):
        await _applyPreferences(preferences.merge(changes));
      case SetScreenshotFolder(:final path):
        await settings?.setScreenshotFolder(path);
      case TakeScreenshot():
        await _takeScreenshot();
      case ToggleRecording():
        await (_state.recording ? _stopRecording() : _startRecording());
      case ToggleMiniPlayer():
        await _setMiniPlayer(!_state.miniPlayer);
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

  /// Les pastilles du panneau reflètent l'historique : on les relit.
  void _refreshPlaylistBadges() {
    for (final entry in playlist.state.entries) {
      playlist.refreshEntry(entry.path);
    }
  }

  Future<void> _setFullscreen(bool value) async {
    await window.setFullscreen(value);
    update((st) => st.copyWith(fullscreen: value));
  }

  /// Capture l'image affichée et l'enregistre. Le chemin est publié dans
  /// l'état : c'est lui que l'OSD montre.
  Future<void> _takeScreenshot() async {
    // `FrameCapturer` n'est pas un sous-type de `MediaController` : Dart ne
    // promeut pas la variable directement, d'où le passage par `Object?`.
    final Object? capturer = _active;
    final store = screenshots;
    final file = _state.file;
    // L'état décrit le résultat de CETTE tentative : sans cela, une capture
    // impossible (fichier audio) afficherait le chemin de la précédente.
    update((st) => st.copyWith(clearLastScreenshot: true, screenshotFailed: false));
    if (capturer is! FrameCapturer || store == null || file == null) return;
    final png = await capturer.captureFrame();
    if (png == null) return;
    try {
      final path = await store.save(png, mediaPath: file.path, position: _state.position);
      update((st) => st.copyWith(lastScreenshot: path));
    } on FileSystemException {
      // Dossier inaccessible : la lecture continue, l'OSD le signale, et le
      // dossier se change dans les paramètres.
      update((st) => st.copyWith(screenshotFailed: true));
    }
  }

  /// Mini-lecteur : fenêtre compacte toujours au premier plan. On mémorise la
  /// géométrie et l'état de premier plan pour les rendre à la sortie.
  Future<void> _setMiniPlayer(bool enabled) async {
    if (enabled == _state.miniPlayer) return;
    if (enabled) {
      if (_state.fullscreen) await _setFullscreen(false);
      _boundsBeforeMini = await window.getBounds();
      _alwaysOnTopBeforeMini = _state.alwaysOnTop;
      await window.setMinimumSize(miniPlayerSize);
      final origin = _boundsBeforeMini!.topLeft;
      await window.setBounds(origin & miniPlayerSize);
      await window.setAlwaysOnTop(true);
      update((st) => st.copyWith(miniPlayer: true, alwaysOnTop: true));
    } else {
      await window.setMinimumSize(mainMinimumSize);
      final previous = _boundsBeforeMini;
      if (previous != null) await window.setBounds(previous);
      await window.setAlwaysOnTop(_alwaysOnTopBeforeMini);
      update((st) => st.copyWith(miniPlayer: false, alwaysOnTop: _alwaysOnTopBeforeMini));
      _boundsBeforeMini = null;
    }
  }

  /// Ouvre un fichier : scan du dossier parent, choix du contrôleur, reprise
  /// éventuelle, puis lecture.
  ///
  /// La lecture ne dépend jamais du scan : celui-ci se poursuit en arrière-plan.
  Future<void> openPath(String path) async {
    // Un extrait en cours s'arrête avec son fichier : il ne continue pas sur
    // le suivant.
    await _stopRecording();
    await _savePositionOfCurrentFile();

    final type = MediaRouter.typeForPath(path);
    final file = MediaFile(path: path, type: type);
    final controller = router.controllerFor(type);

    // Le mini-lecteur ne sait montrer que l'audio et la vidéo : un document
    // déposé dessus (ou une erreur de format) reprend la fenêtre entière.
    if (_state.miniPlayer && !type.isAv) await _setMiniPlayer(false);

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

    // Reprise : automatique, proposée, ou jamais, selon les préférences.
    final offer = _offerFrom(type, history?.entryFor(path));
    final policy = preferences.resumePolicy;
    _clearPendingResume();
    if (offer != null && policy == ResumePolicy.auto) {
      _pendingResume = offer.position;
      _pendingResumePage = offer.page;
      _pendingResumeScroll = offer.scroll;
      _pendingResumePath = path;
    }
    if (_state.resumeOffer != null) {
      update((st) => st.copyWith(clearResumeOffer: true));
    }

    // Inscrit le fichier dans les récents dès maintenant, avant même que la
    // lecture ait commencé.
    await history?.touch(path);

    await controller.open(file, this);

    if (offer != null && policy == ResumePolicy.ask && _state.file?.path == path) {
      update((st) => st.copyWith(resumeOffer: offer));
    }
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
    await _stopRecording();
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
    // Les documents sont mémorisés au fil des changements de page.
    if (_state.isDocument) return;
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
    await _stopRecording();
    await _savePositionOfCurrentFile();
    final active = _active;
    _active = null;
    _clearPendingResume();
    if (_state.resumeOffer != null) {
      update((st) => st.copyWith(clearResumeOffer: true));
    }
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

  // --- Extraits ----------------------------------------------------------

  /// Délai entre deux vérifications du fichier d'un extrait arrêté.
  /// Surchargeable dans les tests.
  final Duration recordingCheckDelay;

  /// Commence un extrait du média audio ou vidéo en cours, dans le dossier
  /// et sous le motif de nom des captures.
  Future<void> _startRecording() async {
    // Comme pour la capture : passage par `Object?` pour la promotion de type.
    final Object? recorder = _active;
    final store = screenshots;
    final file = _state.file;
    if (recorder is! StreamRecorder || store == null || file == null || !file.type.isAv) return;
    if (_state.status == PlaybackStatus.error) return;

    update((st) => st.copyWith(recordingFailed: false, clearLastRecording: true));
    try {
      final path = await store.recordingPath(
        mediaPath: file.path,
        audioOnly: !_state.hasVideo,
        position: _state.position,
      );
      if (await recorder.startRecording(path)) {
        update((st) => st.copyWith(recordingPath: path, recordingStartedAt: DateTime.now()));
        return;
      }
    } on FileSystemException {
      // Dossier des captures inaccessible : même message qu'une capture.
    }
    update((st) => st.copyWith(recordingFailed: true));
  }

  /// Arrête l'extrait en cours, s'il y en a un, et vérifie qu'il a bien été
  /// écrit. Un fichier vide (lecture restée en pause, format refusé par
  /// l'enregistreur) est supprimé et signalé.
  Future<void> _stopRecording() async {
    final path = _state.recordingPath;
    if (path == null) return;
    final Object? recorder = _active;
    if (recorder is StreamRecorder) await recorder.stopRecording();

    final saved = await _recordingWritten(path);
    if (!saved) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Fichier vide impossible à retirer : sans conséquence.
      }
    }
    update(
      (st) => st.copyWith(
        clearRecording: true,
        lastRecording: saved ? path : null,
        clearLastRecording: !saved,
        recordingFailed: !saved,
      ),
    );
  }

  /// mpv finalise le fichier juste après l'arrêt : on lui laisse un court
  /// délai avant de conclure qu'il n'a rien écrit.
  Future<bool> _recordingWritten(String path) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final f = File(path);
      if (await f.exists() && await f.length() > 0) return true;
      await Future<void>.delayed(recordingCheckDelay);
    }
    return false;
  }

  /// Libère ce service. Les contrôleurs de média ne sont pas libérés ici :
  /// leur cycle de vie appartient au provider qui les a créés.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _playlistSubscription.cancel();
    // Un extrait en cours est finalisé : le fichier resterait sinon illisible.
    await _stopRecording();
    // Une sauvegarde de réglages en attente est faite tout de suite, pour ne
    // pas perdre le dernier volume à la fermeture.
    if (_preferencesSave != null) await _savePreferencesNow();
    await _states.close();
    await _preferencesChanges.close();
  }
}
