// Éditeur de raccourcis dans les fenêtres étroites : l'explication, le bouton
// « Tout rétablir », les touches de chaque action et les actions de saisie
// (Remplacer / Annuler) doivent rester lisibles et atteignables jusqu'à 320 px.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/settings/shortcut_editor.dart';

import 'narrow_harness.dart';

const _hint = 'Cliquez sur un raccourci';

/// L'élément trouvé tient dans la largeur [width] : rien ne dépasse sur les
/// côtés. (La hauteur ne dit rien ici : l'éditeur est plus haut que la
/// fenêtre, et défile.)
void _expectWithinWidth(WidgetTester tester, Finder finder, double width, {String? reason}) {
  final rect = tester.getRect(finder);
  final inside = rect.left >= -0.5 && rect.right <= width + 0.5;
  expect(inside, isTrue, reason: '${reason ?? '$finder'} : $rect déborde de $width');
}

void main() {
  group('ShortcutEditor', () {
    Future<LeafHarness> pumpEditor(WidgetTester tester, {double width = 1200}) async {
      final harness = LeafHarness();
      harness.attach(tester);
      tester.view.physicalSize = Size(width, 900);
      // Comme la section « Raccourcis » des paramètres : dans une zone qui
      // défile, sur toute la largeur qu'on lui laisse.
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          const SingleChildScrollView(child: ShortcutEditor()),
        ),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('à toutes les largeurs, rien ne déborde et tout reste lisible', (tester) async {
      await pumpEditor(tester);

      for (final width in narrowWidths) {
        await resizeWindow(tester, Size(width, 900));
        final where = 'largeur $width';
        expect(tester.takeException(), isNull, reason: where);

        for (final finder in [
          find.textContaining(_hint),
          find.text('Tout rétablir'),
          find.text('Lecture / pause'),
          find.text('Espace'),
        ]) {
          expect(finder, findsOneWidget, reason: '$where : $finder');
          _expectWithinWidth(tester, finder, width, reason: '$where : $finder');
        }
      }
    });

    testWidgets('étroit, « Tout rétablir » passe sous l’explication', (tester) async {
      await pumpEditor(tester, width: 320);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text('Tout rétablir')).top,
        greaterThan(tester.getRect(find.textContaining(_hint)).bottom - 0.5),
      );

      // Large, les deux partagent la même ligne, comme avant.
      await resizeWindow(tester, const Size(1200, 900));
      expect(
        tester.getRect(find.text('Tout rétablir')).center.dy,
        closeTo(tester.getRect(find.textContaining(_hint)).center.dy, 2),
      );
    });

    testWidgets('la saisie et son conflit restent utilisables à 320 px', (tester) async {
      await pumpEditor(tester, width: 320);

      // Un clic sur les touches d'une action ouvre la saisie.
      await tester.tap(find.text('Espace'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Appuyez sur la combinaison…'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
      _expectWithinWidth(tester, find.text('Annuler'), 320, reason: 'annuler');

      // « M » appartient déjà à la sourdine : le conflit s'affiche, avec le
      // choix de remplacer ou d'annuler.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Déjà utilisé par'), findsOneWidget);
      for (final label in ['Remplacer', 'Annuler']) {
        expect(find.text(label), findsOneWidget, reason: label);
        _expectWithinWidth(tester, find.text(label), 320, reason: label);
      }

      // Remplacer réaffecte la touche : « Lecture / pause » prend M.
      await tester.tap(find.text('Remplacer'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Espace'), findsNothing);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('Remplacer'), findsNothing);
    });

    testWidgets('Échap abandonne la saisie, à l’étroit comme au large', (tester) async {
      await pumpEditor(tester, width: 360);

      await tester.tap(find.text('Espace'));
      await tester.pumpAndSettle();
      expect(find.text('Appuyez sur la combinaison…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Appuyez sur la combinaison…'), findsNothing);
      expect(find.text('Espace'), findsOneWidget);
    });
  });
}
