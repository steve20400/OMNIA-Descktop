import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/services/user_library.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Dossiers personnels', () {
    test('Windows : sous le profil, avec les noms du disque', () {
      final folders = userMediaFolders(
        environment: {'USERPROFILE': r'C:\Users\Steve'},
        os: 'windows',
      );
      expect(folders.map(p.basename), ['Videos', 'Music', 'Pictures', 'Documents']);
    });

    test('Linux : les répertoires déclarés, en français', () {
      const userDirs = '''
# Fichier écrit par xdg-user-dirs-update
XDG_DESKTOP_DIR="\$HOME/Bureau"
XDG_VIDEOS_DIR="\$HOME/Vidéos"
XDG_MUSIC_DIR="\$HOME/Musique"
XDG_PICTURES_DIR="\$HOME/Images"
XDG_DOCUMENTS_DIR="\$HOME/Documents"
''';
      final folders = userMediaFolders(
        environment: {'HOME': '/home/steve'},
        os: 'linux',
        userDirs: userDirs,
      );
      // Écrits tels que le fichier les déclare, quel que soit le système
      // qui fait tourner le test.
      expect(folders, [
        '/home/steve/Vidéos',
        '/home/steve/Musique',
        '/home/steve/Images',
        '/home/steve/Documents',
      ]);
    });

    test('Linux : un répertoire désactivé ne fait pas parcourir tout le dossier personnel', () {
      final folders = userMediaFolders(
        environment: {'HOME': '/home/steve'},
        os: 'linux',
        userDirs: 'XDG_VIDEOS_DIR="\$HOME/"\nXDG_MUSIC_DIR="\$HOME"\n',
      );
      expect(folders, isNot(contains('/home/steve')));
      expect(folders.first, p.join('/home/steve', 'Videos'));
    });

    test('macOS : Movies plutôt que Videos', () {
      final folders = userMediaFolders(environment: {'HOME': '/Users/steve'}, os: 'macos');
      expect(folders.first, p.join('/Users/steve', 'Movies'));
    });

    test('sans profil, rien à parcourir', () {
      expect(userMediaFolders(environment: const {}, os: 'windows'), isEmpty);
      expect(userMediaFolders(environment: const {}, os: 'linux'), isEmpty);
    });
  });

  group('Parcours des dossiers', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('omnia_bibliotheque_'));
    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Nettoyé par le système.
      }
    });

    File make(String relative, {required DateTime modified}) {
      final file = File(p.joinAll([root.path, ...relative.split('/')]))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      file.setLastModifiedSync(modified);
      return file;
    }

    List<MediaFile> scan({int perType = 150}) =>
        scanLibrarySync([root.path], perType: perType).map(MediaFile.fromJson).toList();

    test('les médias, du plus récent au plus ancien', () {
      make('Films/ancien.mkv', modified: DateTime(2024));
      make('Films/Séries/récent.mp4', modified: DateTime(2026, 11));
      make('notes.txt', modified: DateTime(2025));
      make('archive.xyz', modified: DateTime(2026));

      final found = scan();
      expect(found.map((f) => p.basename(f.path)), ['récent.mp4', 'notes.txt', 'ancien.mkv']);
      expect(found.first.type, MediaType.video);
    });

    test('ni dossiers cachés, ni corbeille, ni trop de profondeur', () {
      make('.cache/caché.mkv', modified: DateTime(2026));
      make(r'$RECYCLE.BIN/jeté.mkv', modified: DateTime(2026));
      make('a/b/c/trouvé.mkv', modified: DateTime(2026));
      make('a/b/c/d/trop-loin.mkv', modified: DateTime(2026));

      expect(scan().map((f) => p.basename(f.path)), ['trouvé.mkv']);
    });

    test('au plus N fichiers par type', () {
      for (var i = 1; i <= 5; i++) {
        make('Films/film$i.mkv', modified: DateTime(2026, 1, i));
      }
      make('Musique/titre.mp3', modified: DateTime(2020));

      final found = scan(perType: 2);
      expect(found.map((f) => p.basename(f.path)), ['film5.mkv', 'film4.mkv', 'titre.mp3']);
    });

    test('un dossier absent ne donne rien, sans erreur', () {
      expect(scanLibrarySync([p.join(root.path, 'absent')]), isEmpty);
    });
  });
}
