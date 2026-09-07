import 'dart:io';

import '../commands/player_command.dart';

/// Traduit les arguments de la ligne de commande en commande d'ouverture.
///
/// `omnia /chemin/fichier.mkv` (« Ouvrir avec » du système) ouvre le fichier ;
/// un dossier déclenche le scan et la lecture de son premier élément. Les
/// options (`--quelque-chose`) sont ignorées. Retourne `null` s'il n'y a rien
/// à ouvrir.
///
/// Utilisé au démarrage et quand une seconde instance transmet ses arguments.
PlayerCommand? commandForLaunchArguments(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('-') || arg.trim().isEmpty) continue;
    switch (FileSystemEntity.typeSync(arg)) {
      case FileSystemEntityType.directory:
        return OpenFolder(arg);
      case FileSystemEntityType.file:
        return OpenFile(arg);
      default:
        // Chemin introuvable : on tente quand même l'ouverture, pour que
        // l'utilisateur voie un message clair plutôt que rien.
        return OpenFile(arg);
    }
  }
  return null;
}
