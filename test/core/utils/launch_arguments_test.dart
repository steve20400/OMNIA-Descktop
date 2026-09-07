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

  test('sans argument, rien à ouvrir', () {
    expect(commandForLaunchArguments(const []), isNull);
    expect(commandForLaunchArguments(const ['--verbose']), isNull);
    expect(commandForLaunchArguments(const ['   ']), isNull);
  });

  test('un fichier existant devient OpenFile', () {
    final file = File(p.join(dir.path, 'a.mkv'))..createSync();
    expect(commandForLaunchArguments([file.path]), OpenFile(file.path));
  });

  test('un dossier devient OpenFolder', () {
    expect(commandForLaunchArguments([dir.path]), OpenFolder(dir.path));
  });

  test('les options sont ignorées, le premier chemin gagne', () {
    final file = File(p.join(dir.path, 'a.mkv'))..createSync();
    expect(
      commandForLaunchArguments(['--flag', file.path, dir.path]),
      OpenFile(file.path),
    );
  });

  test('un chemin introuvable est quand même tenté, pour afficher une erreur', () {
    final missing = p.join(dir.path, 'absent.mkv');
    expect(commandForLaunchArguments([missing]), OpenFile(missing));
  });
}
