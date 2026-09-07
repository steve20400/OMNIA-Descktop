import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/controllers/media_router.dart';
import '../core/providers.dart';

/// Dialogues natifs d'ouverture. Le chemin choisi part sur le bus : l'UI ne
/// touche jamais un contrôleur.

Future<void> pickAndOpenFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: MediaRouter.allExtensions.toList()..sort(),
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  final path = file?.path;
  if (path != null) ref.dispatch(OpenFile(path));
}

Future<void> pickAndOpenFolder(WidgetRef ref) async {
  final dir = await FilePicker.getDirectoryPath(
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  if (dir != null) ref.dispatch(OpenFolder(dir));
}
