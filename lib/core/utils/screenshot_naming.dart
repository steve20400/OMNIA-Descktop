import 'package:path/path.dart' as p;

/// Nom de fichier d'une capture d'écran : `<média> 2026-09-07 21-14-05.png`.
///
/// Les caractères interdits par Windows (`\ / : * ? " < > |`) sont remplacés,
/// pour que le même nom fonctionne sur les trois systèmes.
String screenshotFileName(String mediaPath, DateTime when, {String extension = 'png'}) {
  final base = sanitiseFileName(p.basenameWithoutExtension(mediaPath));
  final stamp = '${when.year.toString().padLeft(4, '0')}-'
      '${_two(when.month)}-${_two(when.day)} '
      '${_two(when.hour)}-${_two(when.minute)}-${_two(when.second)}';
  return '${base.isEmpty ? 'capture' : base} $stamp.$extension';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Retire ce qu'un système de fichiers refuse dans un nom.
String sanitiseFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  // Windows refuse aussi un nom finissant par un point ou un espace.
  return cleaned.replaceAll(RegExp(r'[. ]+$'), '');
}
