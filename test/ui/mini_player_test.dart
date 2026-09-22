import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/document_layout.dart';
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
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
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

      // Le tiroir s'affiche avec son chevron de repli vers le bas
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
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
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);

      // Déclenchement de l'ouverture du tiroir via le bouton playlist
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      // Le tiroir inférieur est visible avec les filtres
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Vidéo'), findsOneWidget);

      // Clic sur le filtre Vidéo
      await tester.tap(find.text('Vidéo'));
      await tester.pumpAndSettle();
      expect(
        harness.commands.whereType<SetPlaylistFilter>().last.filter,
        PlaylistFilter.video,
      );

      // Fermeture du tiroir
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    });

    testWidgets('bouton de fermeture directe de l\'application en mode mini-lecteur', (tester) async {
      final harness = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
          hasVideo: true,
          miniPlayer: true,
        ),
      );

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(harness.window.closed, isTrue);
    });

    testWidgets('mode compact (< 520px) : la playlist se déroule en dessous avec chevron bas et vidéo préservée', (tester) async {
      await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
          hasVideo: true,
          miniPlayer: true,
        ),
        size: const Size(400, 240),
      );

      // Déclenchement de l'ouverture
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      // En mode compact : chevron bas et liste déroulée en dessous
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(find.byType(ColoredBox), findsWidgets);
    });

    testWidgets('mode large (>= 520px) : la barre latérale s\'affiche à gauche et le filtre Images est visible', (tester) async {
      await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
          hasVideo: true,
          miniPlayer: true,
        ),
        size: const Size(600, 300),
      );

      // Au départ, pas de panneau
      expect(find.byIcon(Icons.keyboard_double_arrow_left_rounded), findsNothing);

      // Ouverture
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      // Panneau gauche affiché avec son bouton de repli à gauche et tous les filtres dont Images
      expect(find.byIcon(Icons.keyboard_double_arrow_left_rounded), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Images'), findsOneWidget);

      // Fermeture
      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_double_arrow_left_rounded), findsNothing);
    });

    testWidgets('mode document PDF : la vue est non-bloquante pour permettre le déplacement de la fenêtre', (tester) async {
      await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/docs/document.pdf', type: MediaType.pdf),
          miniPlayer: true,
        ),
      );

      expect(find.byType(IgnorePointer), findsWidgets);
    });

    testWidgets('mode document PDF : la molette déclenche ScrollDocument en continu et NextPage en page par page', (tester) async {
      final harnessContinuous = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/docs/document.pdf', type: MediaType.pdf),
          documentLayout: DocumentLayout.continuous,
          miniPlayer: true,
        ),
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pumpAndSettle();
      expect(harnessContinuous.commands.whereType<ScrollDocument>(), hasLength(1));

      final harnessPaged = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/docs/document.pdf', type: MediaType.pdf),
          documentLayout: DocumentLayout.paged,
          miniPlayer: true,
        ),
      );

      await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pumpAndSettle();
      expect(harnessPaged.commands.whereType<NextPage>(), hasLength(1));
    });

    testWidgets('mode image : la vue est enveloppée dans IgnorePointer et la molette zoome', (tester) async {
      final harness = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/images/photo.png', type: MediaType.image),
          miniPlayer: true,
        ),
      );

      expect(find.byType(IgnorePointer), findsWidgets);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ZoomRelative>(), hasLength(1));
    });

    testWidgets('défilement sur la liste de lecture : n\'altère ni le zoom ni la page du média', (tester) async {
      final harness = await pumpMini(
        tester,
        size: const Size(600, 300),
        state: const PlaybackState(
          file: MediaFile(path: '/images/photo.png', type: MediaType.image),
          miniPlayer: true,
        ),
      );

      // Ouvrir le volet de liste de lecture (en mode large >= 480px, affiché à gauche)
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Dossier'), findsOneWidget);

      // Molette au-dessus de la liste de lecture (à gauche, ex: x=50, y=100)
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(50, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pumpAndSettle();

      // Aucun ZoomRelative ne doit avoir été déclenché par le défilement du volet !
      expect(harness.commands.whereType<ZoomRelative>(), isEmpty);

      // En revanche, molette au-dessus de l'image (à droite, ex: x=400, y=100) déclenche bien le zoom
      await tester.sendEventToBinding(pointer.hover(const Offset(400, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ZoomRelative>(), hasLength(1));
    });

    testWidgets('mode document texte : la vue est non-bloquante et la molette fait défiler', (tester) async {
      final harness = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/docs/notes.txt', type: MediaType.text),
          miniPlayer: true,
        ),
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(100, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ScrollTo>(), hasLength(1));
    });

    testWidgets('redimensionnement du volet latéral en mode mini-lecteur large', (tester) async {
      await pumpMini(
        tester,
        size: const Size(600, 300),
        state: const PlaybackState(
          file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
          hasVideo: true,
          miniPlayer: true,
        ),
      );

      // Ouvrir le volet
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      // La poignée de redimensionnement horizontal est présente
      final handleFinder = find.byTooltip('Redimensionner le panneau');
      expect(handleFinder, findsOneWidget);

      // Glisser la poignée vers la droite (+50px)
      await tester.drag(handleFinder, const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    testWidgets('redimensionnement vertical de la liste en mode mini-lecteur compact', (tester) async {
      await pumpMini(
        tester,
        size: const Size(360, 240),
        state: const PlaybackState(
          file: MediaFile(path: '/media/video.mp4', type: MediaType.video),
          hasVideo: true,
          miniPlayer: true,
        ),
      );

      // Ouvrir le déroulé inférieur
      await tester.tap(find.byIcon(Icons.playlist_play_rounded));
      await tester.pumpAndSettle();

      final handleFinder = find.byTooltip('Redimensionner le panneau');
      expect(handleFinder, findsOneWidget);

      // Glisser la poignée verticalement
      await tester.drag(handleFinder, const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    testWidgets('sur un PDF, les touches fléchées haut et bas naviguent dans le document et jamais Volume', (tester) async {
      final harness = await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/docs/document.pdf', type: MediaType.pdf),
          documentLayout: DocumentLayout.continuous,
          miniPlayer: true,
        ),
      );

      // Appui sur flèche bas (descendre)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ScrollDocument>(), hasLength(1));
      expect(harness.commands.whereType<VolumeRelative>(), isEmpty);

      // Appui sur flèche haut (monter)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(harness.commands.whereType<ScrollDocument>(), hasLength(2));
      expect(harness.commands.whereType<VolumeRelative>(), isEmpty);
    });

    testWidgets('mode document texte : le bouton modifier est présent en mini-lecteur et bascule en édition', (tester) async {
      await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/docs/notes.txt', type: MediaType.text),
          miniPlayer: true,
        ),
      );

      // Bouton modifier présent
      final editButton = find.byTooltip('Modifier le document');
      expect(editButton, findsOneWidget);

      // Clic pour passer en mode édition
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      // En mode édition, les boutons enregistrer et lecture seule sont affichés
      expect(find.byTooltip('Enregistrer les modifications'), findsOneWidget);
      expect(find.byTooltip('Terminer la modification (Lecture seule)'), findsOneWidget);
    });

    testWidgets('mode image : le bouton de retouche est présent et le menu 3 points s\'affiche en mode compact', (tester) async {
      await pumpMini(
        tester,
        state: const PlaybackState(
          file: MediaFile(path: '/images/photo.png', type: MediaType.image),
          miniPlayer: true,
        ),
        size: const Size(320, 220),
      );

      // En mode compact (< 360px), le menu 3 points est présent
      expect(find.byTooltip('Plus d’actions'), findsOneWidget);
      expect(find.byTooltip('Retoucher l’image'), findsOneWidget);

      // Clic sur le menu 3 points pour afficher les options cachées
      await tester.tap(find.byTooltip('Plus d’actions'));
      await tester.pumpAndSettle();

      expect(find.text('Pivoter de 90°'), findsOneWidget);
      expect(find.text('Ajuster à la fenêtre'), findsOneWidget);
    });
  });
}
