import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/ui/widgets/control_layout.dart';
import 'package:omnia/ui/widgets/document_bar.dart';

import 'narrow_harness.dart';

const _pdf = PlaybackState(
  file: MediaFile(path: '/docs/Rapport annuel.pdf', type: MediaType.pdf),
  currentPage: 3,
  totalPages: 120,
);

const _text = PlaybackState(
  file: MediaFile(path: '/docs/Notes.txt', type: MediaType.text),
);

/// La barre d'un PDF vue par la répartition, avec les priorités du widget.
const _pdfSlots = [
  ControlSlot(id: DocumentBarSlots.pageUp, width: 34, priority: 0),
  ControlSlot(id: DocumentBarSlots.pageField, width: 52, priority: 0),
  ControlSlot(id: DocumentBarSlots.pageTotal, width: 48, priority: 1),
  ControlSlot(id: DocumentBarSlots.pageDown, width: 34, priority: 0),
  ControlSlot(id: DocumentBarSlots.separator, width: 25, priority: 3),
  ControlSlot(id: DocumentBarSlots.zoomOut, width: 34, priority: 4),
  ControlSlot(id: DocumentBarSlots.zoomValue, width: 56, priority: 4),
  ControlSlot(id: DocumentBarSlots.zoomIn, width: 34, priority: 4),
  ControlSlot(id: DocumentBarSlots.fitWidth, width: 34, priority: 6),
  ControlSlot(id: DocumentBarSlots.fitPage, width: 34, priority: 7),
  ControlSlot(id: DocumentBarSlots.rotate, width: 34, priority: 8),
  ControlSlot(id: DocumentBarSlots.layout, width: 34, priority: 9),
  ControlSlot(id: DocumentBarSlots.readingDark, width: 34, priority: 5),
  ControlSlot(id: DocumentBarSlots.find, width: 34, priority: 0),
];

const double _pdfTotal = 521;

/// Commandes dans l'ordre où elles doivent quitter la barre : mise en page,
/// rotation, ajuster à la page, à la largeur, mode sombre, puis le zoom.
/// Chacune est reconnue à son icône.
const _dropOrder = <(String, IconData)>[
  ('mise en page', Icons.view_agenda_outlined),
  ('rotation', Icons.rotate_right_rounded),
  ('ajuster à la page', Icons.crop_portrait_rounded),
  ('ajuster à la largeur', Icons.fit_screen_outlined),
  ('mode sombre', Icons.dark_mode_outlined),
  ('zoom −', Icons.remove_rounded),
];

void main() {
  group('fitDocumentControls', () {
    test('tout tient : ni menu, ni commande cachée', () {
      final fit = fitDocumentControls(_pdfSlots, _pdfTotal, overflowWidth: 42);
      expect(fit.hasOverflow, isFalse);
      expect(fit.shown, [for (final s in _pdfSlots) s.id]);
    });

    test('le zoom part au menu d’un bloc, et le séparateur s’efface avec lui', () {
      // Assez de place pour tout, sauf le « + » du zoom (et le menu).
      final fit = fitDocumentControls(_pdfSlots, 370, overflowWidth: 42);
      expect(fit.overflow, containsAll(DocumentBarSlots.zoomGroup));
      expect(fit.shown, [
        DocumentBarSlots.pageUp,
        DocumentBarSlots.pageField,
        DocumentBarSlots.pageTotal,
        DocumentBarSlots.pageDown,
        DocumentBarSlots.find,
      ]);
    });

    test('la navigation par page et la recherche ne partent jamais', () {
      final fit = fitDocumentControls(_pdfSlots, 0, overflowWidth: 42);
      expect(fit.shown, [
        DocumentBarSlots.pageUp,
        DocumentBarSlots.pageField,
        DocumentBarSlots.pageDown,
        DocumentBarSlots.find,
      ]);
      expect(fit.overflow, isNot(contains(DocumentBarSlots.separator)));
    });

    test('plus étroit ne montre jamais une commande qu’une barre plus large cache', () {
      Set<String> shownAt(double width) =>
          fitDocumentControls(_pdfSlots, width, overflowWidth: 42).shown.toSet();
      for (var width = 0.0; width < _pdfTotal; width += 3) {
        expect(shownAt(width).difference(shownAt(width + 3)), isEmpty, reason: 'largeur $width');
      }
    });
  });

  group('DocumentBar', () {
    Future<LeafHarness> pumpBar(WidgetTester tester, PlaybackState state) async {
      final harness = LeafHarness(state: state);
      harness.attach(tester);
      tester.view.physicalSize = const Size(1200, 400);
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          const Align(alignment: Alignment.bottomCenter, child: DocumentBar()),
        ),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('PDF : les outils cèdent dans l’ordre prévu, la navigation reste', (tester) async {
      await pumpBar(tester, _pdf);

      for (final width in [...narrowWidths, 640.0, 560.0, 440.0, 400.0, 280.0]) {
        await resizeWindow(tester, Size(width, 400));
        final where = 'largeur $width';
        expect(tester.takeException(), isNull, reason: where);

        final screen = Offset.zero & Size(width, 400);
        for (final icon in [
          Icons.keyboard_arrow_up_rounded,
          Icons.keyboard_arrow_down_rounded,
          Icons.search_rounded,
        ]) {
          expect(find.byIcon(icon), findsOneWidget, reason: '$where : $icon');
          expectWithin(tester, find.byIcon(icon), screen, reason: '$where : $icon');
        }
        expect(find.byType(TextField), findsOneWidget, reason: '$where : champ de page');

        // Ce qui est caché est toujours un début de la liste de départ.
        final hidden = [for (final (_, icon) in _dropOrder) find.byIcon(icon).evaluate().isEmpty];
        final firstShown = hidden.indexOf(false);
        if (firstShown >= 0) {
          expect(hidden.skip(firstShown), everyElement(isFalse), reason: '$where : $hidden');
        }
        // Le zoom reste d'un bloc.
        expect(
          find.byIcon(Icons.add_rounded).evaluate().isEmpty,
          find.byIcon(Icons.remove_rounded).evaluate().isEmpty,
          reason: '$where : zoom',
        );
        // Le menu « ⋯ » n'existe que s'il a quelque chose à offrir.
        expect(
          find.byTooltip('Plus de commandes'),
          hidden.contains(true) ? findsOneWidget : findsNothing,
          reason: '$where : menu',
        );
      }

      // Aux largeurs d'aujourd'hui, tout est dans la barre.
      await resizeWindow(tester, const Size(1200, 400));
      expect(find.byTooltip('Plus de commandes'), findsNothing);
      for (final (name, icon) in _dropOrder) {
        expect(find.byIcon(icon), findsOneWidget, reason: name);
      }
    });

    testWidgets('le menu « ⋯ » émet sur le bus les commandes des boutons cachés', (tester) async {
      final harness = await pumpBar(tester, _pdf);
      await resizeWindow(tester, const Size(360, 400));

      await tester.tap(find.byTooltip('Plus de commandes'));
      await tester.pumpAndSettle();
      expect(find.text('Pivoter de 90°'), findsOneWidget);
      expect(find.text('Ajuster à la page'), findsOneWidget);
      expect(find.text('Mode sombre de lecture'), findsOneWidget);

      await tester.tap(find.text('Pivoter de 90°'));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<RotateDocument>(), hasLength(1));

      await tester.tap(find.byTooltip('Plus de commandes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajuster à la page'));
      await tester.pumpAndSettle();
      expect(
        harness.commands.whereType<FitZoom>().map((c) => c.mode.name),
        ['page'],
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('texte : zoom, mode sombre et recherche, sans navigation par page', (tester) async {
      await pumpBar(tester, _text);

      for (final width in narrowWidths) {
        await resizeWindow(tester, Size(width, 400));
        final where = 'largeur $width';
        expect(tester.takeException(), isNull, reason: where);
        expect(find.byIcon(Icons.search_rounded), findsOneWidget, reason: where);
        expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing, reason: where);
        expect(find.byType(TextField), findsNothing, reason: where);
      }

      await resizeWindow(tester, const Size(1200, 400));
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
      expect(find.byTooltip('Plus de commandes'), findsNothing);
    });
  });
}
