import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/services/screenshot_service.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
  final when = DateTime(2026, 9, 7, 21, 4, 5);

  setUp(() => dir = Directory.systemTemp.createTempSync('omnia_shot_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  test('enregistre dans le dossier par défaut, avec le nom attendu', () async {
    final service = ScreenshotService(defaultFolder: () async => dir);
    final path = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);

    expect(p.dirname(path), dir.path);
    expect(p.basename(path), 'ep1 2026-09-07 21-04-05.png');
    expect(File(path).readAsBytesSync(), png);
  });

  test('le dossier des préférences a priorité', () async {
    final custom = Directory(p.join(dir.path, 'perso'));
    final settings = MemorySettingsStore();
    await settings.setScreenshotFolder(custom.path);
    final service = ScreenshotService(settings: settings, defaultFolder: () async => dir);

    final path = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
    expect(p.dirname(path), custom.path);
    expect(custom.existsSync(), isTrue);
  });

  test('deux captures dans la même seconde ne s’écrasent pas', () async {
    final service = ScreenshotService(defaultFolder: () async => dir);
    final first = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
    final second = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);
    final third = await service.save(png, mediaPath: '/films/ep1.mkv', now: when);

    expect(first, isNot(second));
    expect(p.basename(second), 'ep1 2026-09-07 21-04-05 (2).png');
    expect(p.basename(third), 'ep1 2026-09-07 21-04-05 (3).png');
  });
}
