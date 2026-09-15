import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// L'icône livrée : le SVG de Linux se suffit à lui-même, et l'.ico de
/// Windows, généré par tool/make_icon.py, porte le même duo d'écrans à
/// chaque taille. Un moniteur ou un téléphone retouché dans le SVG sans
/// relancer le script se voit ici.
void main() {
  group('Icône Linux (SVG)', () {
    late String svg;

    setUpAll(() => svg = File('linux/dev.omnia.omnia.svg').readAsStringSync());

    test('carré de 256 px, sans ressource externe', () {
      expect(svg, contains('viewBox="0 0 256 256" width="256" height="256"'));
      expect(svg, isNot(contains('href')));
      expect(svg, isNot(contains('<image')));
    });

    test('chaque dégradé utilisé est défini dans le fichier', () {
      final used = RegExp(r'url\(#([\w-]+)\)').allMatches(svg).map((m) => m.group(1)!).toSet();
      final defined = RegExp(r'\bid="([\w-]+)"').allMatches(svg).map((m) => m.group(1)!).toSet();
      expect(used, {'g-bg', 'g-beam'});
      expect(defined, containsAll(used));
    });

    test('le duo d’écrans : un moniteur blanc chaud et un téléphone ambre', () {
      expect(
        svg,
        contains('<rect x="28" y="50" width="172" height="118" rx="16" '
            'fill="#1C1720" stroke="#F3EFE6" stroke-width="9"/>'),
      );
      expect(
        svg,
        contains('<rect x="160" y="100" width="66" height="116" rx="16" '
            'fill="#F2B441" stroke="#120F14" stroke-width="9"/>'),
      );
    });
  });

  group('Icône Windows (.ico)', () {
    final images = <int, _Rgba>{};

    setUpAll(() {
      final ico = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
      for (final entry in _icoEntries(ico)) {
        images[entry.size] = _decodePng(entry.png);
      }
    });

    test('une image PNG par taille, de 16 à 256 px', () {
      expect(images.keys, [16, 24, 32, 48, 64, 128, 256]);
      for (final MapEntry(key: size, value: image) in images.entries) {
        expect(image.width, size);
        expect(image.height, size);
      }
    });

    test('coins arrondis transparents, centre opaque, à chaque taille', () {
      for (final MapEntry(key: size, value: image) in images.entries) {
        expect(image.alpha(0, 0), 0, reason: '$size px');
        expect(image.alpha(size ~/ 2, size ~/ 2), 255, reason: '$size px');
      }
    });

    test('en grand, le dessin complet du SVG', () {
      final icon = images[256]!;
      for (final (x, y, color, what) in const [
        (27, 110, '#F3EFE6FF', 'contour du moniteur'),
        (40, 150, '#1C1720FF', 'écran du moniteur'),
        (61, 109, '#F3EFE6FF', 'lampe'),
        (159, 150, '#120F14FF', 'contour du téléphone'),
        (175, 190, '#F2B441FF', 'corps du téléphone'),
        (180, 170, '#120F14FF', 'écran du téléphone'),
        (192, 150, '#F2B441FF', 'bouton lecture'),
        (197, 64, '#F2B441FF', 'première onde'),
      ]) {
        expect(icon.hex(x, y), color, reason: what);
      }
      // Le faisceau pâlit en s'éloignant de la lampe.
      expect(icon.red(80, 110), greaterThan(icon.red(150, 110) + 100));
      // La seconde onde, à 55 %, reste plus discrète que la première.
      expect(icon.red(202, 50), inExclusiveRange(100, 200));
    });

    test('en petit, contours d’un pixel plein et écran du téléphone net', () {
      for (final (size, x, y, color, what) in const [
        (16, 1, 6, '#F3EFE6FF', 'contour du moniteur'),
        (16, 10, 9, '#F2B441FF', 'bord du téléphone'),
        (16, 11, 9, '#120F14FF', 'écran du téléphone'),
        (24, 2, 10, '#F3EFE6FF', 'contour du moniteur'),
        (24, 15, 14, '#F2B441FF', 'bord du téléphone'),
        (24, 17, 14, '#120F14FF', 'écran du téléphone'),
      ]) {
        expect(images[size]!.hex(x, y), color, reason: '$what, $size px');
      }
    });
  });
}

/// Entrées d'un .ico : taille en pixels (0 y vaut 256) et image PNG.
List<({int size, Uint8List png})> _icoEntries(Uint8List ico) {
  final data = ByteData.sublistView(ico);
  if (data.getUint16(0, Endian.little) != 0 || data.getUint16(2, Endian.little) != 1) {
    throw const FormatException('en-tête ICO invalide');
  }
  final count = data.getUint16(4, Endian.little);
  final entries = <({int size, Uint8List png})>[];
  for (var i = 0; i < count; i++) {
    final entry = 6 + 16 * i;
    final length = data.getUint32(entry + 8, Endian.little);
    final offset = data.getUint32(entry + 12, Endian.little);
    entries.add((
      size: ico[entry] == 0 ? 256 : ico[entry],
      png: Uint8List.sublistView(ico, offset, offset + length),
    ));
  }
  return entries;
}

/// Image RGBA 8 bits, lue pixel par pixel.
class _Rgba {
  _Rgba(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;

  int _index(int x, int y) => (y * width + x) * 4;

  int red(int x, int y) => pixels[_index(x, y)];

  int alpha(int x, int y) => pixels[_index(x, y) + 3];

  /// Couleur du pixel en « #RRGGBBAA », comparable aux couleurs du SVG.
  String hex(int x, int y) {
    final i = _index(x, y);
    final channels = pixels.sublist(i, i + 4).map((c) => c.toRadixString(16).padLeft(2, '0'));
    return '#${channels.join().toUpperCase()}';
  }
}

/// Décode un PNG RGBA 8 bits non entrelacé, le format qu'écrit make_icon.py.
_Rgba _decodePng(Uint8List png) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (png[i] != signature[i]) throw const FormatException('signature PNG absente');
  }
  final data = ByteData.sublistView(png);
  var width = 0;
  var height = 0;
  final compressed = <int>[];
  var offset = 8;
  while (offset + 8 <= png.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png, offset + 4, offset + 8);
    final body = Uint8List.sublistView(png, offset + 8, offset + 8 + length);
    if (type == 'IHDR') {
      width = data.getUint32(offset + 8);
      height = data.getUint32(offset + 12);
      // Profondeur 8 bits, couleur 6 (RGBA), sans entrelacement.
      if (body[8] != 8 || body[9] != 6 || body[12] != 0) {
        throw const FormatException('PNG RGBA 8 bits attendu');
      }
    } else if (type == 'IDAT') {
      compressed.addAll(body);
    } else if (type == 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  final raw = zlib.decode(compressed);
  final stride = width * 4;
  final pixels = Uint8List(height * stride);
  var src = 0;
  for (var y = 0; y < height; y++) {
    final filter = raw[src++];
    for (var x = 0; x < stride; x++) {
      final i = y * stride + x;
      final left = x >= 4 ? pixels[i - 4] : 0;
      final up = y > 0 ? pixels[i - stride] : 0;
      final upLeft = x >= 4 && y > 0 ? pixels[i - stride - 4] : 0;
      final value = raw[src++];
      // Filtres PNG : aucun, gauche, haut, moyenne, Paeth. Uint8List ne garde
      // que les huit bits de poids faible : la somme modulo 256 de la norme.
      pixels[i] = switch (filter) {
        0 => value,
        1 => value + left,
        2 => value + up,
        3 => value + (left + up) ~/ 2,
        4 => value + _paeth(left, up, upLeft),
        _ => throw FormatException('filtre PNG inconnu : $filter'),
      };
    }
  }
  return _Rgba(width, height, pixels);
}

/// Prédicteur de Paeth (norme PNG, filtre 4).
int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}
