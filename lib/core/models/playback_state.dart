import 'document_layout.dart';
import 'end_of_playback_mode.dart';
import 'equalizer.dart';
import 'media_file.dart';
import 'media_type.dart';
import 'playback_status.dart';
import 'track_info.dart';
import 'video_adjust.dart';

/// État de lecture centralisé d'OMNIA.
///
/// Un seul objet, immuable, observable et sérialisable en JSON : c'est ce que
/// l'interface affiche aujourd'hui et ce que la télécommande mobile recevra
/// demain. Les contrôleurs de média le mettent à jour via [PlaybackStateSink].
class PlaybackState {
  const PlaybackState({
    this.file,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffering = false,
    this.hasVideo = false,
    this.volume = 100,
    this.muted = false,
    this.speed = 1.0,
    this.currentPage = 0,
    this.totalPages = 0,
    this.zoom = 1.0,
    this.rotation = 0,
    this.readingDark = false,
    this.documentLayout = DocumentLayout.continuous,
    this.scrollFraction = 0,
    this.subtitleTracks = const [],
    this.audioTracks = const [],
    this.subtitleTrackId,
    this.audioTrackId,
    this.subtitlesVisible = true,
    this.subtitleDelay = 0,
    this.subtitleScale = 1.0,
    this.loopA,
    this.loopB,
    this.aspectMode = AspectMode.auto,
    this.videoZoom = 0,
    this.videoRotation = 0,
    this.videoAdjust = VideoAdjust.neutral,
    this.equalizerGains = Equalizer.flat,
    this.equalizerEnabled = false,
    this.lastScreenshot,
    this.miniPlayer = false,
    this.endMode = EndOfPlaybackMode.next,
    this.fullscreen = false,
    this.alwaysOnTop = false,
    this.playlist = const [],
    this.playlistIndex = -1,
    this.error,
  });

  /// Bornes de volume (échelle mpv : 0–100).
  static const double minVolume = 0;
  static const double maxVolume = 100;

  /// Bornes et pas de vitesse.
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;
  static const double speedStep = 0.25;

  /// Bornes de zoom des documents.
  static const double minZoom = 0.25;
  static const double maxZoom = 6.0;

  /// Bornes du décalage des sous-titres (secondes) et de leur taille.
  static const double minSubtitleDelay = -30;
  static const double maxSubtitleDelay = 30;
  static const double subtitleDelayStep = 0.5;
  static const double minSubtitleScale = 0.5;
  static const double maxSubtitleScale = 2.5;

  /// Bornes du zoom vidéo (échelle mpv `video-zoom`, logarithmique : 0 = 1×).
  static const double minVideoZoom = -1.0;
  static const double maxVideoZoom = 2.0;

  /// Fichier courant, `null` si rien n'est ouvert.
  final MediaFile? file;

  final PlaybackStatus status;

  /// Position et durée (médias).
  final Duration position;
  final Duration duration;

  /// Mise en mémoire tampon en cours.
  final bool buffering;

  /// Vrai si le fichier courant possède une piste vidéo.
  final bool hasVideo;

  /// Volume 0–100 et sourdine.
  final double volume;
  final bool muted;

  /// Vitesse de lecture (1.0 = normale).
  final double speed;

  /// Page courante (1-based) et nombre de pages (documents).
  final int currentPage;
  final int totalPages;

  /// Facteur de zoom (documents : 1.0 = page ajustée à la largeur ; texte :
  /// échelle de police).
  final double zoom;

  /// Rotation du document, en quarts de tour (0–3).
  final int rotation;

  /// Mode sombre de lecture (inversion douce des couleurs du document).
  final bool readingDark;

  /// Défilement continu ou page par page.
  final DocumentLayout documentLayout;

  /// Position de défilement d'un texte, 0–1 (les PDF utilisent [currentPage]).
  final double scrollFraction;

  /// Pistes de sous-titres et audio du fichier courant (intégrées et externes).
  final List<TrackInfo> subtitleTracks;
  final List<TrackInfo> audioTracks;

  /// Piste sélectionnée, `null` pour « aucune » (sous-titres) ou « auto ».
  final String? subtitleTrackId;
  final String? audioTrackId;

  /// Sous-titres affichés (indépendant de la piste choisie : `V` bascule).
  final bool subtitlesVisible;

  /// Décalage des sous-titres en secondes (positif = plus tard).
  final double subtitleDelay;

  /// Taille des sous-titres (1.0 = taille par défaut).
  final double subtitleScale;

  /// Boucle A-B : bornes posées. Active quand les deux sont définies.
  final Duration? loopA;
  final Duration? loopB;

  /// Image : ratio, zoom (échelle mpv), rotation (quarts de tour), réglages.
  final AspectMode aspectMode;
  final double videoZoom;
  final int videoRotation;
  final VideoAdjust videoAdjust;

  /// Égaliseur : gains par bande (dB) et activation.
  final List<double> equalizerGains;
  final bool equalizerEnabled;

  /// Chemin de la dernière capture d'écran enregistrée.
  final String? lastScreenshot;

  /// Mode mini-lecteur (fenêtre compacte au premier plan).
  final bool miniPlayer;

  /// Comportement en fin de fichier.
  final EndOfPlaybackMode endMode;

  /// État de la fenêtre.
  final bool fullscreen;
  final bool alwaysOnTop;

  /// Playlist courante (chemins) et index du fichier courant dans celle-ci.
  final List<String> playlist;
  final int playlistIndex;

  /// Erreur courante, si [status] vaut [PlaybackStatus.error].
  final PlaybackError? error;

  /// Type du média courant.
  MediaType get mediaType => file?.type ?? MediaType.unknown;

  bool get hasFile => file != null;
  bool get isPlaying => status == PlaybackStatus.playing;

  /// Un document (PDF ou texte) est affiché.
  bool get isDocument => mediaType.isDocument;

  /// Boucle A-B complète et active.
  bool get abLoopActive => loopA != null && loopB != null;

  /// Nom du préréglage d'égaliseur correspondant aux gains, ou `null`.
  String? get equalizerPreset => Equalizer.presetFor(equalizerGains);

  /// Progression 0–1, sûre même sans durée connue.
  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Duration get remaining {
    final r = duration - position;
    return r.isNegative ? Duration.zero : r;
  }

  PlaybackState copyWith({
    MediaFile? file,
    bool clearFile = false,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    bool? buffering,
    bool? hasVideo,
    double? volume,
    bool? muted,
    double? speed,
    int? currentPage,
    int? totalPages,
    double? zoom,
    int? rotation,
    bool? readingDark,
    DocumentLayout? documentLayout,
    double? scrollFraction,
    List<TrackInfo>? subtitleTracks,
    List<TrackInfo>? audioTracks,
    String? subtitleTrackId,
    bool clearSubtitleTrack = false,
    String? audioTrackId,
    bool clearAudioTrack = false,
    bool? subtitlesVisible,
    double? subtitleDelay,
    double? subtitleScale,
    Duration? loopA,
    Duration? loopB,
    bool clearLoop = false,
    AspectMode? aspectMode,
    double? videoZoom,
    int? videoRotation,
    VideoAdjust? videoAdjust,
    List<double>? equalizerGains,
    bool? equalizerEnabled,
    String? lastScreenshot,
    bool? miniPlayer,
    EndOfPlaybackMode? endMode,
    bool? fullscreen,
    bool? alwaysOnTop,
    List<String>? playlist,
    int? playlistIndex,
    PlaybackError? error,
    bool clearError = false,
  }) {
    return PlaybackState(
      file: clearFile ? null : (file ?? this.file),
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffering: buffering ?? this.buffering,
      hasVideo: hasVideo ?? this.hasVideo,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      speed: speed ?? this.speed,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      zoom: zoom ?? this.zoom,
      rotation: rotation ?? this.rotation,
      readingDark: readingDark ?? this.readingDark,
      documentLayout: documentLayout ?? this.documentLayout,
      scrollFraction: scrollFraction ?? this.scrollFraction,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTrackId: clearSubtitleTrack ? null : (subtitleTrackId ?? this.subtitleTrackId),
      audioTrackId: clearAudioTrack ? null : (audioTrackId ?? this.audioTrackId),
      subtitlesVisible: subtitlesVisible ?? this.subtitlesVisible,
      subtitleDelay: subtitleDelay ?? this.subtitleDelay,
      subtitleScale: subtitleScale ?? this.subtitleScale,
      loopA: clearLoop ? null : (loopA ?? this.loopA),
      loopB: clearLoop ? null : (loopB ?? this.loopB),
      aspectMode: aspectMode ?? this.aspectMode,
      videoZoom: videoZoom ?? this.videoZoom,
      videoRotation: videoRotation ?? this.videoRotation,
      videoAdjust: videoAdjust ?? this.videoAdjust,
      equalizerGains: equalizerGains ?? this.equalizerGains,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      lastScreenshot: lastScreenshot ?? this.lastScreenshot,
      miniPlayer: miniPlayer ?? this.miniPlayer,
      endMode: endMode ?? this.endMode,
      fullscreen: fullscreen ?? this.fullscreen,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      playlist: playlist ?? this.playlist,
      playlistIndex: playlistIndex ?? this.playlistIndex,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, Object?> toJson() => {
        'file': file?.toJson(),
        'status': status.name,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'buffering': buffering,
        'hasVideo': hasVideo,
        'volume': volume,
        'muted': muted,
        'speed': speed,
        'currentPage': currentPage,
        'totalPages': totalPages,
        'zoom': zoom,
        'rotation': rotation,
        'readingDark': readingDark,
        'documentLayout': documentLayout.name,
        'scrollFraction': scrollFraction,
        'subtitleTracks': subtitleTracks.map((t) => t.toJson()).toList(),
        'audioTracks': audioTracks.map((t) => t.toJson()).toList(),
        'subtitleTrackId': subtitleTrackId,
        'audioTrackId': audioTrackId,
        'subtitlesVisible': subtitlesVisible,
        'subtitleDelay': subtitleDelay,
        'subtitleScale': subtitleScale,
        'loopAMs': loopA?.inMilliseconds,
        'loopBMs': loopB?.inMilliseconds,
        'aspectMode': aspectMode.name,
        'videoZoom': videoZoom,
        'videoRotation': videoRotation,
        'videoAdjust': videoAdjust.toJson(),
        'equalizerGains': equalizerGains,
        'equalizerEnabled': equalizerEnabled,
        'lastScreenshot': lastScreenshot,
        'miniPlayer': miniPlayer,
        'endMode': endMode.name,
        'fullscreen': fullscreen,
        'alwaysOnTop': alwaysOnTop,
        'playlist': playlist,
        'playlistIndex': playlistIndex,
        'error': error?.toJson(),
      };

  factory PlaybackState.fromJson(Map<String, Object?> json) {
    final fileJson = json['file'];
    final errorJson = json['error'];
    final adjustJson = json['videoAdjust'];
    List<TrackInfo> tracks(Object? raw) => (raw as List? ?? const [])
        .whereType<Map>()
        .map((m) => TrackInfo.fromJson(Map<String, Object?>.from(m)))
        .toList();
    Duration? ms(Object? raw) => raw is num ? Duration(milliseconds: raw.toInt()) : null;

    return PlaybackState(
      file: fileJson is Map<String, Object?> ? MediaFile.fromJson(fileJson) : null,
      status: PlaybackStatus.fromJson(json['status']),
      position: Duration(milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
      buffering: json['buffering'] as bool? ?? false,
      hasVideo: json['hasVideo'] as bool? ?? false,
      volume: (json['volume'] as num?)?.toDouble() ?? 100,
      muted: json['muted'] as bool? ?? false,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.0,
      rotation: ((json['rotation'] as num?)?.toInt() ?? 0) % 4,
      readingDark: json['readingDark'] as bool? ?? false,
      documentLayout: DocumentLayout.fromJson(json['documentLayout']),
      scrollFraction: ((json['scrollFraction'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
      subtitleTracks: tracks(json['subtitleTracks']),
      audioTracks: tracks(json['audioTracks']),
      subtitleTrackId: json['subtitleTrackId'] as String?,
      audioTrackId: json['audioTrackId'] as String?,
      subtitlesVisible: json['subtitlesVisible'] as bool? ?? true,
      subtitleDelay: (json['subtitleDelay'] as num?)?.toDouble() ?? 0,
      subtitleScale: (json['subtitleScale'] as num?)?.toDouble() ?? 1.0,
      loopA: ms(json['loopAMs']),
      loopB: ms(json['loopBMs']),
      aspectMode: AspectMode.fromJson(json['aspectMode']),
      videoZoom: (json['videoZoom'] as num?)?.toDouble() ?? 0,
      videoRotation: ((json['videoRotation'] as num?)?.toInt() ?? 0) % 4,
      videoAdjust: adjustJson is Map
          ? VideoAdjust.fromJson(Map<String, Object?>.from(adjustJson))
          : VideoAdjust.neutral,
      equalizerGains: Equalizer.normalise(
        (json['equalizerGains'] as List? ?? const []).whereType<num>().map((n) => n.toDouble()).toList(),
      ),
      equalizerEnabled: json['equalizerEnabled'] as bool? ?? false,
      lastScreenshot: json['lastScreenshot'] as String?,
      miniPlayer: json['miniPlayer'] as bool? ?? false,
      endMode: EndOfPlaybackMode.fromJson(json['endMode']),
      fullscreen: json['fullscreen'] as bool? ?? false,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
      playlist: (json['playlist'] as List?)?.cast<String>() ?? const [],
      playlistIndex: (json['playlistIndex'] as num?)?.toInt() ?? -1,
      error: errorJson is Map<String, Object?> ? PlaybackError.fromJson(errorJson) : null,
    );
  }

  @override
  String toString() =>
      'PlaybackState(${file?.name ?? '—'}, ${status.name}, $position/$duration)';
}
