/// Contrôleur capable d'enregistrer le flux qu'il lit : un extrait vidéo ou
/// audio, recopié tel quel, sans réencodage ni perte de qualité.
///
/// Comme [FrameCapturer], ce n'est pas un sous-type de `MediaController` :
/// seuls les contrôleurs qui savent le faire l'implémentent, et le service de
/// lecture le vérifie avant de s'en servir.
abstract interface class StreamRecorder {
  /// Commence à recopier le flux lu dans [path]. Le format suit l'extension
  /// (Matroska : `.mkv`, `.mka`). Retourne `false` si le moteur refuse.
  ///
  /// L'enregistrement suit la lecture : il avance au rythme du média, et une
  /// pause le suspend. Un saut dans le média laisse un trou dans l'extrait.
  Future<bool> startRecording(String path);

  /// Arrête l'enregistrement en cours et finalise le fichier.
  Future<void> stopRecording();
}
