import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/models/playlist_entry.dart';
import 'package:omnia/core/models/playlist_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/widgets/mini_player.dart';
import 'package:omnia/ui/widgets/stage.dart';
import 'package:omnia/ui/widgets/window_drag_area.dart';

import 'narrow_harness.dart';

/// Une liste figée : sans elle, l'écran construit la vraie liste de lecture,
/// qui réveille le moteur média — absent d'un test.
class _FixedPlaylist extends PlaylistStateNotifier {
  @override
  PlaylistState build() => PlaylistState(
        folder: '/media',
        entries: const [
          PlaylistEntry(file: MediaFile(path: '/media/video.mp4', type: MediaType.video)),
        ],
        currentPath: '/media/video.mp4',
      );
}

void main() {
  group('Mini-lecteur : le clavier survit à un déplacement de fenêtre', () {
    const playing = PlaybackState(
      file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
      status: PlaybackStatus.playing,
      hasVideo: true,
      videoWidth: 1920,
      videoHeight: 1080,
      miniPlayer: true,
      duration: Duration(minutes: 20),
    );

    testWidgets('une pression rend le focus, même quand le clic devient un glissement',
        (tester) async {
      var dragStarted = 0;
      final harness = LeafHarness(
        state: playing,
        overrides: [
          // Sans cela, le glissement appellerait la vraie fenêtre native.
          startWindowDragProvider.overrideWithValue(() => dragStarted++),
          playlistStateProvider.overrideWith(_FixedPlaylist.new),
          videoSurfaceProvider.overrideWithValue(
            (context, {required fit, aspectRatio}) =>
                const ColoredBox(color: Colors.black),
          ),
        ],
      );
      harness.attach(tester);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 240);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ailleurs = FocusNode(debugLabel: 'ailleurs');
      addTearDown(ailleurs.dispose);

      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Stack(
            children: [
              const Positioned.fill(child: MiniPlayer()),
              Positioned(
                left: 0,
                top: 0,
                child: Focus(
                  focusNode: ailleurs,
                  child: const SizedBox(width: 1, height: 1),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Le focus part ailleurs : c'est ce que fait l'ouverture d'un menu, ou
      // le système qui prend la main pendant un déplacement de fenêtre.
      ailleurs.requestFocus();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, ailleurs);

      // Une pression qui devient un glissement : le clic est abandonné, et
      // c'est précisément le cas où le focus n'était jamais redemandé.
      final centre = tester.getCenter(find.byType(MiniPlayer));
      final geste = await tester.startGesture(centre);
      await geste.moveBy(const Offset(40, 0));
      await tester.pump();
      await geste.up();
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'omnia.mini',
        reason: 'le mini-lecteur doit reprendre le focus à la pression',
      );

      // Et le clavier répond de nouveau : Tab ouvre le panneau. Sans focus,
      // cette touche ne parvenait nulle part, et la fenêtre semblait figée
      // alors que la molette continuait de défiler.
      harness.commands.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ToggleSidePanel>(), isNotEmpty);
    });
  });
}
