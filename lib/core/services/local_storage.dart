import 'dart:io';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Initialise Hive dans le dossier de données applicatives du système.
///
/// On n'utilise pas `Hive.initFlutter`, qui passe par le dossier « Documents »
/// de l'utilisateur : sous Linux, ce dossier est résolu en lançant le binaire
/// externe `xdg-user-dir`, absent d'un système minimal, et l'échec remonte
/// avant même l'affichage de la fenêtre — OMNIA ne démarrerait pas, sans
/// aucun message. Le dossier de support applicatif, lui, est toujours
/// déterminable :
///
/// - Linux  : `~/.local/share/dev.omnia.omnia/`
/// - Windows: `%APPDATA%\dev.omnia\omnia\`
/// - macOS  : `~/Library/Application Support/dev.omnia.omnia/`
Future<void> initialiseLocalStorage() async {
  if (_initialised) return;
  Hive.init((await localStorageDirectory()).path);
  _initialised = true;
}

/// Dossier de données local d'OMNIA (boîtes Hive, verrou d'instance unique).
Future<Directory> localStorageDirectory() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'data'));
}

bool _initialised = false;
