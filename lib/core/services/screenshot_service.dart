import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_preferences.dart';
import '../utils/screenshot_naming.dart';
import 'local_storage.dart';
import 'settings_store.dart';

/// Enregistre les captures d'écran sur disque.
class ScreenshotService {
  ScreenshotService({this.settings, Future<Directory> Function()? defaultFolder})
      : _defaultFolder = defaultFolder ?? defaultScreenshotFolder;

  final SettingsStore? settings;
  final Future<Directory> Function() _defaultFolder;

  /// Dossier de destination : celui des préférences s'il est défini, sinon
  /// le dossier par défaut du système.
  Future<Directory> folder() async {
    final configured = settings?.screenshotFolder;
    if (configured != null && configured.isNotEmpty) return Directory(configured);
    return _defaultFolder();
  }

  /// Écrit [png] et retourne le chemin du fichier créé. Le nom suit le motif
  /// des préférences ([position] sert au jeton `{position}`).
  ///
  /// Lève une [FileSystemException] si le dossier est inaccessible : c'est à
  /// l'appelant d'en faire un message.
  Future<String> save(
    Uint8List png, {
    required String mediaPath,
    Duration position = Duration.zero,
    DateTime? now,
  }) async {
    final dir = await folder();
    await dir.create(recursive: true);
    final pattern =
        settings?.preferences.screenshotNamePattern ?? AppPreferences.defaultScreenshotPattern;
    var path = p.join(
      dir.path,
      screenshotFileName(mediaPath, now ?? DateTime.now(), pattern: pattern, position: position),
    );
    // Deux captures dans la même seconde : on suffixe plutôt que d'écraser.
    var attempt = 1;
    while (await File(path).exists()) {
      attempt++;
      final base = p.basenameWithoutExtension(path).replaceFirst(RegExp(r' \(\d+\)$'), '');
      path = p.join(dir.path, '$base ($attempt).png');
    }
    await File(path).writeAsBytes(png, flush: true);
    return path;
  }
}

/// Dossier par défaut : `Téléchargements/OMNIA` quand le système sait le
/// donner, sinon le dossier de données de l'application. On évite le dossier
/// « Images » : path_provider ne le connaît pas sur desktop.
Future<Directory> defaultScreenshotFolder() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return Directory(p.join(downloads.path, 'OMNIA'));
  } on Object {
    // Pas de dossier Téléchargements connu sur ce système.
  }
  return Directory(p.join((await localStorageDirectory()).path, 'captures'));
}
