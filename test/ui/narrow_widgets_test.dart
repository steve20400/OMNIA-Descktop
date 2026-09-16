import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/resume_offer.dart';
import 'package:omnia/ui/document_search.dart';
import 'package:omnia/ui/help_overlay_controller.dart';
import 'package:omnia/ui/osd/osd_controller.dart';
import 'package:omnia/ui/osd/osd_message.dart';
import 'package:omnia/ui/settings/settings_controller.dart';
import 'package:omnia/ui/tool_panel_controller.dart';
import 'package:omnia/ui/widgets/find_bar.dart';
import 'package:omnia/ui/widgets/floating_surface.dart';
import 'package:omnia/ui/widgets/help_overlay.dart';
import 'package:omnia/ui/widgets/osd_overlay.dart';
import 'package:omnia/ui/widgets/resume_prompt.dart';
import 'package:omnia/ui/widgets/tool_panels.dart';

import 'narrow_harness.dart';

const _video = PlaybackState(
  file: MediaFile(path: '/films/Film.mkv', type: MediaType.video),
  hasVideo: true,
);

void main() {
  group('ResumePrompt', () {
    testWidgets('étroite, la question s’abrège et les boutons passent dessous', (tester) async {
      final harness = LeafHarness(
        state: const PlaybackState(
          file: MediaFile(path: '/films/Film.mkv', type: MediaType.video),
          resumeOffer: ResumeOffer(position: Duration(minutes: 12, seconds: 34)),
        ),
      );
      harness.attach(tester);
      tester.view.physicalSize = const Size(1200, 400);
      // Comme dans l'écran principal : centrée sur toute la largeur de la scène.
      await tester.pumpWidget(omniaTestApp(harness.container, const Center(child: ResumePrompt())));
      await tester.pumpAndSettle();

      for (final width in narrowWidths) {
        await resizeWindow(tester, Size(width, 400));
        final where = 'largeur $width';
        expect(tester.takeException(), isNull, reason: where);

        final screen = Offset.zero & Size(width, 400);
        final accept = find.text('Reprendre');
        final decline = find.text('Depuis le début');
        expectWithin(tester, accept, screen, reason: '$where : reprendre');
        expectWithin(tester, decline, screen, reason: '$where : depuis le début');
        expectWithin(tester, find.byType(FloatingSurface), screen, reason: '$where : pastille');

        final icon = tester.getRect(find.byIcon(Icons.history_rounded));
        if (width < ResumePrompt.compactWidth) {
          expect(tester.getRect(accept).top, greaterThan(icon.bottom), reason: '$where : boutons dessous');
        } else if (width >= 800) {
          // Assez large pour tout aligner, même avec la police des tests.
          expect(tester.getRect(accept).center.dy, closeTo(icon.center.dy, 1), reason: '$where : une ligne');
        }
      }

      // Répondre passe par le bus, à toutes les largeurs.
      await tester.tap(find.text('Reprendre'));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<AcceptResume>(), hasLength(1));
    });
  });

  group('OsdOverlay', () {
    const messages = <OsdMessage>[
      OsdFileChanged(
        name: 'Un nom de fichier vraiment très, très long pour une petite scène.mkv',
        forward: true,
      ),
      OsdScreenshot('/home/utilisateur/Images/Captures/OMNIA/Un film au nom interminable 00-12-34.png'),
      OsdScreenshotFailed(),
      OsdRecordingFailed(),
      OsdVolume(volume: 65, muted: false),
      OsdSeek(
        deltaSeconds: -10,
        position: Duration(hours: 1, minutes: 2, seconds: 3),
        duration: Duration(hours: 2),
      ),
      OsdSubtitleDelay(-2.5),
    ];

    for (final message in messages) {
      testWidgets('la pastille ${message.runtimeType} tient dans la scène', (tester) async {
        final harness = LeafHarness(
          overrides: [osdProvider.overrideWith(() => FixedOsd(message))],
        );
        harness.attach(tester);
        tester.view.physicalSize = const Size(1200, 400);
        await tester.pumpWidget(omniaTestApp(harness.container, const OsdOverlay()));
        await tester.pumpAndSettle();

        for (final width in narrowWidths) {
          await resizeWindow(tester, Size(width, 400));
          final where = 'largeur $width';
          expect(tester.takeException(), isNull, reason: where);
          final pill = find.byType(FloatingSurface);
          expect(tester.getSize(pill).width, lessThanOrEqualTo(OsdOverlay.maxPillWidth(width) + 0.5),
              reason: where);
          expectWithin(tester, pill, Offset.zero & Size(width, 400), reason: where);
        }
      });
    }
  });

  group('FindBar', () {
    testWidgets('le champ se resserre, les boutons restent à portée', (tester) async {
      final harness = LeafHarness(
        state: const PlaybackState(file: MediaFile(path: '/docs/Notes.txt', type: MediaType.text)),
      );
      harness.attach(tester);
      final search = PlainTextSearch('Une ligne avec un mot, puis un autre mot.');
      addTearDown(search.dispose);
      tester.view.physicalSize = const Size(1200, 400);
      // Comme dans l'écran principal : posée par son coin en haut à droite.
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Stack(
            children: [
              Positioned(right: 16, top: 16, child: FindBar(search: search)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final width in narrowWidths) {
        await resizeWindow(tester, Size(width, 400));
        final where = 'largeur $width';
        expect(tester.takeException(), isNull, reason: where);
        final screen = Offset.zero & Size(width, 400);
        expectWithin(tester, find.byType(FloatingSurface), screen, reason: where);
        for (final prefix in ['Résultat précédent', 'Résultat suivant', 'Fermer la recherche']) {
          expectWithin(tester, byTooltipPrefix(prefix), screen, reason: '$where : $prefix');
        }
        expect(tester.getSize(find.byType(TextField)).width, lessThanOrEqualTo(FindBar.fieldMaxWidth),
            reason: where);
      }

      // Aux largeurs d'aujourd'hui, le champ garde sa largeur pleine.
      await resizeWindow(tester, const Size(1200, 400));
      expect(tester.getSize(find.byType(TextField)).width, FindBar.fieldMaxWidth);

      // Bornée plus étroit encore que prévu, elle ne déborde toujours pas.
      for (final width in [240.0, 200.0, 150.0]) {
        await tester.pumpWidget(
          omniaTestApp(
            harness.container,
            Align(
              alignment: Alignment.topRight,
              child: SizedBox(width: width, child: FindBar(search: search)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final where = 'bornée à $width';
        expect(tester.takeException(), isNull, reason: where);
        final box = tester.getRect(find.byType(FindBar));
        expectWithin(tester, byTooltipPrefix('Fermer la recherche'), box, reason: where);
      }
    });
  });

  group('ToolPanelHost', () {
    for (final panel in [ToolPanel.image, ToolPanel.equalizer]) {
      testWidgets('le panneau ${panel.name} tient dans la place qu’on lui donne', (tester) async {
        final harness = LeafHarness(state: _video);
        harness.attach(tester);
        harness.container.read(toolPanelProvider.notifier).toggle(panel);
        tester.view.physicalSize = const Size(1200, 700);
        // Comme l'écran principal pourrait le poser : la scène moins les
        // marges et la place de la barre de contrôles, panneau en bas à droite.
        await tester.pumpWidget(
          omniaTestApp(
            harness.container,
            const Stack(
              children: [
                Positioned(
                  left: 16,
                  top: 16,
                  right: 16,
                  bottom: 112,
                  child: Align(alignment: Alignment.bottomRight, child: ToolPanelHost()),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final sizes = [
          for (final width in narrowWidths) Size(width, 700),
          const Size(360, 240),
          const Size(320, 240),
        ];
        for (final size in sizes) {
          await resizeWindow(tester, size);
          final where = 'fenêtre $size';
          expect(tester.takeException(), isNull, reason: where);

          final space = Rect.fromLTRB(16, 16, size.width - 16, size.height - 112);
          final surface = find.byType(FloatingSurface);
          expectWithin(tester, surface, space, reason: where);
          expect(tester.getSize(surface).width, lessThanOrEqualTo(ToolPanelHost.maxWidth), reason: where);
          // Le bouton de fermeture est dans le panneau, en haut : toujours visible.
          expectWithin(tester, find.byTooltip('Fermer'), space, reason: '$where : fermer');
        }

        if (panel == ToolPanel.equalizer) {
          // Dix bandes trop larges pour une petite fenêtre : elles défilent.
          await resizeWindow(tester, const Size(320, 700));
          expect(find.byType(Scrollbar), findsOneWidget);
          await resizeWindow(tester, const Size(1200, 700));
          expect(find.byType(Scrollbar), findsNothing);
        }
      });
    }

    testWidgets('posé par un seul coin, comme aujourd’hui, il reste dans la fenêtre', (tester) async {
      final harness = LeafHarness(state: _video);
      harness.attach(tester);
      harness.container.read(toolPanelProvider.notifier).toggle(ToolPanel.equalizer);
      tester.view.physicalSize = const Size(360, 240);
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          const Stack(
            children: [Positioned(right: 16, bottom: 112, child: ToolPanelHost())],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectWithin(tester, find.byType(FloatingSurface), Offset.zero & const Size(360, 240));
    });
  });

  group('HelpOverlay', () {
    testWidgets('la carte tient et défile, sa fermeture toujours à portée', (tester) async {
      final harness = LeafHarness();
      harness.attach(tester);
      harness.container.read(helpVisibleProvider.notifier).toggle();
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpWidget(omniaTestApp(harness.container, const HelpOverlay()));
      await tester.pumpAndSettle();

      final sizes = [
        for (final width in narrowWidths) Size(width, 800),
        const Size(1200, 400),
        const Size(800, 300),
        const Size(360, 240),
        const Size(320, 240),
      ];
      for (final size in sizes) {
        await resizeWindow(tester, size);
        final where = 'fenêtre $size';
        expect(tester.takeException(), isNull, reason: where);
        final screen = Offset.zero & size;
        expectWithin(tester, find.byType(FloatingSurface), screen, reason: where);
        expectWithin(tester, byTooltipPrefix('Fermer l\'aide'), screen, reason: '$where : fermer');
        expect(find.text('Raccourcis clavier'), findsOneWidget, reason: where);
      }

      // Même compacte, la carte mène aux raccourcis des paramètres.
      await tester.tap(find.byTooltip('Raccourcis'));
      await tester.pumpAndSettle();
      final settings = harness.container.read(settingsUiProvider);
      expect(settings.visible, isTrue);
      expect(settings.section, SettingsSection.shortcuts);
      expect(harness.container.read(helpVisibleProvider), isFalse);
    });
  });
}
