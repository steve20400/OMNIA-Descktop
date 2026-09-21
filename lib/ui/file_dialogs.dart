import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/commands/player_command.dart';
import '../core/controllers/media_router.dart';
import '../core/providers.dart';

/// Dialogues natifs d'ouverture. Le chemin choisi part sur le bus : l'UI ne
/// touche jamais un contrôleur.

/// Lance une nouvelle fenêtre OMNIA indépendante avec le chemin spécifié.
Future<void> openInNewWindow(String path) async {
  try {
    final exe = Platform.resolvedExecutable;
    await Process.start(
      exe,
      ['--new-window', path],
      mode: ProcessStartMode.detached,
    );
  } catch (_) {
    // Échec de création du processus détaché.
  }
}

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
  final prefs = ref.read(preferencesProvider);
  final file = await FilePicker.pickFile(
    dialogTitle: 'OMNIA',
    type: FileType.custom,
    allowedExtensions: mediaPickerExtensions(),
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  final path = file?.path;
  if (path != null) {
    if (prefs.inAppOpenNewWindow) {
      await openInNewWindow(path);
    } else {
      bus.dispatch(OpenFile(path));
    }
  }
}

Future<void> pickAndOpenFolder(WidgetRef ref) async {
  final bus = ref.read(commandBusProvider);
  final prefs = ref.read(preferencesProvider);
  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: 'OMNIA',
    windowsOptions: const WindowsOptions(lockParentWindow: true),
    linuxOptions: const LinuxOptions(lockParentWindow: true),
  );
  if (dir != null) {
    if (prefs.inAppOpenNewWindow) {
      await openInNewWindow(dir);
    } else {
      bus.dispatch(OpenFolder(dir));
    }
  }
}
