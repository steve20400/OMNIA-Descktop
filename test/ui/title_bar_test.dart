import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/ui/widgets/title_bar.dart';
import 'package:window_manager/window_manager.dart';

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
      expect(tester.getRect(find.byType(DragToMoveArea)), bar, reason: where);

      final settings = byTooltipPrefix('Paramètres');
      expectWithin(tester, settings, bar, reason: '$where : paramètres');
      expectWithin(tester, byTooltipPrefix('Ouvrir un fichier'), bar, reason: '$where : ouvrir');
      expectWithin(tester, byTooltipPrefix('Toujours au premier plan'), bar, reason: '$where : premier plan');
      expectWithin(tester, byTooltipPrefix('OMNIA Connect'), bar, reason: '$where : connect');
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
}
