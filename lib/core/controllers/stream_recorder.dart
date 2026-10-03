import '../models/recording_failure.dart';

/// Contrôleur capable d'enregistrer le flux qu'il lit : un extrait vidéo ou
/// audio, recopié tel quel, sans réencodage ni perte de qualité.
///
/// Comme [FrameCapturer], ce n'est pas un sous-type de `MediaController` :
/// seuls les contrôleurs qui savent le faire l'implémentent, et le service de
/// lecture le vérifie avant de s'en servir.
///
/// Le déroulé complet d'un extrait, vu par le service :
/// [startRecording] → (lecture) → [stopRecording] → éventuellement
/// [dumpRecording] → [releaseRecording], toujours, même après un échec.
abstract interface class StreamRecorder {
  /// Commence à recopier le flux lu dans [path]. Le format suit l'extension
  /// (Matroska : `.mkv`, `.mka`).
  ///
  /// Retourne [RecordingFailure.none] seulement si le moteur a *prouvé* qu'il
  /// sait écrire ce fichier-là : pas de voyant d'enregistrement devant un
  /// moteur qui n'écrira rien. Toute autre valeur dit pourquoi l'extrait n'a
  /// pas commencé, et rien n'est en cours.
  ///
  /// L'appel prend un instant — quelques centaines de millisecondes : c'est le
  /// prix de la preuve, et le voyant ne s'allume qu'après.
  ///
  /// L'enregistrement suit la lecture : il avance au rythme du média, et une
  /// pause le suspend. Un saut dans le média laisse un trou dans l'extrait.
  Future<RecordingFailure> startRecording(String path);

  /// Arrête l'enregistrement en cours et fige la fin de l'extrait.
  ///
  /// Contrat : au retour, plus rien n'est en cours d'écriture. Ce que le moteur
  /// avait déjà écrit dans le fichier est complet ; le service peut le regarder
  /// sans laisser de délai supplémentaire. Ne rend pas encore au moteur ses
  /// réglages d'avant l'extrait : [dumpRecording] en a besoin.
  Future<void> stopRecording();

  /// Écrit dans [path] ce que le moteur a gardé en mémoire entre le début et
  /// la fin de l'extrait. Appelé par le service quand [stopRecording] n'a rien
  /// laissé d'exploitable — ce qui, pour un fichier local, est le cas normal.
  ///
  /// L'écriture au fil de l'eau du moteur ne recopie que les paquets
  /// *nouvellement* lus par le démultiplexeur. Un fichier local est lu
  /// d'avance : quand l'utilisateur lance l'extrait, la suite est déjà en
  /// cache, et il ne reste aucun paquet neuf à recopier. Le cache, lui,
  /// contient la séquence : c'est donc ce chemin-ci qui écrit l'extrait, et non
  /// l'exception.
  ///
  /// Retourne `true` seulement si un fichier non vide existe à l'arrivée.
  Future<bool> dumpRecording(String path);

  /// Rend au moteur ses réglages d'avant l'extrait (taille du cache arrière),
  /// et oublie l'extrait courant. Appelé par le service quand il en a fini
  /// avec le fichier, que l'extrait ait réussi ou non.
  Future<void> releaseRecording();

  /// Ce que le moteur rapporte de l'enregistrement, en clair et en plusieurs
  /// lignes : propriété d'enregistrement relue, état du cache, position, et
  /// les dernières lignes du journal du moteur.
  ///
  /// Sert aux journaux et surtout au test d'intégration : un échec en CI doit
  /// dire *pourquoi*, sans machine locale pour rejouer la scène.
  Future<String> recordingDiagnostics();
}
