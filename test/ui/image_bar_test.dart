import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/document_layout.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/ui/widgets/image_bar.dart';

import 'narrow_harness.dart';

const _image = PlaybackState(
  file: MediaFile(path: '/images/photo.jpg', type: MediaType.image),
  zoom: 1.0,
);

void main() {
  group('ImageBar', () {
    Future<LeafHarness> pumpBar(WidgetTester tester, [PlaybackState state = _image]) async {
      final harness = LeafHarness(state: state);
      harness.attach(tester);
      tester.view.physicalSize = const Size(1200, 400);
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          const Align(alignment: Alignment.bottomCenter, child: ImageBar()),
        ),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('affiche les contrôles de zoom, rotation, navigation et plein écran', (tester) async {
      await pumpBar(tester);

      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
      expect(find.text('100 %'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fit_screen_outlined), findsOneWidget);
      expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.picture_in_picture_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });

    testWidgets('les boutons émettent les commandes attendues sur le bus', (tester) async {
      final harness = await pumpBar(tester);

      // Mini-lecteur
      await tester.tap(find.byIcon(Icons.picture_in_picture_alt_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ToggleMiniPlayer>(), hasLength(1));

      // Zoom out
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ZoomRelative>().last.factor, closeTo(1 / 1.25, 0.001));

      // Zoom in
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ZoomRelative>().last.factor, closeTo(1.25, 0.001));

      // Reset zoom to 100%
      await tester.tap(find.text('100 %'));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<SetZoom>().last.zoom, 1.0);

      // Fit to window
      await tester.tap(find.byIcon(Icons.fit_screen_outlined));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<FitZoom>().last.mode, FitMode.width);

      // Rotate 90
      await tester.tap(find.byIcon(Icons.rotate_right_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<RotateDocument>().last.quarterTurns, 1);

      // Previous / Next
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<PreviousFile>(), hasLength(1));

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<NextFile>(), hasLength(1));

      // Fullscreen
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ToggleFullscreen>(), hasLength(1));
    });
  });
}
