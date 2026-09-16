// Barre de lecture et boutons texte dans les fenêtres étroites : la rangée de
// commandes doit tenir dans la surface flottante, bordure comprise, et un
// libellé trop long doit s'abréger au lieu de faire déborder son bouton.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/models/track_info.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';
import 'package:omnia/ui/widgets/beam_progress_bar.dart';
import 'package:omnia/ui/widgets/control_bar.dart';
import 'package:omnia/ui/widgets/floating_surface.dart';
import 'package:omnia/ui/widgets/omnia_button.dart';

import 'narrow_harness.dart';

/// Un film en cours de lecture, dans un dossier de plusieurs fichiers : toutes
/// les commandes de la barre existent (extrait, sous-titres, pistes audio).
const _video = PlaybackState(
  file: MediaFile(path: '/films/Un très long titre de film.mkv', type: MediaType.video),
  status: PlaybackStatus.playing,
  hasVideo: true,
  position: Duration(minutes: 12, seconds: 34),
  duration: Duration(hours: 1, minutes: 45),
  audioTracks: [
    TrackInfo(id: '1', language: 'fre'),
    TrackInfo(id: '2', language: 'eng'),
  ],
  playlist: ['/films/Un très long titre de film.mkv', '/films/Le suivant.mkv'],
  playlistIndex: 0,
);

void main() {
  group('ControlBar', () {
    Future<LeafHarness> pumpBar(WidgetTester tester) async {
      final harness = LeafHarness(state: _video);
      harness.attach(tester);
      tester.view.physicalSize = const Size(1200, 400);
      // Comme dans l'écran principal : posée en bas, sur toute la largeur.
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          const Align(alignment: Alignment.bottomCenter, child: ControlBar()),
        ),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('à toutes les largeurs, la barre tient dans la scène', (tester) async {
      await pumpBar(tester);

      for (final width in narrowWidths) {
        await resizeWindow(tester, Size(width, 400));
        final where = 'largeur $width';
        expect(tester.takeException(), isNull, reason: where);

        final screen = Offset.zero & Size(width, 400);
        final surface = find.byType(FloatingSurface);
        expectWithin(tester, surface, screen, reason: '$where : barre');
        expect(find.byType(BeamProgressBar), findsOneWidget, reason: '$where : faisceau');

        // Lecture / pause ne cède jamais sa place (priorité 0).
        final play = find.byIcon(Icons.pause_rounded);
        expect(play, findsOneWidget, reason: '$where : lecture');
        expectWithin(tester, play, screen, reason: '$where : lecture');

        // La dernière commande de la rangée reste dans la surface, marge
        // intérieure et bordure comprises : c'est ce que mesure la barre.
        final overflow = find.byTooltip('Plus de commandes');
        final last = overflow.evaluate().isEmpty
            ? find.byIcon(Icons.fullscreen_rounded)
            : overflow;
        if (last.evaluate().isNotEmpty) {
          const inset = OmniaMetrics.controlBarPadding + 1; // marge + bordure
          final box = tester.getRect(surface);
          expectWithin(
            tester,
            last,
            Rect.fromLTRB(box.left + inset, box.top, box.right - inset, box.bottom),
            reason: '$where : dernière commande',
          );
        }
      }

      // Étroite, la barre range le reste dans le menu « ⋯ » ; large, non.
      await resizeWindow(tester, const Size(360, 400));
      expect(find.byTooltip('Plus de commandes'), findsOneWidget);
      await resizeWindow(tester, const Size(1200, 400));
      expect(find.byTooltip('Plus de commandes'), findsNothing);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });

    testWidgets('aucune largeur ne fait déborder la rangée d’un pixel', (tester) async {
      await pumpBar(tester);

      // La place des commandes, c'est la largeur de la barre moins sa marge
      // intérieure ET sa bordure : au pixel où une commande vient tout juste
      // de tenir, l'oubli de la bordure faisait déborder la rangée.
      for (var width = 300.0; width <= 640.0; width += 1) {
        tester.view.physicalSize = Size(width, 400);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'largeur $width');
      }
      await tester.pumpAndSettle();
    });
  });

  group('OmniaButton', () {
    testWidgets('un libellé trop long s’abrège au lieu de déborder', (tester) async {
      final harness = LeafHarness();
      harness.attach(tester);
      tester.view.physicalSize = const Size(400, 200);

      const label = 'Rétablir tous les raccourcis clavier par défaut';
      var tapped = false;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Center(
            child: SizedBox(
              width: 120,
              child: OmniaButton(
                label: label,
                icon: Icons.restart_alt_rounded,
                onPressed: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(OmniaButton)).width, 120);
      expect(tester.widget<Text>(find.text(label)).overflow, TextOverflow.ellipsis);
      // L'icône reste, et le bouton reste cliquable.
      expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
      await tester.tap(find.byType(OmniaButton));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('avec la place, il garde sa largeur naturelle', (tester) async {
      final harness = LeafHarness();
      harness.attach(tester);
      tester.view.physicalSize = const Size(800, 200);

      const label = 'Rétablir tous les raccourcis clavier par défaut';
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Center(
            child: OmniaButton(
              label: label,
              icon: Icons.restart_alt_rounded,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Le libellé n'est pas rogné : les mesures de largeur des autres écrans
      // (invite de reprise, paramètres) comptent là-dessus.
      final button = tester.getSize(find.byType(OmniaButton)).width;
      final text = tester.getSize(find.text(label)).width;
      expect(button, greaterThan(120));
      expect(button, greaterThan(text));
    });
  });
}
