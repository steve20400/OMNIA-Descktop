import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/utils/launch_arguments.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('omnia_args_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  File touch(String name) => File(p.join(dir.path, name))..createSync(recursive: true);

  group('Arguments de la ligne de commande', () {
    test('sans argument, rien à ouvrir', () {
      expect(commandForLaunchArguments(const []), isNull);
      expect(commandForLaunchArguments(const ['--verbose']), isNull);
      expect(commandForLaunchArguments(const ['   ']), isNull);
    });

    test('un fichier existant devient OpenFile', () {
      final file = touch('a.mkv');
      expect(commandForLaunchArguments([file.path]), OpenFile(file.path));
    });

    test('un dossier devient OpenFolder', () {
      expect(commandForLaunchArguments([dir.path]), OpenFolder(dir.path));
    });

    test('les options sont ignorées, le premier chemin gagne', () {
      final file = touch('a.mkv');
      expect(
        commandForLaunchArguments(['--flag', file.path, dir.path]),
        OpenFile(file.path),
      );
    });

    test('un chemin introuvable est quand même tenté, pour afficher une erreur', () {
      final missing = p.join(dir.path, 'absent.mkv');
      expect(commandForLaunchArguments([missing]), OpenFile(missing));
    });

    test('un URI file:// (lanceurs Linux, docks) est décodé en chemin', () {
      final file = touch(p.join('Vidéos été', 'film 1.mkv'));
      final uri = Uri.file(file.path).toString();
      expect(uri, startsWith('file:'));
      expect(uri, contains('%20'));
      expect(pathFromArgument(uri), file.path);
      expect(commandForLaunchArguments([uri]), OpenFile(file.path));
    });
  });

  group('Fichiers déposés', () {
    test('le premier fichier lisible gagne sur un fichier inconnu', () {
      final unknown = touch('archive.zip');
      final film = touch('film.mkv');
      expect(commandForPaths([unknown.path, film.path]), OpenFile(film.path));
    });

    test('rien de lisible : le premier est tenté, pour afficher une erreur', () {
      final unknown = touch('archive.zip');
      expect(commandForPaths([unknown.path]), OpenFile(unknown.path));
      expect(commandForPaths(const []), isNull);
    });

    test('un dossier déposé en premier est scanné', () {
      final film = touch('film.mkv');
      expect(commandForPaths([dir.path, film.path]), OpenFolder(dir.path));
    });

    test('un sous-titre déposé sur une vidéo se charge sur elle', () {
      final subtitle = touch('film.fr.srt');
      expect(
        commandForPaths([subtitle.path], videoPlaying: true),
        LoadSubtitleFile(subtitle.path),
      );
    });

    test('sans vidéo en cours, le sous-titre cède la place au média déposé avec lui', () {
      final subtitle = touch('film.srt');
      final film = touch('film.mkv');
      expect(commandForPaths([subtitle.path, film.path]), OpenFile(film.path));
    });

    test('reconnaît les extensions de sous-titres, sans tenir compte de la casse', () {
      expect(isSubtitlePath('/a/film.SRT'), isTrue);
      expect(isSubtitlePath('/a/film.ass'), isTrue);
      expect(isSubtitlePath('/a/film.vtt'), isTrue);
      expect(isSubtitlePath('/a/film.mkv'), isFalse);
      expect(isSubtitlePath('/a/srt'), isFalse);
    });
  });
}
