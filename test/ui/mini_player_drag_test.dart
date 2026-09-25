// Déplacement de la fenêtre depuis le mini-lecteur.
//
// Le geste ne peut pas être joué en vrai (il n'y a pas de fenêtre native sous
// un test), mais tout ce qui le précède se vérifie : où la pression arrive,
// ce qui la prend au passage, et si le départ du déplacement est demandé —
// une fois, et une seule, par pression.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/services/audio_metadata_service.dart';
import 'package:omnia/ui/audio_tags_provider.dart';
import 'package:omnia/ui/widgets/mini_player.dart';
import 'package:omnia/ui/widgets/stage.dart';
import 'package:omnia/ui/widgets/window_drag_area.dart';

import 'narrow_harness.dart';

const _video = PlaybackState(
  file: MediaFile(path: '/films/Film.mkv', type: MediaType.video),
  hasVideo: true,
  duration: Duration(minutes: 4),
  position: Duration(minutes: 1),
);

const _audio = PlaybackState(
  file: MediaFile(path: '/musique/Piste.mp3', type: MediaType.audio),
  duration: Duration(minutes: 4),
  position: Duration(minutes: 1),
);

/// Surface vidéo de test : un aplat, sans libmpv derrière.
Widget _flatSurface(BuildContext context, {required BoxFit fit, double? aspectRatio}) =>
    const SizedBox.expand(child: ColoredBox(color: Color(0xFF101010)));

/// Tags connus d'avance : aucun fichier n'est lu.
class _FixedTags extends AudioTagsNotifier {
  @override
  AudioTags? build() => const AudioTags(title: 'Titre', artist: 'Artiste');
}

/// Le mini-lecteur monté, avec le compte des déplacements demandés au système
/// et les commandes émises.
class _Mini {
  late final LeafHarness harness;

  /// Nombre d'appels à [startWindowDragProvider] : autant de glissements
  /// confiés au système.
  int drags = 0;

  Rect bounds = Rect.zero;

  void recordDrag() => drags++;

  List<PlayerCommand> get commands => harness.commands;

  /// Point du mini-lecteur situé à [offset] de son coin haut-gauche.
  Offset at(Offset offset) => bounds.topLeft + offset;
}

/// Monte le mini-lecteur en 480 × 270 au centre d'une fenêtre de 800 × 600.
Future<_Mini> _pumpMini(WidgetTester tester, PlaybackState state) async {
  final mini = _Mini();
  mini.harness = LeafHarness(
    state: state,
    overrides: [
      videoSurfaceProvider.overrideWithValue(_flatSurface),
      audioTagsProvider.overrideWith(_FixedTags.new),
      startWindowDragProvider.overrideWithValue(mini.recordDrag),
    ],
  );
  mini.harness.attach(tester);
  tester.view.physicalSize = const Size(800, 600);
  await tester.pumpWidget(
    omniaTestApp(
      mini.harness.container,
      const Center(child: SizedBox(width: 480, height: 270, child: MiniPlayer())),
    ),
  );
  await tester.pumpAndSettle();
  mini.bounds = tester.getRect(find.byType(MiniPlayer));
  return mini;
}

/// Laisse expirer le délai du double-clic : sans cela, le minuteur qu'il arme
/// à chaque relâchement survivrait au test.
Future<void> _settleTaps(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));

/// Pression à [at], mouvement de [by] bouton enfoncé, puis relâchement.
Future<void> _pressAndMove(
  WidgetTester tester,
  Offset at, {
  Offset by = const Offset(8, 6),
}) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await gesture.moveBy(by);
  await tester.pump();
  await gesture.up();
  await _settleTaps(tester);
}

void main() {
  group('Mini-lecteur vidéo', () {
    testWidgets('une pression suivie d’un mouvement sur l’image déplace la fenêtre',
        (tester) async {
      final mini = await _pumpMini(tester, _video);

      // À mi-hauteur, à gauche : l'image, loin de la plaque des commandes.
      await _pressAndMove(tester, mini.at(const Offset(60, 135)));

      expect(mini.drags, 1);
    });

    testWidgets('le voile des commandes laisse passer le déplacement', (tester) async {
      final mini = await _pumpMini(tester, _video);

      // Le dégradé du haut, là où se trouve le pointeur quand les commandes
      // viennent d'apparaître : il ne doit rien prendre au passage.
      await _pressAndMove(tester, mini.at(const Offset(24, 20)));

      expect(mini.drags, 1);
    });

    testWidgets('une pression sur une commande ne déplace pas la fenêtre', (tester) async {
      final mini = await _pumpMini(tester, _video);

      await _pressAndMove(
        tester,
        tester.getCenter(find.byIcon(Icons.play_arrow_rounded)),
        by: const Offset(30, 0),
      );

      expect(mini.drags, 0);
    });

    testWidgets('le déplacement ne part qu’une fois par pression', (tester) async {
      final mini = await _pumpMini(tester, _video);

      final gesture = await tester.startGesture(
        mini.at(const Offset(60, 135)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(6, 0));
        await tester.pump();
      }
      await gesture.up();
      await _settleTaps(tester);

      expect(mini.drags, 1);
    });

    testWidgets('un relâchement perdu n’empêche pas le déplacement suivant', (tester) async {
      final mini = await _pumpMini(tester, _video);
      final point = mini.at(const Offset(60, 135));

      // Pendant qu'il déplace la fenêtre, le système garde la souris : Flutter
      // ne voit jamais le bouton relâché. C'est ce qui condamnait le
      // déplacement pour le reste de la session avec un détecteur de « pan »,
      // bloqué pour de bon dans son état « accepté ».
      final lost = await tester.startGesture(point, pointer: 1, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await lost.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(mini.drags, 1);

      final next = await tester.startGesture(point, pointer: 2, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await next.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(mini.drags, 2, reason: 'la fenêtre se déplace encore');

      await next.up();
      await lost.up();
      await _settleTaps(tester);
    });

    testWidgets('un clic lance la lecture, un double-clic rend la fenêtre entière',
        (tester) async {
      final mini = await _pumpMini(tester, _video);
      final point = mini.at(const Offset(60, 135));

      await tester.tapAt(point);
      // Le double-clic retient le clic simple le temps de son délai.
      await _settleTaps(tester);
      expect(mini.commands.whereType<TogglePlay>(), hasLength(1));
      expect(mini.drags, 0, reason: 'un clic ne déplace pas la fenêtre');

      mini.commands.clear();
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await _settleTaps(tester);
      expect(mini.commands.whereType<ToggleMiniPlayer>(), hasLength(1));
      expect(mini.commands.whereType<TogglePlay>(), isEmpty);
      expect(mini.drags, 0);
    });
  });

  group('Mini-lecteur audio', () {
    testWidgets('le bandeau se déplace par la pochette, le titre et les marges',
        (tester) async {
      final mini = await _pumpMini(tester, _audio);

      // La pochette (carrée, à gauche), le titre, puis une marge au-dessus :
      // rien de tout cela n'est une commande.
      final points = <Offset>[
        mini.at(const Offset(60, 135)),
        tester.getCenter(find.text('Titre')),
        mini.at(const Offset(200, 20)),
      ];
      for (final point in points) {
        final before = mini.drags;
        await _pressAndMove(tester, point);
        expect(mini.drags, before + 1, reason: 'saisi en $point');
      }
    });

    testWidgets('une pression sur une commande du bandeau ne déplace pas la fenêtre',
        (tester) async {
      final mini = await _pumpMini(tester, _audio);

      await _pressAndMove(
        tester,
        tester.getCenter(find.byIcon(Icons.play_arrow_rounded)),
        by: const Offset(30, 0),
      );

      expect(mini.drags, 0);
    });
  });
}
