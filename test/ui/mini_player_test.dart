import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playlist_entry.dart';
import 'package:omnia/core/models/playlist_sort.dart';
import 'package:omnia/core/models/playlist_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/widgets/mini_player.dart';
import 'package:omnia/ui/widgets/stage.dart';

import 'narrow_harness.dart';

class _FixedPlaylistNotifier extends PlaylistStateNotifier {
  _FixedPlaylistNotifier(this._initial);

  final PlaylistState _initial;

  @override
  PlaylistState build() => _initial;
}

void main() {
  group('MiniPlayer', () {
    Future<LeafHarness> pumpMini(
      WidgetTester tester, {
      PlaybackState state = const PlaybackState(),
      PlaylistState? playlist,
      Size size = const Size(360, 240),
    }) async {
      final initialPlaylist = playlist ??
          PlaylistState(
            folder: '/media',
            entries: [
              const PlaylistEntry(file: MediaFile(path: '/media/video.mp4', type: MediaType.video)),
              const PlaylistEntry(file: MediaFile(path: '/media/song.mp3', type: MediaType.audio)),
              const PlaylistEntry(file: MediaFile(path: '/media/photo.jpg', type: MediaType.image)),
              const PlaylistEntry(file: MediaFile(path: '/media/book.pdf', type: MediaType.pdf)),
            ],
          );

      final harness = LeafHarness(
        state: state,
        overrides: [
          playlistStateProvider.overrideWith(() => _FixedPlaylistNotifier(initialPlaylist)),
          videoSurfaceProvider.overrideWithValue(
            (context, {required fit, aspectRatio}) => const ColoredBox(color: Colors.black),
          ),
        ],
      );
      harness.attach(tester);
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          const Align(alignment: Alignment.center, child: MiniPlayer()),
        ),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('mode image : affiche les contrôles de zoom, rotation et sortie', (tester) async {
      final harness = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/images/photo.png', type: MediaType.image),
          miniPlayer: true,
        ),
      );

      // Icônes attendues pour l'image
      expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fit_screen_outlined), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);

      // Clic sur sortie mini-lecteur
      await tester.tap(find.byIcon(Icons.open_in_full_rounded));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ToggleMiniPlayer>(), hasLength(1));
    });

    testWidgets('mode audio : affiche le bandeau et le bouton de liste de lecture', (tester) async {
      await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/music/track.mp3', type: MediaType.audio),
          miniPlayer: true,
        ),
        size: const Size(360, 110),
      );

      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);

      // Clic sur le bouton de liste de lecture pour ouvrir le tiroir
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      // Le tiroir s'affiche avec son bouton de fermeture
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('tiroir inférieur de liste de lecture coulissant', (tester) async {
      final harness = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
          hasVideo: true,
          miniPlayer: true,
        ),
      );

      // Au départ le tiroir n'est pas affiché
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // Déclenchement de l'ouverture du tiroir via le bouton playlist
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      // Le tiroir inférieur est visible avec les filtres
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('Images'), findsOneWidget);
      expect(find.text('Tout'), findsOneWidget);

      // Clic sur le filtre Images
      await tester.tap(find.text('Images'));
      await tester.pumpAndSettle();
      expect(
        harness.commands.whereType<SetPlaylistFilter>().last.filter,
        PlaylistFilter.images,
      );

      // Fermeture du tiroir
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });
  });
}
