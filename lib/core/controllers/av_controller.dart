import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../commands/player_command.dart';
import '../models/app_preferences.dart';
import '../models/equalizer.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../models/recording_failure.dart';
import '../models/track_info.dart';
import '../models/video_adjust.dart';
import '../utils/os_errors.dart';
import 'frame_capturer.dart';
import 'media_controller.dart';
import 'stream_recorder.dart';

/// Contrôleur audio/vidéo basé sur media_kit (libmpv).
///
/// Un seul [Player] pour toute la vie de l'application : ouvrir un nouveau
/// fichier remplace le précédent sans recréer le moteur (ouverture < 1 s).
///
/// Tout ce que media_kit n'expose pas directement (sourdine, sous-titres
/// externes automatiques, boucle A-B, image, égaliseur) passe par les
/// propriétés mpv, derrière [_setProperty] qui n'échoue jamais bruyamment :
/// une propriété refusée par une version de mpv laisse la lecture intacte.
class AvController implements MediaController, FrameCapturer, StreamRecorder {
  /// [withVideoOutput] à `false` : aucune surface de rendu n'est créée, et
  /// [videoController] reste inutilisable. Réservé aux tests qui pilotent
  /// libmpv sans interface : la surface attend le moteur Flutter et ses canaux
  /// de plateforme, et sans eux tout appel à mpv resterait en attente.
  AvController({
    Player? player,
    AppPreferences Function()? preferences,
    bool withVideoOutput = true,
  })
      // libass : mpv dessine les sous-titres dans l'image, et media_kit retire
      // sa propre couche de texte. Sans cela, activer une piste les
      // affichait deux fois, et « masquer » laissait la copie de media_kit.
      //
      // Journal du moteur jusqu'aux avertissements : c'est à ce niveau que mpv
      // dit pourquoi il refuse d'écrire un extrait, et le niveau `warn` reste
      // silencieux en lecture ordinaire.
      : player = player ??
            Player(
              configuration: const PlayerConfiguration(
                libass: true,
                logLevel: MPVLogLevel.warn,
              ),
            ),
        _preferences = preferences ?? (() => AppPreferences.defaults) {
    if (withVideoOutput) videoController = VideoController(this.player);
    _listen();
    unawaited(_applyBaseProperties());
  }

  /// Moteur mpv.
  final Player player;

  /// Préférences lues à chaque ouverture (sous-titres automatiques, décalage
  /// par défaut) : un changement dans les paramètres vaut dès le fichier suivant.
  final AppPreferences Function() _preferences;

  /// Surface de rendu vidéo, consommée par le widget `Video` de l'interface.
  /// Non initialisée quand le contrôleur est créé sans sortie vidéo.
  late final VideoController videoController;

  PlaybackStateSink? _sink;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Vrai entre `open()` et le premier événement de lecture, pour ne pas
  /// afficher « en pause » pendant le chargement.
  bool _opening = false;

  /// Pistes rapportées par mpv pour le fichier courant, pour retrouver un
  /// objet piste à partir de son identifiant.
  Tracks _tracks = const Tracks();

  /// Dernières lignes du journal de mpv, gardées en mémoire pour expliquer un
  /// extrait manqué. Ce n'est pas un journal, c'est un indice : le nombre est
  /// volontairement court, car ces lignes finissent dans une annotation de CI,
  /// tronquée à 4 096 caractères.
  final List<String> _mpvLogs = [];
  static const int _mpvLogsKept = 40;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  /// Réglages mpv valables pour toute la session.
  ///
  /// media_kit impose des réglages de rendu économiques (mise à l'échelle
  /// bilinéaire, aucun tramage). On rétablit ceux d'un mpv autonome : le
  /// tramage évite les dégradés en escalier (ciel, scènes sombres) des vidéos
  /// 10 bits affichées en 8 bits, et les filtres de mise à l'échelle ne
  /// coûtent rien tant que l'image est rendue à sa taille d'origine.
  Future<void> _applyBaseProperties() async {
    // Une seule image demandée à la capture, pas de bande-son de clic.
    await _setProperty('screenshot-format', 'png');
    await _setProperty('dither', 'fruit');
    await _setProperty('dither-depth', 'auto');
    await _setProperty('scale', 'spline36');
    await _setProperty('dscale', 'mitchell');
    await _setProperty('correct-downscaling', 'yes');
    await _applyCacheProperties();
  }

  /// Cache du démultiplexeur, dont dépend tout l'enregistrement d'extraits.
  ///
  /// mpv n'active son cache que pour les flux réseau quand `cache=auto` ;
  /// media_kit le force déjà à `yes`, ce qui vaut aussi pour un fichier local.
  /// On le réaffirme : sans cache, `dump-cache` n'a rien à recopier et un
  /// extrait de fichier local reste vide. `demuxer-seekable-cache` suit
  /// (`auto` vaut déjà `yes` dès que `cache=yes`, mais mpv remet à zéro le
  /// cache arrière quand le cache n'est pas navigable, et c'est ce cache
  /// arrière qui fournit l'extrait).
  ///
  /// `cache-on-disk` en revanche est ramené à `no` : media_kit l'active, ce qui
  /// déplace la charge utile de chaque paquet dans un fichier temporaire. Pour
  /// un lecteur de fichiers locaux, cela n'apporte rien (le média est déjà sur
  /// le disque) et ajoute une relecture — donc un risque d'échec — au moment
  /// précis où l'on recopie le cache dans un extrait. La documentation de mpv
  /// est formelle : ce réglage ne se retire pas en cours de lecture (« If the
  /// option is disabled at runtime, old data remains in the disk cache »), il
  /// faut donc le poser AVANT d'ouvrir le fichier.
  ///
  /// Appliqué à l'ouverture de la session *et* avant chaque fichier : mpv lit
  /// ces réglages quand il crée le démultiplexeur, c'est-à-dire à l'ouverture.
  Future<void> _applyCacheProperties() async {
    await _setProperty('cache', 'yes');
    await _setProperty('cache-on-disk', 'no');
    await _setProperty('demuxer-seekable-cache', 'yes');
    await _setProperty('demuxer-max-back-bytes', '$_idleBackBufferBytes');
  }

  // Position : mpv la publie à chaque image affichée, soit 25 à 60 fois par
  // seconde (et deux fois plus à 2×). L'interface n'en a pas besoin d'autant,
  // et chaque mise à jour la reconstruit : on en garde six par seconde au
  // plus. Un saut (recherche, nouveau fichier) passe tout de suite.
  final Stopwatch _positionClock = Stopwatch()..start();
  Duration _lastPosition = Duration.zero;

  void _onPosition(Duration position) {
    final jump = (position - _lastPosition).abs() > const Duration(milliseconds: 900);
    if (!jump && _positionClock.elapsedMilliseconds < 150) return;
    _publishPosition(position);
  }

  void _publishPosition(Duration position) {
    _positionClock.reset();
    _lastPosition = position;
    _update((st) => st.copyWith(position: position));
  }

  void _listen() {
    final s = player.stream;
    _subscriptions.addAll([
      // Journal de mpv : c'est là qu'il dit pourquoi il refuse d'écrire un
      // extrait (« Failed opening output file. », « Can't mux one of the input
      // streams. », « Writing header failed. »). media_kit ne remonte pas ces
      // lignes comme des erreurs de lecture : sans elles, un extrait manqué
      // resterait sans explication.
      s.log.listen((entry) {
        _mpvLogs.add('[${entry.level}] ${entry.prefix} : ${entry.text}');
        if (_mpvLogs.length > _mpvLogsKept) _mpvLogs.removeAt(0);
      }),
      s.position.listen(_onPosition),
      s.duration.listen((duration) => _update((st) => st.copyWith(duration: duration))),
      s.buffering.listen((buffering) => _update((st) => st.copyWith(buffering: buffering))),
      s.volume.listen((volume) => _update((st) => st.copyWith(volume: volume))),
      s.rate.listen((rate) => _update((st) => st.copyWith(speed: rate))),
      // Dimensions d'affichage de l'image : media_kit les tire de
      // `video-out-params` (dw, dh), rapport d'aspect et rotation compris.
      // Largeur et hauteur arrivent sur deux flux, mais l'état du moteur tient
      // déjà les deux : on publie la paire, sans ratio intermédiaire (nouvelle
      // largeur, ancienne hauteur) qui redimensionnerait le mini-lecteur pour
      // rien. `null` : moteur remis à zéro entre deux fichiers, ce que
      // `open()` et `close()` ont déjà reporté dans l'état.
      s.width.listen((width) {
        if (width == null) return;
        _update(
          (st) => st.copyWith(
            hasVideo: width > 0,
            videoWidth: width,
            videoHeight: player.state.height ?? st.videoHeight,
          ),
        );
      }),
      s.height.listen((height) {
        if (height == null) return;
        _update(
          (st) => st.copyWith(
            videoWidth: player.state.width ?? st.videoWidth,
            videoHeight: height,
          ),
        );
      }),
      s.tracks.listen((tracks) {
        _tracks = tracks;
        _update(
          (st) => st.copyWith(
            subtitleTracks: tracks.subtitle.where(_isRealTrack).map(_toInfo).toList(),
            audioTracks: tracks.audio.where(_isRealTrack).map(_toInfo).toList(),
          ),
        );
      }),
      s.track.listen((track) {
        _update(
          (st) => st.copyWith(
            subtitleTrackId: _isRealTrack(track.subtitle) ? track.subtitle.id : null,
            clearSubtitleTrack: !_isRealTrack(track.subtitle),
            audioTrackId: _isRealTrack(track.audio) ? track.audio.id : null,
            clearAudioTrack: !_isRealTrack(track.audio),
          ),
        );
      }),
      s.playing.listen((playing) {
        if (playing) _opening = false;
        // À la pause, la position affichée est l'exacte, pas la dernière
        // retenue par le filtre de fréquence.
        if (!playing) _publishPosition(player.state.position);
        _update((st) {
          if (st.status == PlaybackStatus.error) return st;
          if (!playing && _opening) return st;
          return st.copyWith(
            status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          );
        });
      }),
      s.completed.listen((completed) {
        if (!completed) return;
        _update((st) => st.copyWith(status: PlaybackStatus.ended));
      }),
      s.error.listen((message) {
        // mpv émet aussi des erreurs non fatales en cours de lecture (une
        // piste de sous-titres illisible, un paquet corrompu). Interrompre la
        // lecture pour cela remplacerait une image qui s'affiche par un écran
        // d'erreur. On ne bascule en erreur que si rien ne joue encore.
        final st = _sink?.state;
        final fatal = _opening ||
            st == null ||
            st.status == PlaybackStatus.loading ||
            st.duration <= Duration.zero;
        if (!fatal) return;
        _opening = false;
        _update(
          (state) => state.copyWith(
            status: PlaybackStatus.error,
            error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: message),
          ),
        );
      }),
    ]);
  }

  /// media_kit liste aussi les pseudo-pistes « auto » et « no ».
  static bool _isRealTrack(Object track) {
    final id = switch (track) {
      SubtitleTrack(:final id) => id,
      AudioTrack(:final id) => id,
      VideoTrack(:final id) => id,
      _ => '',
    };
    return id != 'auto' && id != 'no';
  }

  static TrackInfo _toInfo(Object track) => switch (track) {
        SubtitleTrack(:final id, :final title, :final language, :final uri) => TrackInfo(
            id: id,
            title: title ?? (uri ? p.basename(id) : null),
            language: language,
            external: uri,
          ),
        AudioTrack(:final id, :final title, :final language, :final uri) =>
          TrackInfo(id: id, title: title, language: language, external: uri),
        _ => const TrackInfo(id: '?'),
      };

  void _update(PlaybackState Function(PlaybackState) reducer) {
    _sink?.update(reducer);
  }

  /// Écrit une propriété mpv. Une propriété inconnue ou refusée ne doit pas
  /// interrompre la lecture : on l'ignore.
  Future<void> _setProperty(String name, String value) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(name, value);
    } on Object {
      // Propriété absente de cette version de mpv, ou moteur déjà libéré.
    }
  }

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    _opening = true;

    if (!File(file.path).existsSync()) {
      _opening = false;
      // Remettre position, durée et présence vidéo à zéro : sans cela, l'état
      // garderait celles du fichier précédent, et la sauvegarde de position
      // les attribuerait au nouveau fichier.
      sink.update(
        (st) => st.copyWith(
          file: file,
          status: PlaybackStatus.error,
          position: Duration.zero,
          duration: Duration.zero,
          hasVideo: false,
          videoWidth: 0,
          videoHeight: 0,
          error: const PlaybackError(PlaybackErrorCode.fileNotFound),
        ),
      );
      return;
    }

    final prefs = _preferences();
    // Vitesse, volume, sourdine, sous-titres, image et égaliseur sont
    // conservés d'un fichier à l'autre. On les relève AVANT d'ouvrir : le
    // moteur peut publier ses propres valeurs pendant l'ouverture, qui
    // écraseraient celles de l'utilisateur.
    final state = sink.state;

    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: file.type == MediaType.video,
        // Dimensions de l'image : connues seulement une fois la première image
        // décodée. Jusque-là, le mini-lecteur garde sa forme.
        videoWidth: 0,
        videoHeight: 0,
        // Propres à chaque fichier : pistes, boucle A-B, décalage des
        // sous-titres, zoom et rotation de l'image.
        subtitleTracks: const [],
        audioTracks: const [],
        clearSubtitleTrack: true,
        clearAudioTrack: true,
        clearLoop: true,
        subtitleDelay: prefs.subtitleDelay,
        videoZoom: 0,
        videoRotation: 0,
        clearError: true,
      ),
    );

    try {
      // Réglages du cache avant d'ouvrir : mpv les lit quand il crée le
      // démultiplexeur, et c'est ce cache qui fournira les extraits.
      await _applyCacheProperties();
      // Sous-titres voisins chargés automatiquement : même nom de base, avec
      // ou sans suffixe de langue (`film.srt`, `film.fr.srt`).
      await _setProperty('sub-auto', prefs.subtitleAutoLoad ? 'fuzzy' : 'no');
      await _setProperty('ab-loop-a', 'no');
      await _setProperty('ab-loop-b', 'no');
      await _setProperty('sub-delay', prefs.subtitleDelay.toStringAsFixed(2));
      await _setProperty('video-zoom', '0');
      await _setProperty('video-rotate', '0');

      await player.open(Media(file.path), play: true);

      await player.setRate(state.speed);
      await player.setVolume(state.volume);
      await _setMuted(state.muted);
      await _setProperty('sub-visibility', state.subtitlesVisible ? 'yes' : 'no');
      await _setProperty('sub-scale', state.subtitleScale.toStringAsFixed(2));
      await _applyNeutralAspect();
      await _applyAdjust(state.videoAdjust);
      await _applyEqualizer(state.equalizerEnabled ? state.equalizerGains : Equalizer.flat);
    } on Object catch (e) {
      _opening = false;
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(_classify(e), detail: e.toString()),
        ),
      );
    }
  }

  PlaybackErrorCode _classify(Object error) {
    if (error is FileSystemException) return classifyFileSystemError(error);
    return PlaybackErrorCode.decodeFailed;
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final state = _sink?.state;
    if (state == null || !state.hasFile) return false;

    switch (command) {
      case Play():
        await player.play();
      case Pause():
        await player.pause();
      case TogglePlay():
        if (state.status == PlaybackStatus.ended) {
          await player.seek(Duration.zero);
          await player.play();
        } else {
          await player.playOrPause();
        }
      case SeekRelative(:final seconds):
        await _seekTo(state.position + Duration(milliseconds: (seconds * 1000).round()));
      case SeekAbsolute(:final position):
        await _seekTo(position);
      case SetVolume(:final volume):
        await _setVolume(volume);
      case VolumeRelative(:final delta):
        await _setVolume(state.volume + delta);
      case ToggleMute():
        await _setMuted(!state.muted);
      case SetSpeed(:final speed):
        await _setSpeed(speed);
      case SpeedRelative(:final delta):
        await _setSpeed(state.speed + delta);

      // Sous-titres
      case SetSubtitleTrack(:final id):
        await _selectSubtitle(id);
      case ToggleSubtitles():
        final visible = !state.subtitlesVisible;
        await _setProperty('sub-visibility', visible ? 'yes' : 'no');
        _update((st) => st.copyWith(subtitlesVisible: visible));
      case LoadSubtitleFile(:final path):
        await player.setSubtitleTrack(SubtitleTrack.uri(path, title: p.basename(path)));
        await _setProperty('sub-visibility', 'yes');
        _update((st) => st.copyWith(subtitlesVisible: true));
      case SetSubtitleDelay(:final seconds):
        await _setSubtitleDelay(seconds);
      case SubtitleDelayRelative(:final delta):
        await _setSubtitleDelay(state.subtitleDelay + delta);
      case SetSubtitleScale(:final scale):
        final s = scale.clamp(PlaybackState.minSubtitleScale, PlaybackState.maxSubtitleScale);
        await _setProperty('sub-scale', s.toStringAsFixed(2));
        _update((st) => st.copyWith(subtitleScale: s));

      // Pistes audio
      case SetAudioTrack(:final id):
        await _selectAudio(id);

      // Boucle A-B
      case CycleAbLoop():
        await _cycleAbLoop(state);
      case ClearAbLoop():
        await _clearAbLoop();

      // Image
      case SetAspectMode(:final mode):
        // Appliqué par l'interface (ajustement du widget vidéo) : la texture
        // garde sa taille, et « Remplir » fonctionne réellement.
        _update((st) => st.copyWith(aspectMode: mode));
      case VideoZoomRelative(:final delta):
        final z = (state.videoZoom + delta)
            .clamp(PlaybackState.minVideoZoom, PlaybackState.maxVideoZoom);
        await _setProperty('video-zoom', z.toStringAsFixed(3));
        _update((st) => st.copyWith(videoZoom: z));
      case ResetVideoZoom():
        await _setProperty('video-zoom', '0');
        _update((st) => st.copyWith(videoZoom: 0));
      case RotateVideo(:final quarterTurns):
        final r = (state.videoRotation + quarterTurns) % 4;
        await _setProperty('video-rotate', '${r * 90}');
        _update((st) => st.copyWith(videoRotation: r));
      case SetVideoAdjust(:final adjust):
        final a = adjust.copyWith();
        await _applyAdjust(a);
        _update((st) => st.copyWith(videoAdjust: a));
      case ResetVideoAdjust():
        await _applyAdjust(VideoAdjust.neutral);
        _update((st) => st.copyWith(videoAdjust: VideoAdjust.neutral));

      // Égaliseur
      case SetEqualizerGains(:final gains):
        final g = Equalizer.normalise(gains);
        await _applyEqualizer(state.equalizerEnabled ? g : Equalizer.flat);
        _update((st) => st.copyWith(equalizerGains: g));
      case SetEqualizerPreset(:final preset):
        final g = Equalizer.presets[preset];
        if (g == null) return false;
        await _applyEqualizer(g);
        _update((st) => st.copyWith(equalizerGains: g, equalizerEnabled: true));
      case ToggleEqualizer():
        final enabled = !state.equalizerEnabled;
        await _applyEqualizer(enabled ? state.equalizerGains : Equalizer.flat);
        _update((st) => st.copyWith(equalizerEnabled: enabled));

      default:
        return false;
    }
    return true;
  }

  // --- Capture ----------------------------------------------------------------

  @override
  Future<Uint8List?> captureFrame() async {
    final state = _sink?.state;
    if (state == null || !state.hasVideo) return null;
    try {
      return await player.screenshot(format: 'image/png');
    } on Object {
      return null;
    }
  }

  // --- Transport --------------------------------------------------------------

  Future<void> _seekTo(Duration target) async {
    final duration = _sink?.state.duration ?? Duration.zero;
    var clamped = target.isNegative ? Duration.zero : target;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    // Retour visuel immédiat : la position est mise à jour avant que mpv confirme.
    _update((st) => st.copyWith(position: clamped));
    await player.seek(clamped);
    // Reprendre après un seek depuis la fin.
    if (_sink?.state.status == PlaybackStatus.ended) await player.play();
  }

  Future<void> _setVolume(double volume) async {
    final v = volume.clamp(PlaybackState.minVolume, PlaybackState.maxVolume);
    if (_sink?.state.muted ?? false) await _setMuted(false);
    await player.setVolume(v);
    _update((st) => st.copyWith(volume: v));
  }

  Future<void> _setMuted(bool muted) async {
    await _setProperty('mute', muted ? 'yes' : 'no');
    _update((st) => st.copyWith(muted: muted));
  }

  Future<void> _setSpeed(double speed) async {
    // Arrondi au pas de 0,25 puis bornage 0,25×–4×.
    final steps = (speed / PlaybackState.speedStep).round();
    final s = (steps * PlaybackState.speedStep)
        .clamp(PlaybackState.minSpeed, PlaybackState.maxSpeed);
    await player.setRate(s);
    // En lecture rapide, mpv peut sauter des images en retard dès le
    // décodage : le mouvement est moins fluide, mais l'image ne décroche pas.
    await _setProperty('framedrop', s >= 1.75 ? 'decoder+vo' : 'vo');
    _update((st) => st.copyWith(speed: s));
  }

  // --- Sous-titres et pistes --------------------------------------------------

  Future<void> _selectSubtitle(String? id) async {
    if (id == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      _update((st) => st.copyWith(clearSubtitleTrack: true));
      return;
    }
    final track = _tracks.subtitle.where((t) => t.id == id).firstOrNull;
    if (track != null) {
      await player.setSubtitleTrack(track);
    } else if (File(id).existsSync()) {
      // Identifiant qui est un chemin : sous-titre externe pas encore chargé.
      await player.setSubtitleTrack(SubtitleTrack.uri(id, title: p.basename(id)));
    } else {
      return;
    }
    await _setProperty('sub-visibility', 'yes');
    _update((st) => st.copyWith(subtitleTrackId: id, subtitlesVisible: true));
  }

  Future<void> _selectAudio(String? id) async {
    if (id == null) {
      await player.setAudioTrack(AudioTrack.auto());
      _update((st) => st.copyWith(clearAudioTrack: true));
      return;
    }
    final track = _tracks.audio.where((t) => t.id == id).firstOrNull;
    if (track == null) return;
    await player.setAudioTrack(track);
    _update((st) => st.copyWith(audioTrackId: id));
  }

  Future<void> _setSubtitleDelay(double seconds) async {
    final d = seconds.clamp(PlaybackState.minSubtitleDelay, PlaybackState.maxSubtitleDelay);
    await _setProperty('sub-delay', d.toStringAsFixed(2));
    _update((st) => st.copyWith(subtitleDelay: d));
  }

  // --- Boucle A-B -------------------------------------------------------------

  /// A absent → A = position ; B absent → B = position ; les deux → effacer.
  /// mpv boucle lui-même entre `ab-loop-a` et `ab-loop-b`, à l'image près.
  Future<void> _cycleAbLoop(PlaybackState state) async {
    // Position exacte du moteur : celle de l'état est filtrée (six par seconde).
    if (state.loopA == null) {
      final a = player.state.position;
      await _setProperty('ab-loop-a', _seconds(a));
      _update((st) => st.copyWith(loopA: a));
    } else if (state.loopB == null) {
      final b = player.state.position;
      if (b <= state.loopA! + const Duration(milliseconds: 500)) {
        // Un point B avant A (ou collé à A) ne ferait pas une boucle.
        return;
      }
      await _setProperty('ab-loop-b', _seconds(b));
      _update((st) => st.copyWith(loopB: b));
    } else {
      await _clearAbLoop();
    }
  }

  Future<void> _clearAbLoop() async {
    await _setProperty('ab-loop-a', 'no');
    await _setProperty('ab-loop-b', 'no');
    _update((st) => st.copyWith(clearLoop: true));
  }

  static String _seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);

  // --- Image ------------------------------------------------------------------

  /// Le ratio et le remplissage sont appliqués par l'interface. Côté mpv, on
  /// garde l'image telle quelle : changer le ratio y recréerait la texture
  /// (un éclair noir), et `panscan` n'a rien à rogner dans une texture qui a
  /// déjà le ratio de la vidéo.
  Future<void> _applyNeutralAspect() async {
    await _setProperty('video-aspect-override', AspectMode.auto.mpvAspect);
    await _setProperty('panscan', AspectMode.auto.mpvPanscan);
  }

  Future<void> _applyAdjust(VideoAdjust adjust) async {
    await _setProperty('brightness', adjust.brightness.round().toString());
    await _setProperty('contrast', adjust.contrast.round().toString());
    await _setProperty('saturation', adjust.saturation.round().toString());
  }

  // --- Égaliseur --------------------------------------------------------------

  /// Remplace la chaîne de filtres audio. Une chaîne vide retire tout filtre.
  Future<void> _applyEqualizer(List<double> gains) async {
    await _setProperty('af', Equalizer.filterFor(gains));
  }

  // --- Extraits ---------------------------------------------------------------

  /// Taille du cache arrière hors enregistrement, en octets : celle que
  /// media_kit applique déjà (`demuxer-max-back-bytes`).
  static const int _idleBackBufferBytes = 32 * 1024 * 1024;

  /// Taille du cache arrière pendant un extrait, en octets.
  ///
  /// C'est le cache arrière qui FOURNIT l'extrait (voir [dumpRecording]) : il
  /// doit garder, derrière la position de lecture, tout ce qui a défilé depuis
  /// le début de l'enregistrement. Coût mémoire : ces 256 Mio ne sont occupés
  /// que si l'extrait les remplit, soit environ quatre minutes de vidéo à
  /// 8 Mbit/s, ou plus d'une heure de musique à 320 kbit/s. Au-delà, mpv oublie
  /// le début de l'extrait : le fichier obtenu commence plus tard que demandé,
  /// mais il existe et se lit. La valeur est rendue par [releaseRecording].
  static const int _recordingBackBufferBytes = 256 * 1024 * 1024;

  /// Fenêtre d'observation de la lecture avant de commencer : le temps de
  /// laisser la position avancer assez pour qu'on puisse l'affirmer.
  static const Duration _playbackProofDelay = Duration(milliseconds: 350);

  /// Avancée minimale de la position pendant cette fenêtre. En dessous, rien
  /// ne défile vraiment (pause déguisée, fin de fichier, moteur bloqué).
  static const Duration _playbackProofProgress = Duration(milliseconds: 40);

  /// Longueur de la tranche recopiée par la répétition générale. Prise DANS LE
  /// PASSÉ, donc forcément déjà en cache : l'essai ne juge alors que
  /// l'écriture, jamais la disponibilité des paquets. Courte à dessein : le
  /// fichier d'essai est écrit puis relu tout de suite, et le moteur est figé
  /// pendant ce temps.
  static const Duration _rehearsalSpan = Duration(milliseconds: 250);

  /// Au-delà, on considère que le moteur ne répondra pas : une commande
  /// d'écriture qui ne rend jamais la main bloquerait l'interface.
  static const Duration _recordingCommandTimeout = Duration(seconds: 20);

  /// Position du média au début de l'extrait en cours. `null` : aucun extrait
  /// commencé.
  Duration? _recordingFrom;

  /// Position figée par [stopRecording] : la fin de l'extrait est là où
  /// l'utilisateur a arrêté, pas là où le service finit ses vérifications.
  Duration? _recordingTo;

  /// Vrai tant que le cache arrière est agrandi pour un extrait.
  bool _backBufferRaised = false;

  /// Commence un extrait dans [path].
  ///
  /// **Pourquoi `stream-record` ne peut pas écrire l'extrait d'un fichier
  /// local.** Sa documentation est explicite : « this will write only data that
  /// is appended at the end of the cache, and the already cached data cannot be
  /// written. You can try the `dump-cache` command as an alternative. » Dans le
  /// moteur (`demux/demux.c`), l'enregistreur n'est même créé qu'à l'arrivée
  /// d'un paquet neuf (`record_packet`, appelé depuis `add_packet_locked`). Or
  /// `cache-secs` vaut par défaut mille heures : avec `cache=yes`, mpv lit
  /// d'avance tout ce que `demuxer-max-bytes` autorise (32 Mio chez media_kit),
  /// c'est-à-dire un fichier de musique entier et une bonne demi-minute de
  /// vidéo. Quand l'utilisateur lance l'extrait, il n'y a plus un seul paquet
  /// neuf à recopier : aucun enregistreur n'est créé, **et le fichier n'est
  /// même pas ouvert**. Voyant allumé, dossier vide : exactement le défaut
  /// rapporté. Et lorsqu'il finit par recevoir des paquets (fichier plus gros
  /// que le cache), il écrit un extrait amputé de son début, ce qui est pire.
  ///
  /// OMNIA n'ouvre que des fichiers locaux : l'extrait est donc écrit par
  /// `dump-cache`, d'un seul tenant, à l'arrêt (voir [dumpRecording]), depuis
  /// le cache arrière agrandi ici pour la durée de l'extrait.
  ///
  /// **Le voyant ne s'allume pas sur une promesse.** Avant de répondre
  /// [RecordingFailure.none], on exige trois preuves :
  ///
  /// 1. le dossier de destination accepte réellement un fichier ([_folderAccepts]) ;
  /// 2. la position du moteur avance vraiment pendant la préparation ;
  /// 3. le moteur écrit tout de suite, au même endroit et avec la même
  ///    extension, un fichier d'essai non vide ([_rehearse]).
  @override
  Future<RecordingFailure> startRecording(String path) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return RecordingFailure.engineRefused;

    _recordingFrom = null;
    _recordingTo = null;

    final target = _mpvPath(path);
    if (!_folderAccepts(target)) return RecordingFailure.folderUnavailable;

    final mark = _mpvLogs.length;
    try {
      // Le cache arrière doit tenir tout l'extrait : c'est lui qui le fournira.
      // Posé en premier, avant même de mesurer la lecture, pour que rien de ce
      // qui défile pendant la préparation ne soit oublié.
      await platform.setProperty('demuxer-max-back-bytes', '$_recordingBackBufferBytes');
      _backBufferRaised = true;

      // Position exacte du moteur, et non celle de l'état, filtrée à six mises
      // à jour par seconde.
      final before = player.state.position;
      await Future<void>.delayed(_playbackProofDelay);
      if (player.state.position - before < _playbackProofProgress) {
        await releaseRecording();
        return RecordingFailure.notPlaying;
      }

      final rehearsal = await _rehearse(platform, target, mark);
      if (rehearsal != RecordingFailure.none) {
        await releaseRecording();
        return rehearsal;
      }

      _recordingFrom = before;
      return RecordingFailure.none;
    } on Object {
      await releaseRecording();
      return RecordingFailure.engineRefused;
    }
  }

  /// Le dossier de destination accepte-t-il un fichier ?
  ///
  /// Vérifié ici, en Dart, et non par le moteur : media_kit appelle
  /// `mpv_set_property_string` sans regarder son code de retour, et mpv ne
  /// signale l'échec d'ouverture d'un fichier de sortie que dans son journal.
  /// Un disque externe retiré ou un dossier en lecture seule est la panne la
  /// plus banale, et un essai d'écriture est la seule réponse fiable : les
  /// droits ne se devinent pas.
  static bool _folderAccepts(String target) {
    final probe = File(p.join(p.dirname(target), '.omnia-acces'));
    try {
      probe.writeAsBytesSync(const <int>[], flush: true);
    } on FileSystemException {
      return false;
    }
    try {
      probe.deleteSync();
    } on FileSystemException {
      // Témoin impossible à retirer : l'écriture, elle, a bien eu lieu.
    }
    return true;
  }

  /// Répétition générale : le moteur écrit tout de suite un fichier d'essai
  /// minuscule, à côté de l'extrait et avec la même extension, puis on le
  /// relit et on le supprime.
  ///
  /// C'est exactement le code que l'extrait empruntera (`mp_recorder_create`,
  /// dans `common/recorder.c`) : deviner le conteneur d'après l'extension
  /// (« Output format not found. »), ouvrir le fichier (« Failed opening output
  /// file. »), décrire chaque piste choisie (« Can't mux one of the input
  /// streams. »), écrire l'en-tête (« Writing header failed. »). Les quatre
  /// échecs possibles y sont, tous avant le premier paquet, et l'en-tête est
  /// écrit dès la création de l'enregistreur.
  ///
  /// La preuve ne dépend donc pas du contenu : même si la tranche demandée ne
  /// donnait aucun paquet, un conteneur bien ouvert laisse un fichier non vide
  /// (en-tête et fin de conteneur). Un fichier vide, ou absent, veut dire que
  /// l'extrait aurait échoué — et le journal du moteur dit lequel des quatre.
  ///
  /// La tranche demandée est prise dans le passé immédiat : elle est déjà lue,
  /// donc déjà en cache, et l'essai ne dépend de rien d'autre que de
  /// l'écriture.
  Future<RecordingFailure> _rehearse(NativePlayer platform, String target, int mark) async {
    final probe = _rehearsalPathFor(target);
    final file = File(probe);
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      return RecordingFailure.folderUnavailable;
    }

    final to = player.state.position;
    final from = to - _rehearsalSpan;
    try {
      await platform
          .command([
            'dump-cache',
            _seconds(from.isNegative ? Duration.zero : from),
            _seconds(to),
            probe,
          ])
          .timeout(_recordingCommandTimeout);
    } on Object {
      return RecordingFailure.engineRefused;
    }

    final written = file.existsSync() ? file.lengthSync() : 0;
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Fichier d'essai impossible à retirer : sans conséquence pour l'extrait.
    }
    if (written > 0) return RecordingFailure.none;
    return _refusalInLogs(mark, fallback: RecordingFailure.engineRefused);
  }

  /// Traduit en raison d'échec ce que mpv a écrit dans son journal depuis
  /// [mark]. Retourne [fallback] quand il n'a rien dit de reconnaissable.
  RecordingFailure _refusalInLogs(int mark, {RecordingFailure fallback = RecordingFailure.none}) {
    // Messages de `common/recorder.c` et `player/command.c`, en anglais dans le
    // moteur : on ne les traduit pas, on les reconnaît.
    const folder = ['Failed opening output file'];
    const container = [
      'Output format not found',
      "Can't mux one of the input streams",
      "Can't mux one of the attachments",
      'Writing header failed',
      'No streams.',
    ];
    const engine = ['Cache dumping stopped due to error', 'No demuxer open'];
    for (var i = mark; i < _mpvLogs.length; i++) {
      final line = _mpvLogs[i];
      if (folder.any(line.contains)) return RecordingFailure.folderUnavailable;
      if (container.any(line.contains)) return RecordingFailure.containerRefused;
      if (engine.any(line.contains)) return RecordingFailure.engineRefused;
    }
    return fallback;
  }

  /// Fige la fin de l'extrait.
  ///
  /// Rien n'est en cours d'écriture à cet instant : le fichier est écrit d'un
  /// seul tenant par [dumpRecording]. Le service peut donc regarder le fichier
  /// dès le retour, sans laisser de délai au moteur.
  @override
  Future<void> stopRecording() async {
    if (_recordingFrom == null) return;
    _recordingTo = player.state.position;
  }

  /// Écrit l'extrait : `dump-cache` recopie dans [path] les paquets que le
  /// démultiplexeur garde en mémoire entre le début et la fin de
  /// l'enregistrement.
  ///
  /// La commande écrase le fichier, et — c'est le point important — elle ne
  /// rend la main qu'une fois le fichier fermé : dans le moteur, `dump_cache`
  /// s'exécute en entier sous le verrou du démultiplexeur, et la commande n'est
  /// signalée terminée qu'après l'écriture de la fin du conteneur. À son
  /// retour, le fichier est donc complet sur le disque.
  ///
  /// On relit quand même le résultat : mpv ne signale ses refus que dans son
  /// journal, et media_kit ne remonte pas le code de retour d'une commande.
  @override
  Future<bool> dumpRecording(String path) async {
    final platform = player.platform;
    final from = _recordingFrom;
    if (platform is! NativePlayer || from == null) return false;
    final to = _recordingTo ?? player.state.position;
    // Rien ne s'est écoulé : il n'y a aucune séquence à écrire.
    if (to <= from) return false;
    final target = _mpvPath(path);
    try {
      await platform
          .command(['dump-cache', _seconds(from), _seconds(to), target])
          .timeout(_recordingCommandTimeout);
    } on Object {
      return false;
    }
    final file = File(target);
    return file.existsSync() && file.lengthSync() > 0;
  }

  @override
  Future<void> releaseRecording() async {
    _recordingFrom = null;
    _recordingTo = null;
    if (!_backBufferRaised) return;
    _backBufferRaised = false;
    await _setProperty('demuxer-max-back-bytes', '$_idleBackBufferBytes');
  }

  @override
  Future<String> recordingDiagnostics() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return 'Moteur mpv absent : rien à rapporter.';

    Future<String> read(String name) async {
      try {
        final value = (await platform.getProperty(name)).trim();
        return value.isEmpty ? '(vide)' : value;
      } on Object {
        return '(illisible)';
      }
    }

    return [
      'mpv ${await read('mpv-version')} ; fichier ${await read('path')}',
      'stream-record = ${await read('stream-record')}'
          ' (OMNIA ne s’en sert pas : voir startRecording)',
      'cache = ${await read('cache')}'
          ' ; cache-on-disk = ${await read('cache-on-disk')}'
          ' ; demuxer-seekable-cache = ${await read('demuxer-seekable-cache')}'
          ' ; cache-secs = ${await read('cache-secs')}',
      'demuxer-max-bytes = ${await read('demuxer-max-bytes')}'
          ' ; demuxer-max-back-bytes = ${await read('demuxer-max-back-bytes')}'
          ' ; demuxer-donate-buffer = ${await read('demuxer-donate-buffer')}',
      'demuxer-cache-time = ${await read('demuxer-cache-time')}'
          ' ; demuxer-cache-duration = ${await read('demuxer-cache-duration')}'
          ' ; demuxer-cache-idle = ${await read('demuxer-cache-idle')}'
          ' ; demuxer-via-network = ${await read('demuxer-via-network')}',
      'demuxer-cache-state = ${await read('demuxer-cache-state')}',
      'time-pos = ${await read('time-pos')}'
          ' ; pause = ${await read('pause')}'
          ' ; core-idle = ${await read('core-idle')}'
          ' ; eof-reached = ${await read('eof-reached')}'
          ' ; speed = ${await read('speed')}',
      'file-format = ${await read('file-format')}'
          ' ; audio-codec-name = ${await read('audio-codec-name')}'
          ' ; video-codec = ${await read('video-codec')}'
          ' ; aid = ${await read('aid')} ; vid = ${await read('vid')}'
          ' ; ao = ${await read('current-ao')}',
      'extrait : de ${_recordingFrom ?? '(aucun)'} à ${_recordingTo ?? '(en cours)'}'
          ' ; cache arrière agrandi : ${_backBufferRaised ? 'oui' : 'non'}',
      if (_mpvLogs.isEmpty)
        'journal de mpv : aucune ligne (niveau de journal trop élevé ?)'
      else
        'journal de mpv (${_mpvLogs.length} dernières lignes) :',
      for (final line in _mpvLogs) '  $line',
    ].join('\n');
  }

  /// Chemin tel que mpv l'attend.
  ///
  /// Deux couches le regardent. mpv d'abord : `dump-cache` passe son troisième
  /// argument par `mp_get_user_path()`, qui développe un `~/` ou un `~~/` en
  /// TÊTE de chaîne — un chemin absolu n'en commence jamais. libavformat
  /// ensuite, qui devine un protocole au préfixe « xxx: » du nom ; il reconnaît
  /// une lettre de lecteur Windows (`C:\…`) comme un chemin, mais un chemin
  /// relatif dont le premier élément contient deux-points le tromperait. On ne
  /// lui donne donc que des chemins absolus et normalisés. Les espaces, les
  /// parenthèses et les antislashs, eux, ne demandent aucune protection : la
  /// valeur voyage comme un argument de commande, pas comme une ligne de shell.
  static String _mpvPath(String path) => p.normalize(p.absolute(path));

  /// Nom du fichier de la répétition générale : un point en tête pour qu'il ne
  /// ressemble jamais à un extrait, et l'extension de l'extrait conservée en
  /// dernier, car c'est elle qui décide du conteneur chez libavformat.
  static String _rehearsalPathFor(String target) =>
      p.join(p.dirname(target), '.omnia-essai${p.extension(target)}');

  @override
  Future<void> close() async {
    _opening = false;
    // Un extrait en cours ne doit pas continuer sur le fichier suivant. Le
    // service, lui, a déjà écrit son fichier : ici on ne fait qu'oublier
    // l'extrait et rendre au moteur ses réglages d'avant.
    await releaseRecording();
    await player.stop();
    _tracks = const Tracks();
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        videoWidth: 0,
        videoHeight: 0,
        subtitleTracks: const [],
        audioTracks: const [],
        clearSubtitleTrack: true,
        clearAudioTrack: true,
        clearLoop: true,
        clearError: true,
      ),
    );
    _sink = null;
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await player.dispose();
  }
}
