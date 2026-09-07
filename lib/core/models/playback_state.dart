import 'document_layout.dart';
import 'end_of_playback_mode.dart';
import 'media_file.dart';
import 'media_type.dart';
import 'playback_status.dart';

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

  /// Bornes de zoom des documents.
  static const double minZoom = 0.25;
  static const double maxZoom = 6.0;

  /// Rotation du document, en quarts de tour (0–3).
  final int rotation;

  /// Mode sombre de lecture (inversion douce des couleurs du document).
  final bool readingDark;

  /// Défilement continu ou page par page.
  final DocumentLayout documentLayout;

  /// Position de défilement d'un texte, 0–1 (les PDF utilisent [currentPage]).
  final double scrollFraction;

  /// Comportement en fin de fichier.
  final EndOfPlaybackMode endMode;

  /// État de la fenêtre.
  final bool fullscreen;
  final bool alwaysOnTop;

  /// Playlist courante (chemins) et index du fichier courant dans celle-ci.
  /// Remplie par le scan de dossier (Phase 2).
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
    return PlaybackState(
      file: fileJson is Map<String, Object?>
          ? MediaFile.fromJson(fileJson)
          : null,
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
      endMode: EndOfPlaybackMode.fromJson(json['endMode']),
      fullscreen: json['fullscreen'] as bool? ?? false,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? false,
      playlist: (json['playlist'] as List?)?.cast<String>() ?? const [],
      playlistIndex: (json['playlistIndex'] as num?)?.toInt() ?? -1,
      error: errorJson is Map<String, Object?>
          ? PlaybackError.fromJson(errorJson)
          : null,
    );
  }

  @override
  String toString() =>
      'PlaybackState(${file?.name ?? '—'}, ${status.name}, $position/$duration)';
}
