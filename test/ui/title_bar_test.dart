import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/ui/widgets/title_bar.dart';
import 'package:omnia/ui/widgets/window_drag_area.dart';

import 'narrow_harness.dart';

const _longName = 'Un film au titre vraiment très long pour une barre étroite.mkv';

void main() {
  group('placeTitle', () {
    test('centré sur la barre quand la place le permet', () {
      final slot = placeTitle(barWidth: 1200, leading: 170, trailing: 138, textWidth: 200)!;
      expect(slot.width, 200);
      expect(slot.left, (1200 - 200) / 2);
    });

    test('décalé plutôt que de toucher un groupe', () {
      // Le groupe de droite est bien plus large : centré, le titre le toucherait.
      final slot = placeTitle(barWidth: 400, leading: 76, trailing: 138, textWidth: 150)!;
      expect(slot.width, 150);
      expect(slot.left, greaterThanOrEqualTo(76 + TitleBar.titleGap));
      expect(slot.left + slot.width, lessThanOrEqualTo(400 - 138 - TitleBar.titleGap));
    });

    test('abrégé à la place qui reste entre les groupes', () {
      final slot = placeTitle(barWidth: 360, leading: 76, trailing: 138, textWidth: 900)!;
      expect(slot.left, 76 + TitleBar.titleGap);
      expect(slot.width, 360 - 76 - 138 - 2 * TitleBar.titleGap);
    });

    test('pas de titre quand il reste moins que la largeur minimale', () {
      expect(placeTitle(barWidth: 300, leading: 76, trailing: 138, textWidth: 60), isNull);
    });
  });

  testWidgets('la barre de titre tient à toutes les largeurs, sans rien chevaucher', (tester) async {
    final harness = LeafHarness(
      state: const PlaybackState(
        file: MediaFile(path: '/films/$_longName', type: MediaType.video),
      ),
    );
    harness.attach(tester);
    tester.view.physicalSize = const Size(1200, 400);
    await tester.pumpWidget(
      omniaTestApp(
        harness.container,
        const Align(alignment: Alignment.topCenter, child: TitleBar()),
      ),
    );
    await tester.pumpAndSettle();

    for (final width in narrowWidths) {
      await resizeWindow(tester, Size(width, 400));
      final where = 'largeur $width';
      expect(tester.takeException(), isNull, reason: where);

      final bar = tester.getRect(find.byType(TitleBar));
      expect(bar.width, width, reason: where);
      // La zone de déplacement couvre toujours toute la barre.
      expect(tester.getRect(find.byType(WindowDragArea)), bar, reason: where);

      final settings = byTooltipPrefix('Paramètres');
      expectWithin(tester, settings, bar, reason: '$where : paramètres');
      expectWithin(tester, byTooltipPrefix('Ouvrir un fichier'), bar, reason: '$where : ouvrir');
      expect(
        find.text('OMNIA'),
        width >= TitleBar.wordmarkMinWidth ? findsOneWidget : findsNothing,
        reason: '$where : mot « OMNIA »',
      );

      if (!Platform.isMacOS) {
        for (final tooltip in ['Réduire', 'Agrandir', 'Fermer']) {
          expectWithin(tester, find.byTooltip(tooltip), bar, reason: '$where : $tooltip');
        }
        // Les deux groupes ne se touchent pas : il reste de quoi saisir la
        // fenêtre entre eux.
        final minimize = tester.getRect(find.byTooltip('Réduire'));
        expect(minimize.left - tester.getRect(settings).right, greaterThan(24), reason: where);

        final title = find.text(_longName);
        if (title.evaluate().isNotEmpty) {
          final rect = tester.getRect(title);
          expect(rect.left, greaterThanOrEqualTo(tester.getRect(settings).right), reason: where);
          expect(rect.right, lessThanOrEqualTo(minimize.left), reason: where);
        }
      }
    }

    // Aux largeurs d'aujourd'hui, le titre est affiché et centré sur la barre.
    await resizeWindow(tester, const Size(1200, 400));
    final title = tester.getRect(find.text(_longName));
    expect(title.center.dx, closeTo(600, 1));
  });

  testWidgets('la barre de titre déplace la fenêtre, autant de fois qu’on veut', (tester) async {
    var drags = 0;
    final harness = LeafHarness(
      state: const PlaybackState(
        file: MediaFile(path: '/films/Film.mkv', type: MediaType.video),
      ),
      overrides: [startWindowDragProvider.overrideWithValue(() => drags++)],
    );
    harness.attach(tester);
    tester.view.physicalSize = const Size(1200, 400);
    await tester.pumpWidget(
      omniaTestApp(
        harness.container,
        const Align(alignment: Alignment.topCenter, child: TitleBar()),
      ),
    );
    await tester.pumpAndSettle();

    // Le centre de la barre : le titre, loin des boutons de fenêtre.
    final grab = tester.getRect(find.byType(TitleBar)).center;

    // Trois fois de suite : le premier déplacement passait déjà, c'est le
    // deuxième qui manquait. Le système avale le bouton relâché pendant qu'il
    // déplace la fenêtre, et l'ancien détecteur de glissement restait bloqué.
    for (var attempt = 1; attempt <= 3; attempt++) {
      final gesture = await tester.startGesture(grab, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(12, 4));
      await tester.pump();
      expect(drags, attempt, reason: 'déplacement n°$attempt');
      // Relâchement perdu, comme sous Windows : la pression suivante doit
      // repartir quand même.
      await tester.pump();
    }

    // Un clic sans mouvement ne déplace pas la fenêtre.
    await tester.tapAt(grab);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
    expect(drags, 3);
  });
}
