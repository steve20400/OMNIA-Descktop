import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/services/window_service.dart';

/// Une fenêtre qui ne répond jamais : le cas du système qui garde la main
/// pendant un redimensionnement, une réduction ou le retour qui suit.
class _Muette extends FakeWindowService {
  @override
  Future<void> setBounds(Rect value) => Completer<void>().future;

  @override
  Future<Rect> getBounds() => Completer<Rect>().future;

  @override
  Future<bool> isMaximized() => Completer<bool>().future;

  @override
  Future<void> setMinimumSize(Size size) => Completer<void>().future;
}

void main() {
  group('Fenêtre bornée', () {
    const budget = Duration(milliseconds: 30);

    test('un appel sans réponse rend la main au lieu de bloquer', () async {
      final fenetre = BoundedWindowService(_Muette(), budget: budget);
      // Sans borne, chacun de ces appels resterait suspendu pour toujours —
      // et comme les commandes du lecteur s'enchaînent dans une file, toutes
      // les suivantes avec lui.
      await fenetre.setBounds(const Rect.fromLTWH(0, 0, 100, 100))
          .timeout(const Duration(seconds: 2));
      await fenetre.setMinimumSize(const Size(10, 10))
          .timeout(const Duration(seconds: 2));
    });

    test('une question sans réponse rend la dernière valeur connue', () async {
      final vraie = FakeWindowService()..bounds = const Rect.fromLTWH(4, 8, 16, 32);
      final fenetre = BoundedWindowService(vraie, budget: budget);
      expect(await fenetre.getBounds(), const Rect.fromLTWH(4, 8, 16, 32));

      // La même fenêtre se tait désormais : la géométrie rendue est la
      // dernière obtenue, et non une valeur inventée qui enverrait le
      // mini-lecteur dans le coin de l'écran.
      final muette = BoundedWindowService(_Muette(), budget: budget);
      final vue = await muette.getBounds().timeout(const Duration(seconds: 2));
      expect(vue, Rect.zero);
      expect(await muette.isMaximized().timeout(const Duration(seconds: 2)), isFalse);
    });

    test('une fenêtre qui répond passe sans retard ni perte', () async {
      final vraie = FakeWindowService();
      final fenetre = BoundedWindowService(vraie, budget: budget);
      await fenetre.setFullscreen(true);
      expect(await fenetre.isFullscreen(), isTrue);
      await fenetre.setAlwaysOnTop(true);
      expect(await fenetre.isAlwaysOnTop(), isTrue);
      await fenetre.setBounds(const Rect.fromLTWH(1, 2, 3, 4));
      expect(vraie.bounds, const Rect.fromLTWH(1, 2, 3, 4));
      await fenetre.setTitle('OMNIA');
      expect(vraie.title, 'OMNIA');
    });
  });
}
