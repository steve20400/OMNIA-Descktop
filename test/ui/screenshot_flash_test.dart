// L'éclair de capture : la scène blanchit un instant quand une image est
// enregistrée, puis revient comme avant.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/widgets/screenshot_flash.dart';

import 'narrow_harness.dart';

/// État de lecture où l'on peut annoncer une capture, comme le ferait le
/// service après avoir écrit le fichier.
class _Captures extends PlaybackStateNotifier {
  @override
  PlaybackState build() => const PlaybackState();

  void capture(String path) => state = state.copyWith(lastScreenshot: path);
}

void main() {
  testWidgets('une capture fait blanchir la scène, puis s’efface', (tester) async {
    final container = ProviderContainer(
      overrides: [playbackStateProvider.overrideWith(_Captures.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      omniaTestApp(container, const SizedBox.expand(child: ScreenshotFlash())),
    );
    await tester.pumpAndSettle();

    // Celui de l'éclair : l'application en pose d'autres pour ses transitions.
    double voile() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(ScreenshotFlash),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    expect(voile(), 0, reason: 'au repos, rien ne couvre la scène');

    (container.read(playbackStateProvider.notifier) as _Captures)
        .capture('/captures/image 1.png');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(voile(), greaterThan(0.25), reason: 'le déclic se voit');

    await tester.pump(ScreenshotFlash.duration);
    expect(voile(), lessThan(0.05), reason: 'et ne s’attarde pas');
  });

  testWidgets('deux captures de suite donnent deux éclairs', (tester) async {
    final container = ProviderContainer(
      overrides: [playbackStateProvider.overrideWith(_Captures.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      omniaTestApp(container, const SizedBox.expand(child: ScreenshotFlash())),
    );
    await tester.pumpAndSettle();

    // Celui de l'éclair : l'application en pose d'autres pour ses transitions.
    double voile() => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(ScreenshotFlash),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    final notifier = container.read(playbackStateProvider.notifier) as _Captures;
    notifier.capture('/captures/image 1.png');
    await tester.pump();
    await tester.pump(ScreenshotFlash.duration);
    expect(voile(), lessThan(0.05));

    // Chaque fichier porte un nom différent : le second éclair repart.
    notifier.capture('/captures/image 2.png');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(voile(), greaterThan(0.25));
    await tester.pump(ScreenshotFlash.duration);
  });
}
