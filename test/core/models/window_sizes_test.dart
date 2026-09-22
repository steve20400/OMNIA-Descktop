import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/window_sizes.dart';

void expectSize(Size actual, double width, double height) {
  expect(actual.width, closeTo(width, 1e-9), reason: 'largeur');
  expect(actual.height, closeTo(height, 1e-9), reason: 'hauteur');
}

void main() {
  group('WindowSizes', () {
    test('vidéo paysage : la largeur porte le grand côté', () {
      expectSize(WindowSizes.miniVideoSize(16 / 9), 400, 225);
      expectSize(WindowSizes.miniVideoSize(1920 / 1080), 400, 225);
      expectSize(WindowSizes.miniVideoSize(4 / 3), 400, 300);
    });

    test('vidéo portrait : la hauteur porte le grand côté', () {
      expectSize(WindowSizes.miniVideoSize(9 / 16), 225, 400);
      expectSize(WindowSizes.miniVideoSize(1080 / 1920), 225, 400);
    });

    test('image carrée', () {
      expectSize(WindowSizes.miniVideoSize(1), 400, 400);
    });

    test('grand côté choisi, jamais sous le plancher', () {
      expectSize(WindowSizes.miniVideoSize(16 / 9, longSide: 600), 600, 337.5);
      expectSize(WindowSizes.miniVideoSize(16 / 9, longSide: 50), 200, 112.5);
      expectSize(WindowSizes.miniVideoSize(9 / 16, longSide: 50), 112.5, 200);
    });

    test('plancher du mini-lecteur vidéo', () {
      expectSize(WindowSizes.miniVideoMinimum(16 / 9), 200, 112.5);
      expectSize(WindowSizes.miniVideoMinimum(9 / 16), 112.5, 200);
    });

    test('un ratio ou un grand côté inexploitable ne donne pas une fenêtre vide', () {
      expectSize(WindowSizes.miniVideoSize(0), 400, 400);
      expectSize(WindowSizes.miniVideoSize(-2), 400, 400);
      expectSize(WindowSizes.miniVideoSize(double.nan), 400, 400);
      expectSize(WindowSizes.miniVideoSize(double.infinity), 400, 400);
      expectSize(WindowSizes.miniVideoSize(16 / 9, longSide: double.nan), 400, 225);
    });

    test('les planchers du mini-lecteur passent sous celui de la fenêtre principale', () {
      expect(WindowSizes.miniAudioMinimum.height, lessThan(WindowSizes.mainMinimum.height));
      expect(WindowSizes.miniVideoMinimum(16 / 9).height, lessThan(WindowSizes.mainMinimum.height));
      expect(WindowSizes.miniAudio.width, greaterThanOrEqualTo(WindowSizes.miniAudioMinimum.width));
      expect(WindowSizes.miniAudio.height, greaterThanOrEqualTo(WindowSizes.miniAudioMinimum.height));
    });

    test('plancher de la fenêtre principale : dimensions compactes sans collision', () {
      expect(WindowSizes.mainMinimum, const Size(320, 240));
      expect(WindowSizes.mainMinimum.width, greaterThanOrEqualTo(320));
      expect(WindowSizes.mainMinimum.height, greaterThanOrEqualTo(240));
    });
  });
}
