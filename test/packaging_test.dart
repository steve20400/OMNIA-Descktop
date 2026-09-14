import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/controllers/media_router.dart';

/// Les fichiers d'intégration au système doivent rester fidèles au code :
/// une extension ajoutée à MediaRouter doit aussi être proposée par
/// l'installateur Windows, et le fichier .desktop doit porter l'identifiant
/// d'application sans lequel GNOME ne relie pas la fenêtre à son icône.
void main() {
  group('Installateur Windows', () {
    late String iss;

    setUpAll(() => iss = File('windows/installer/omnia.iss').readAsStringSync());

    test('chaque extension lisible est proposée dans « Ouvrir avec »', () {
      final declared = RegExp(r'Software\\Classes\\\.([a-z0-9]+)\\OpenWithProgids')
          .allMatches(iss)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, MediaRouter.allExtensions,
          reason: 'relancer : python tool/make_installer_assoc.py');
    });

    test('chaque extension est aussi un type pris en charge par l’application', () {
      final supported = RegExp(r'SupportedTypes"; ValueType: string; ValueName: "\.([a-z0-9]+)"')
          .allMatches(iss)
          .map((m) => m.group(1)!)
          .toSet();
      expect(supported, MediaRouter.allExtensions);
    });

    test('l’icône de l’installateur existe', () {
      expect(File('windows/runner/resources/app_icon.ico').existsSync(), isTrue);
    });
  });

  test('le manifeste Windows accepte les chemins longs', () {
    final manifest = File('windows/runner/runner.exe.manifest').readAsStringSync();
    expect(manifest, contains('<longPathAware'));
    expect(manifest, contains('>true</longPathAware>'));
  });

  group('Fichier .desktop Linux', () {
    late String desktop;

    setUpAll(() => desktop = File('linux/dev.omnia.omnia.desktop').readAsStringSync());

    String? field(String key) =>
        RegExp('^$key=(.*)\$', multiLine: true).firstMatch(desktop)?.group(1)?.trim();

    test('identifiant d’application cohérent', () {
      expect(field('StartupWMClass'), 'dev.omnia.omnia');
      expect(field('Icon'), 'dev.omnia.omnia');
      expect(File('linux/dev.omnia.omnia.svg').existsSync(), isTrue);
    });

    test('fichiers déposés sur l’icône ou « Ouvrir avec » : un seul lancement', () {
      // %F : tous les fichiers en une fois. Avec %f, GNOME lancerait OMNIA une
      // fois par fichier déposé.
      expect(field('Exec'), 'omnia %F');
    });

    test('les familles de formats lisibles sont déclarées', () {
      final mimes = field('MimeType')!.split(';').where((m) => m.isNotEmpty).toSet();
      expect(mimes, containsAll(['video/mp4', 'video/x-matroska', 'audio/mpeg', 'audio/flac']));
      expect(mimes, containsAll(['application/pdf', 'text/plain', 'text/markdown']));
    });
  });
}
