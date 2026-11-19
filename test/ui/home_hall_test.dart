import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/history_entry.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/ui/home/hall_library.dart';
import 'package:omnia/ui/home/hall_model.dart';
import 'package:omnia/ui/home/home_hall.dart';
import 'package:omnia/ui/recent_files.dart';
import 'package:omnia/ui/widgets/omnia_button.dart';

import 'narrow_harness.dart';

/// Quatre séances : un film entamé, un album, un PDF lu à la page 12, et un
/// fichier disparu depuis.
class _Recents extends RecentFilesNotifier {
  @override
  List<RecentFile> build() {
    final now = DateTime.now();
    return [
      RecentFile(
        entry: HistoryEntry(
          path: '/films/Dune.Part.Two.2024.mkv',
          position: const Duration(hours: 1, minutes: 12, seconds: 5),
          duration: const Duration(hours: 2, minutes: 46),
          lastOpened: now,
        ),
        exists: true,
      ),
      RecentFile(
        entry: HistoryEntry(
          path: '/musique/Random Access Memories.flac',
          position: Duration.zero,
          duration: const Duration(minutes: 74),
          lastOpened: now.subtract(const Duration(hours: 1)),
        ),
        exists: true,
      ),
      RecentFile(
        entry: HistoryEntry(
          path: '/docs/rapport.pdf',
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: now.subtract(const Duration(hours: 2)),
          page: 12,
          pageCount: 140,
        ),
        exists: true,
      ),
      RecentFile(
        entry: HistoryEntry(
          path: '/films/disparu.mp4',
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: now.subtract(const Duration(days: 1)),
        ),
        exists: false,
      ),
    ];
  }
}

/// Le hall, avec le clavier de l'accueil branché comme dans l'écran
/// principal.
Widget _hallWithKeys() => Consumer(
      builder: (context, ref, _) => Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          return handleHallKey(event, ref) ? KeyEventResult.handled : KeyEventResult.ignored;
        },
        child: const HomeHall(),
      ),
    );

Future<LeafHarness> _mount(
  WidgetTester tester, {
  bool withRecents = true,
  Size size = const Size(1200, 760),
  List<MediaFile> library = const [],
}) async {
  final harness = LeafHarness(
    overrides: [
      if (withRecents) recentFilesProvider.overrideWith(_Recents.new),
      userLibraryProvider.overrideWith((ref) async => library),
    ],
  );
  harness.attach(tester);
  tester.view.physicalSize = size;
  await tester.pumpWidget(omniaTestApp(harness.container, _hallWithKeys()));
  await tester.pumpAndSettle();
  return harness;
}

List<String> _opened(LeafHarness harness) =>
    [for (final c in harness.commands) if (c is OpenFile) c.path];

void main() {
  group('Le hall', () {
    testWidgets('la séance sélectionnée, ses affiches, et de quoi ouvrir', (tester) async {
      await _mount(tester);

      // Le titre en grand et sous l'affiche, sans les points du nom de fichier.
      expect(find.text('Dune Part Two 2024'), findsNWidgets(2));
      expect(find.text('Reprise à 1:12:05 sur 2:46:00'), findsOneWidget);
      expect(find.widgetWithText(OmniaButton, 'Reprendre'), findsOneWidget);
      expect(find.byType(HallPoster), findsNWidgets(4));

      for (final rayon in HallCategory.values) {
        expect(find.text(rayon.label), findsOneWidget, reason: rayon.label);
      }
      // Les deux boutons d'ouverture restent sur l'accueil.
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un fichier'), findsOneWidget);
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un dossier'), findsOneWidget);
    });

    testWidgets('← → parcourent les affiches, Entrée ouvre la sélection', (tester) async {
      final harness = await _mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Random Access Memories'), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_opened(harness), ['/musique/Random Access Memories.flac']);

      // Au bord, la sélection s'arrête au lieu de boucler.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Dune Part Two 2024'), findsNWidgets(2));

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(find.text('Fichier introuvable'), findsOneWidget);
    });

    testWidgets('un fichier disparu ne s’ouvre pas', (tester) async {
      final harness = await _mount(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.byType(HallPoster).last);
      await tester.pump();

      expect(_opened(harness), isEmpty);
    });

    testWidgets('un clic sur une affiche l’ouvre', (tester) async {
      final harness = await _mount(tester);

      await tester.tap(find.byType(HallPoster).at(2));
      await tester.pump();

      expect(_opened(harness), ['/docs/rapport.pdf']);
    });

    testWidgets('un rayon ne montre que son type', (tester) async {
      await _mount(tester);

      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(find.byType(HallPoster), findsOneWidget);
      expect(find.text('Page 12 sur 140'), findsOneWidget);

      await tester.tap(find.text('Images'));
      await tester.pumpAndSettle();
      expect(find.byType(HallPoster), findsNothing);
      expect(find.text('Rien dans ce rayon'), findsOneWidget);
    });

    testWidgets('les rayons montrent aussi les dossiers personnels, sans doublon', (tester) async {
      await _mount(
        tester,
        library: [
          MediaFile(path: '/videos/Nouveau film.mkv', type: MediaType.video, modifiedAt: DateTime(2026, 11, 10)),
          // Déjà ouvert : il reste à sa place parmi les récents, une seule fois.
          MediaFile(path: '/films/Dune.Part.Two.2024.mkv', type: MediaType.video, modifiedAt: DateTime(2026, 11, 9)),
          MediaFile(path: '/images/plage.jpg', type: MediaType.image, modifiedAt: DateTime(2026, 11, 8)),
        ],
      );

      // « Tout » est presque vide : les dossiers le complètent.
      expect(find.text('Nouveau film'), findsOneWidget);

      await tester.tap(find.text('Vidéos'));
      await tester.pumpAndSettle();
      expect(find.byType(HallPoster), findsNWidgets(3));

      await tester.tap(find.text('Images'));
      await tester.pumpAndSettle();
      expect(find.byType(HallPoster), findsOneWidget);
      expect(find.text('plage'), findsNWidgets(2));
      // Jamais ouvert : rien à reprendre, on l'ouvre.
      expect(find.widgetWithText(OmniaButton, 'Ouvrir'), findsOneWidget);
    });

    testWidgets('hall vide : la bienvenue, et la place des premières affiches', (tester) async {
      await _mount(tester, withRecents: false);

      expect(find.text('Déposez un fichier ou un dossier ici'), findsOneWidget);
      expect(find.byType(HallPoster), findsNothing);
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un fichier'), findsOneWidget);
    });

    testWidgets('tient dans toutes les fenêtres, jusqu’à la plus petite', (tester) async {
      await _mount(tester);
      for (final size in const [
        Size(1200, 760),
        Size(800, 600),
        Size(480, 400),
        Size(360, 240),
        Size(320, 240),
      ]) {
        await resizeWindow(tester, size);
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });

  group('Ce que le hall écrit', () {
    test('le titre d’un film perd ses points et son extension', () {
      expect(hallTitleFor('/f/The.Matrix.1999.1080p.mkv'), 'The Matrix 1999 1080p');
      expect(hallTitleFor('/f/Mon_film_de_vacances.mp4'), 'Mon film de vacances');
      // Un nom déjà lisible reste tel quel.
      expect(hallTitleFor('/m/01 - Get Lucky.flac'), '01 - Get Lucky');
    });

    test('où l’on en est, dit en clair', () {
      HistoryEntry entry({
        Duration position = Duration.zero,
        Duration duration = Duration.zero,
        bool completed = false,
        int page = 0,
        int pageCount = 0,
        double scroll = 0,
      }) =>
          HistoryEntry(
            path: '/x',
            position: position,
            duration: duration,
            lastOpened: DateTime.now(),
            completed: completed,
            page: page,
            pageCount: pageCount,
            scrollFraction: scroll,
          );

      expect(
        hallProgressLabel(
          entry(position: const Duration(minutes: 12, seconds: 5), duration: const Duration(minutes: 40)),
          MediaType.video,
        ),
        'Reprise à 12:05 sur 40:00',
      );
      expect(hallProgressLabel(entry(duration: const Duration(minutes: 40)), MediaType.audio), '40:00');
      expect(hallProgressLabel(entry(completed: true), MediaType.video), 'Terminé');
      expect(hallProgressLabel(entry(page: 3, pageCount: 9), MediaType.pdf), 'Page 3 sur 9');
      expect(hallProgressLabel(entry(scroll: 0.4), MediaType.text), 'Lu à 40 %');
      expect(hallProgressLabel(entry(), MediaType.image), isNull);
    });

    test('l’heure et la date, à la française', () {
      final t = DateTime(2026, 11, 17, 9, 5);
      expect(hallClock(t), '09:05');
      expect(hallDate(t), 'mardi 17 novembre');
    });

    test('chaque rayon ne garde que son type', () {
      expect(HallCategory.video.accepts(MediaType.video), isTrue);
      expect(HallCategory.video.accepts(MediaType.audio), isFalse);
      expect(HallCategory.documents.accepts(MediaType.pdf), isTrue);
      expect(HallCategory.documents.accepts(MediaType.text), isTrue);
      expect(HallCategory.images.accepts(MediaType.image), isTrue);
      expect(HallCategory.all.accepts(MediaType.unknown), isFalse);
    });
  });

  group('Fond du hall', () {
    test('le choix et l’image survivent à l’enregistrement', () {
      const prefs = AppPreferences(
        hallBackground: HallBackground.wallpaper,
        hallWallpaper: '/images/fond.jpg',
      );
      final relue = AppPreferences.fromJson(prefs.toJson());
      expect(relue.hallBackground, HallBackground.wallpaper);
      expect(relue.hallWallpaper, '/images/fond.jpg');
    });

    test('une valeur inconnue retombe sur l’aperçu', () {
      final relue = AppPreferences.fromJson({'hallBackground': 'hologramme'});
      expect(relue.hallBackground, HallBackground.preview);
      expect(relue.hallWallpaper, isEmpty);
      expect(relue.hallShowsLibrary, isTrue);
    });

    test('les dossiers personnels se retirent de l’accueil, et le restent', () {
      final relue = AppPreferences.fromJson(
        const AppPreferences(hallShowsLibrary: false).toJson(),
      );
      expect(relue.hallShowsLibrary, isFalse);
    });
  });
}
