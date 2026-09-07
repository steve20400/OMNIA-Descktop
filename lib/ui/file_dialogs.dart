import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/controllers/media_router.dart';
import '../core/providers.dart';

/// Dialogues natifs d'ouverture. Le chemin choisi part sur le bus : l'UI ne
/// touche jamais un contrôleur.

/// Extensions proposées par le dialogue d'ouverture.
///
/// Chaque extension est listée en minuscules ET en majuscules : sous Linux, le
/// filtre du portail XDG est un motif glob sensible à la casse, et un fichier
/// `Episode.MKV` — courant sur des médias venus de Windows — resterait
/// invisible dans le sélecteur.
List<String> mediaPickerExtensions() {
  final extensions = <String>{};
  for (final ext in MediaRouter.allExtensions) {
    extensions.add(ext);
    extensions.add(ext.toUpperCase());
  }
  return extensions.toList()..sort();
}

/// Le bus est lu AVANT l'ouverture du dialogue : celui-ci est modal et peut
/// durer, et le widget appelant peut avoir disparu entre-temps. Utiliser `ref`
/// après l'attente lèverait alors une erreur dans une future non surveillée.
Future<void> pickAndOpenFile(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: mediaPickerExtensions(),
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  final path = file?.path;
  if (path != null) bus.dispatch(OpenFile(path));
}

Future<void> pickAndOpenFolder(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final dir = await FilePicker.getDirectoryPath(
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  if (dir != null) bus.dispatch(OpenFolder(dir));
}
