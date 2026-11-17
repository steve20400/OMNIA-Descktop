import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../controllers/media_router.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';

/// Les dossiers personnels où vivent les médias de l'utilisateur : vidéos,
/// musique, images, documents.
///
/// - Windows : sous le profil, `Videos`, `Music`, `Pictures`, `Documents`.
///   « Vidéos » ou « Musique » ne sont que la traduction qu'affiche
///   l'explorateur : sur le disque, les noms restent anglais.
/// - Linux : ceux que déclare `~/.config/user-dirs.dirs` — « Vidéos » sur un
///   Ubuntu en français —, à défaut les noms anglais.
/// - macOS : `Movies`, `Music`, `Pictures`, `Documents`.
///
/// Fonction pure, pour être vérifiable sans le système : [environment] tient
/// lieu des variables d'environnement, [userDirs] du contenu de
/// `user-dirs.dirs`.
List<String> userMediaFolders({
  required Map<String, String> environment,
  required String os,
  String? userDirs,
}) {
  if (os == 'windows') {
    final profile = environment['USERPROFILE'];
    if (profile == null || profile.isEmpty) return const [];
    return [for (final name in const ['Videos', 'Music', 'Pictures', 'Documents']) p.join(profile, name)];
  }
  final home = environment['HOME'];
  if (home == null || home.isEmpty) return const [];
  if (os == 'macos') {
    return [for (final name in const ['Movies', 'Music', 'Pictures', 'Documents']) p.join(home, name)];
  }

  // Linux et apparentés : les répertoires XDG, s'ils sont déclarés.
  final declared = <String, String>{};
  for (final line in (userDirs ?? '').split('\n')) {
    final match = RegExp(r'^\s*XDG_([A-Z]+)_DIR\s*=\s*"?([^"]*)"?\s*$').firstMatch(line);
    if (match == null) continue;
    final value = match.group(2)!.replaceFirst(r'$HOME', home);
    // Un répertoire désactivé pointe sur le dossier personnel lui-même : le
    // parcourir reviendrait à tout parcourir.
    if (p.equals(value, home)) continue;
    declared[match.group(1)!] = value;
  }
  return [
    declared['VIDEOS'] ?? p.join(home, 'Videos'),
    declared['MUSIC'] ?? p.join(home, 'Music'),
    declared['PICTURES'] ?? p.join(home, 'Pictures'),
    declared['DOCUMENTS'] ?? p.join(home, 'Documents'),
  ];
}

/// Les dossiers personnels de cette machine.
List<String> defaultUserMediaFolders() {
  String? userDirs;
  final home = Platform.environment['HOME'];
  if (Platform.isLinux && home != null) {
    try {
      userDirs = File(p.join(home, '.config', 'user-dirs.dirs')).readAsStringSync();
    } on FileSystemException {
      // Pas de répertoires XDG déclarés : les noms anglais servent.
    }
  }
  return userMediaFolders(
    environment: Platform.environment,
    os: Platform.operatingSystem,
    userDirs: userDirs,
  );
}

/// Les médias de [roots], du plus récent au plus ancien, scannés hors de
/// l'interface : un dossier « Documents » de plusieurs milliers de fichiers
/// ne doit pas figer l'accueil.
Future<List<MediaFile>> scanUserLibrary(List<String> roots) async {
  if (roots.isEmpty) return const [];
  try {
    final raw = await Isolate.run(() => scanLibrarySync(roots));
    return raw.map(MediaFile.fromJson).toList();
  } on Object {
    return const [];
  }
}

/// Parcours synchrone des dossiers [roots], exposé pour l'isolate et les
/// tests.
///
/// Bornes, parce que ces dossiers peuvent être immenses : [maxDepth]
/// niveaux de sous-dossiers, [maxEntries] éléments visités au total,
/// [budget] de temps, et [perType] fichiers gardés par type de média. Les
/// dossiers cachés, la corbeille et les dépendances de développement sont
/// sautés : rien de ce qu'on y trouve n'a sa place à l'accueil.
List<Map<String, Object?>> scanLibrarySync(
  List<String> roots, {
  int maxDepth = 3,
  int maxEntries = 8000,
  int perType = 150,
  Duration budget = const Duration(seconds: 3),
}) {
  final clock = Stopwatch()..start();
  final found = <MediaFile>[];
  var visited = 0;

  bool skipped(String name) =>
      name.startsWith('.') ||
      name.startsWith(r'$') ||
      name == 'node_modules' ||
      name == 'AppData';

  final queue = <(Directory, int)>[
    for (final root in roots)
      if (Directory(root).existsSync()) (Directory(root), 0),
  ];
  while (queue.isNotEmpty) {
    if (visited >= maxEntries || clock.elapsed >= budget) break;
    final (dir, depth) = queue.removeAt(0);
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entity in entries) {
      if (++visited >= maxEntries) break;
      final name = p.basename(entity.path);
      if (skipped(name)) continue;
      if (entity is Directory) {
        if (depth < maxDepth) queue.add((entity, depth + 1));
        continue;
      }
      if (entity is! File) continue;
      final type = MediaRouter.typeForPath(entity.path);
      if (!type.isSupported) continue;
      try {
        final stat = entity.statSync();
        found.add(
          MediaFile(path: entity.path, type: type, size: stat.size, modifiedAt: stat.modified),
        );
      } on FileSystemException {
        // Disparu entre le listing et le stat.
      }
    }
  }

  found.sort((a, b) => (b.modifiedAt ?? DateTime(0)).compareTo(a.modifiedAt ?? DateTime(0)));
  final kept = <MediaType, int>{};
  return [
    for (final file in found)
      if ((kept[file.type] = (kept[file.type] ?? 0) + 1) <= perType) file.toJson(),
  ];
}
