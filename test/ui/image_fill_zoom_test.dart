import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/widgets/image_stage.dart';

void main() {
  const ecran = Size(1600, 900);

  test('une photo en hauteur, tournée, prend toute la largeur de l’écran', () {
    // 1000 × 1500 tournée devient 1500 × 1000 : ajustée à 1350 × 900, il
    // faut 1600 / 1350 pour en couvrir la largeur.
    final zoom = imageFillZoom(stage: ecran, image: const Size(1000, 1500), quarterTurns: 1);
    expect(zoom, closeTo(1600 / 1350, 1e-9));
  });

  test('sans rotation, la même photo doit beaucoup plus grandir pour remplir', () {
    final zoom = imageFillZoom(stage: ecran, image: const Size(1000, 1500), quarterTurns: 0);
    expect(zoom, closeTo(1600 / 600, 1e-9));
  });

  test('une image déjà aux proportions de l’écran ne bouge pas', () {
    final zoom = imageFillZoom(stage: ecran, image: const Size(3200, 1800), quarterTurns: 0);
    expect(zoom, closeTo(1, 1e-9));
  });

  test('une petite image garde sa taille : le zoom fait tout le chemin', () {
    final zoom = imageFillZoom(stage: ecran, image: const Size(400, 300), quarterTurns: 2);
    expect(zoom, closeTo(1600 / 400, 1e-9));
  });
}
