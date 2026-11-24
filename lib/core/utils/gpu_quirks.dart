import 'dart:io';

import '../models/app_preferences.dart';

/// Les puces graphiques Intel dont le décodage vidéo par le pilote Linux
/// (VAAPI, pilote i965) peut figer toute la machine pendant une lecture :
/// Ironlake (Gen5) et Sandy Bridge (Gen6), par leur identifiant PCI.
///
/// Diagnostic du 24 novembre 2026 sur un Latitude E6420 (Sandy Bridge) : six
/// gels sur six pendant une vidéo décodée par VAAPI, sous VLC comme sous
/// OMNIA — échecs d'allocation de surfaces juste avant, puis verrouillage
/// complet sans un mot du noyau (CHANTIERS S.2).
const Set<int> fragileIntelDecoders = {
  // Ironlake.
  0x0042, 0x0046,
  // Sandy Bridge.
  0x0102, 0x0106, 0x010A, 0x0112, 0x0116, 0x0122, 0x0126,
};

/// Vrai si cette machine a une puce graphique au décodage fragile.
///
/// Lit les identifiants exposés par le noyau sous [drmRoot]. Hors de Linux,
/// toujours faux : ce pilote-là n'existe que sous Linux.
bool hasFragileVideoDecoder({String drmRoot = '/sys/class/drm', bool? linux}) {
  if (!(linux ?? Platform.isLinux)) return false;
  try {
    for (final entry in Directory(drmRoot).listSync()) {
      final name = entry.path.split(Platform.pathSeparator).last.split('/').last;
      if (!RegExp(r'^card\d+$').hasMatch(name)) continue;
      final vendor = _hexIn(File('${entry.path}/device/vendor'));
      final device = _hexIn(File('${entry.path}/device/device'));
      if (vendor == 0x8086 && device != null && fragileIntelDecoders.contains(device)) {
        return true;
      }
    }
  } on FileSystemException {
    // Pas de /sys lisible : on ne sait pas, on ne présume rien.
  }
  return false;
}

/// La réponse pour cette machine, lue une fois.
final bool fragileVideoDecoder = hasFragileVideoDecoder();

/// La valeur de la propriété `hwdec` de mpv pour [mode].
///
/// « auto-safe » : mpv n'essaie que les méthodes qu'il sait fiables. Sur une
/// puce au décodage fragile, Automatique coupe le décodage matériel : le
/// processeur s'en charge, plus lentement, sans exposer la machine.
String hwdecFor(HardwareDecoding mode, {required bool fragile}) => switch (mode) {
      HardwareDecoding.on => 'auto-safe',
      HardwareDecoding.off => 'no',
      HardwareDecoding.auto => fragile ? 'no' : 'auto-safe',
    };

int? _hexIn(File file) {
  try {
    final text = file.readAsStringSync().trim();
    return int.tryParse(text.startsWith('0x') ? text.substring(2) : text, radix: 16);
  } on FileSystemException {
    return null;
  }
}
