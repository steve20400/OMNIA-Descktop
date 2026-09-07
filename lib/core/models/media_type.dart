/// Type de média reconnu par OMNIA.
///
/// Le [MediaRouter] déduit ce type de l'extension du fichier et choisit le
/// contrôleur adapté. `unknown` signifie « non pris en charge ».
enum MediaType {
  video,
  audio,
  pdf,
  text,
  unknown;

  /// Vrai pour les médias lus par le moteur audio/vidéo (mpv).
  bool get isAv => this == video || this == audio;

  /// Vrai pour les documents en lecture seule (PDF, texte).
  bool get isDocument => this == pdf || this == text;

  /// Vrai si OMNIA sait ouvrir ce type.
  bool get isSupported => this != unknown;

  /// Désérialisation tolérante : une valeur inconnue devient [unknown].
  static MediaType fromJson(Object? value) => values.firstWhere(
        (e) => e.name == value,
        orElse: () => MediaType.unknown,
      );
}
