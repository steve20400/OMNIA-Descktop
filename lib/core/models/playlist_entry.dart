import 'media_file.dart';

/// Un élément du panneau de dossier.
///
/// Les métadonnées coûteuses ([duration], [pageCount]) ne sont pas sondées au
/// scan : elles proviennent de l'historique quand le fichier a déjà été ouvert.
/// Sonder 2000 fichiers au moment du scan gèlerait l'ouverture ; on préfère
/// n'afficher une durée que lorsqu'elle est connue sans coût.
class PlaylistEntry {
  const PlaylistEntry({
    required this.file,
    this.duration,
    this.pageCount,
    this.resumePosition,
    this.completed = false,
  });

  final MediaFile file;

  /// Durée connue (média déjà ouvert au moins une fois).
  final Duration? duration;

  /// Nombre de pages connu (document déjà ouvert).
  final int? pageCount;

  /// Position mémorisée, si la lecture a été interrompue en cours de route.
  final Duration? resumePosition;

  /// Le fichier a été lu jusqu'au bout.
  final bool completed;

  String get path => file.path;

  /// Vrai si le panneau doit afficher un repère « déjà lu / position mémorisée ».
  bool get hasProgressBadge => completed || resumePosition != null;

  /// Progression connue, 0–1, pour la pastille du panneau.
  double? get progress {
    if (completed) return 1;
    final d = duration;
    final r = resumePosition;
    if (d == null || r == null || d.inMilliseconds <= 0) return null;
    return (r.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  PlaylistEntry copyWith({
    Duration? duration,
    int? pageCount,
    Duration? resumePosition,
    bool clearResumePosition = false,
    bool? completed,
  }) {
    return PlaylistEntry(
      file: file,
      duration: duration ?? this.duration,
      pageCount: pageCount ?? this.pageCount,
      resumePosition:
          clearResumePosition ? null : (resumePosition ?? this.resumePosition),
      completed: completed ?? this.completed,
    );
  }

  Map<String, Object?> toJson() => {
        'file': file.toJson(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (pageCount != null) 'pageCount': pageCount,
        if (resumePosition != null) 'resumeMs': resumePosition!.inMilliseconds,
        'completed': completed,
      };

  factory PlaylistEntry.fromJson(Map<String, Object?> json) => PlaylistEntry(
        file: MediaFile.fromJson(json['file']! as Map<String, Object?>),
        duration: json['durationMs'] is num
            ? Duration(milliseconds: (json['durationMs']! as num).toInt())
            : null,
        pageCount: (json['pageCount'] as num?)?.toInt(),
        resumePosition: json['resumeMs'] is num
            ? Duration(milliseconds: (json['resumeMs']! as num).toInt())
            : null,
        completed: json['completed'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) => other is PlaylistEntry && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'PlaylistEntry(${file.name})';
}
