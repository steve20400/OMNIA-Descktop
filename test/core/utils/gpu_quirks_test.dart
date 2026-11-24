import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/utils/gpu_quirks.dart';
import 'package:path/path.dart' as p;

/// Un faux /sys/class/drm : une carte par couple (fabricant, modèle).
Directory _drm(List<(String, String)> cards) {
  final root = Directory.systemTemp.createTempSync('omnia_drm_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (var i = 0; i < cards.length; i++) {
    final device = Directory(p.join(root.path, 'card$i', 'device'))..createSync(recursive: true);
    File(p.join(device.path, 'vendor')).writeAsStringSync('${cards[i].$1}\n');
    File(p.join(device.path, 'device')).writeAsStringSync('${cards[i].$2}\n');
  }
  // Une sortie d'affichage, qui n'est pas une carte : ignorée.
  Directory(p.join(root.path, 'card0-eDP-1')).createSync();
  return root;
}

void main() {
  group('Puce graphique au décodage fragile', () {
    test('un Sandy Bridge est reconnu, même à côté d’une carte NVIDIA', () {
      final root = _drm([('0x8086', '0x0126'), ('0x10de', '0x1057')]);
      expect(hasFragileVideoDecoder(drmRoot: root.path, linux: true), isTrue);
    });

    test('une puce Intel récente ne l’est pas', () {
      final root = _drm([('0x8086', '0x9a49')]);
      expect(hasFragileVideoDecoder(drmRoot: root.path, linux: true), isFalse);
    });

    test('hors de Linux, jamais', () {
      final root = _drm([('0x8086', '0x0126')]);
      expect(hasFragileVideoDecoder(drmRoot: root.path, linux: false), isFalse);
    });

    test('un /sys absent ne lève rien', () {
      expect(hasFragileVideoDecoder(drmRoot: '/nulle/part', linux: true), isFalse);
    });
  });

  group('Décodage confié à mpv', () {
    test('automatique : coupé sur une puce fragile, sûr ailleurs', () {
      expect(hwdecFor(HardwareDecoding.auto, fragile: true), 'no');
      expect(hwdecFor(HardwareDecoding.auto, fragile: false), 'auto-safe');
    });

    test('le réglage force l’un ou l’autre', () {
      expect(hwdecFor(HardwareDecoding.on, fragile: true), 'auto-safe');
      expect(hwdecFor(HardwareDecoding.off, fragile: false), 'no');
    });

    test('les deux réglages survivent à l’enregistrement', () {
      const prefs = AppPreferences(hardwareDecoding: HardwareDecoding.off, hardwareRendering: false);
      final back = AppPreferences.fromJson(prefs.toJson());
      expect(back.hardwareDecoding, HardwareDecoding.off);
      expect(back.hardwareRendering, isFalse);
      expect(AppPreferences.fromJson(const {}).hardwareDecoding, HardwareDecoding.auto);
      expect(AppPreferences.fromJson(const {}).hardwareRendering, isTrue);
    });
  });
}
