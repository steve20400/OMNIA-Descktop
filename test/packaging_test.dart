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

    test('la version par défaut est celle du pubspec, et la CI peut la fixer', () {
      final pubspec = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync())!
          .group(1);
      expect(iss, contains('#ifndef AppVersion'));
      expect(RegExp(r'#define AppVersion "([^"]+)"').firstMatch(iss)?.group(1), pubspec);
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
      expect(File('linux/dev.omnia.omnia.png').existsSync(), isTrue);
      expect(File('linux/icons/hicolor/256x256/apps/dev.omnia.omnia.png').existsSync(), isTrue);
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
      expect(mimes, containsAll(['image/png', 'image/jpeg', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']));
    });

  });

  group('Intégration continue', () {
    late String workflow;

    setUpAll(() => workflow = File('.github/workflows/ci.yml').readAsStringSync());

    test('Flutter est épinglé sur la version compatible avec pdfrx', () {
      expect(workflow, contains("FLUTTER_VERSION: '3.44.8'"));
      // pdfrx ≥ 2.6 exige Flutter 3.47 : les deux se relèvent ensemble.
      expect(File('pubspec.yaml').readAsStringSync(), contains('pdfrx: ">=2.4.0 <2.6.0"'));
    });

    test('Windows et Ubuntu sont compilés et lancés pour de vrai', () {
      expect(workflow, contains('runs-on: windows-2025'));
      expect(workflow, contains('flutter build windows --release'));
      expect(workflow, contains('runs-on: ubuntu-24.04'));
      expect(workflow, contains('flutter build linux --release'));
      expect(workflow, contains('smoke_windows.ps1'));
      expect(workflow, contains('smoke_linux.sh'));
    });

    test('chaque script appelé par le workflow existe', () {
      final scripts = RegExp(r'tool/ci/[\w.]+').allMatches(workflow).map((m) => m.group(0)!).toSet();
      expect(scripts, isNotEmpty);
      for (final script in scripts) {
        expect(File(script).existsSync(), isTrue, reason: script);
      }
      // Les scripts appelés par d'autres scripts aussi.
      expect(File('tool/ci/make_samples.py').existsSync(), isTrue);
    });

    test('une étape conditionnelle garde une fonction d’état', () {
      // Sans success(), always() ou !cancelled(), GitHub ajoute success() :
      // l'étape serait sautée dès qu'une étape précédente a échoué.
      final conditions = RegExp(r'^\s*if: (.+)$', multiLine: true)
          .allMatches(workflow)
          .map((m) => m.group(1)!);
      for (final condition in conditions) {
        expect(condition, matches(RegExp(r'success\(\)|failure\(\)|always\(\)|cancelled\(\)')),
            reason: condition);
      }
    });

    test('les scripts shell gardent des fins de ligne LF', () {
      expect(File('.gitattributes').readAsStringSync(), contains('*.sh text eol=lf'));
    });
  });
}
