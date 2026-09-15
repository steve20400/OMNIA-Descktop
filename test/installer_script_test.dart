import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Inno Setup lit le script en UTF-8 grâce à son BOM ; un second BOM passe
/// pour du texte hors section et fait échouer la compilation. C'est ce que
/// produisait le générateur des extensions en relisant le fichier.
void main() {
  test('le script de l’installateur commence par un seul BOM UTF-8', () {
    final bytes = File('windows/installer/omnia.iss').readAsBytesSync();
    expect(bytes.sublist(0, 4), [0xEF, 0xBB, 0xBF, 0x3B],
        reason: 'un seul BOM, puis le « ; » du premier commentaire : '
            'relancer python tool/make_installer_assoc.py');
  });
}
