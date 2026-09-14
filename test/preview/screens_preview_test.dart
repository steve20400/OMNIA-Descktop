// Aperçus des écrans d'OMNIA, rendus par le vrai code de l'interface.
//
// Désactivé par défaut. Pour régénérer les images dans build/preview/ :
//   OMNIA_PREVIEW=1 flutter test test/preview/screens_preview_test.dart
//
// L'application est montée telle quelle (OmniaApp, PlayerScreen, thème,
// traductions), avec des stockages en mémoire et un contrôleur de lecture
// factice à la place de mpv : ce qui s'affiche est exactement ce que dessine
// l'application, sans lecture réelle.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/core/services/audio_metadata_service.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/screen_wake.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:omnia/ui/app.dart';
import 'package:omnia/ui/help_overlay_controller.dart';
import 'package:omnia/ui/screens/player_screen.dart';
import 'package:omnia/ui/settings/settings_controller.dart';
import 'package:path/path.dart' as p;

final bool _enabled = Platform.environment['OMNIA_PREVIEW'] == '1';

/// Contrôleur factice : annonce la durée et la position voulues, sans son.
class _PreviewPlayer implements MediaController {
  _PreviewPlayer(this.timing);

  final Map<String, (Duration, Duration)> timing;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    final (duration, position) = timing[file.path] ?? (const Duration(minutes: 4), Duration.zero);
    sink.update(
      (s) => s.copyWith(
        file: file,
        status: PlaybackStatus.playing,
        duration: duration,
        position: position,
        hasVideo: false,
        clearError: true,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async => true;

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(File(path).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

/// Pochette d'album dessinée pour l'aperçu.
Future<Uint8List> _artwork() async {
  const size = 640.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const rect = Rect.fromLTWH(0, 0, size, size);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(size, size),
        const [Color(0xFF231433), Color(0xFF7A2E3B), Color(0xFFE08A3C)],
        const [0, 0.55, 1],
      ),
  );
  canvas.drawCircle(const Offset(400, 250), 190, Paint()..color = const Color(0x33F3EFE6));
  canvas.drawCircle(const Offset(400, 250), 120, Paint()..color = const Color(0xFFF2B441));
  canvas.drawCircle(const Offset(360, 230), 118, Paint()..color = const Color(0xFF231433));
  final lines = Paint()
    ..color = const Color(0x40F3EFE6)
    ..strokeWidth = 2;
  for (var i = 0; i < 9; i++) {
    final y = 430.0 + i * 18;
    canvas.drawLine(Offset(60, y), Offset(size - 60 - i * 30, y), lines);
  }
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(p.join('build', 'preview', '$name.png'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!_enabled) return;
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
    await _loadFont('InstrumentSans', ['assets/fonts/InstrumentSans.ttf']);
    await _loadFont(
      'IBMPlexMono',
      ['assets/fonts/IBMPlexMono-Regular.ttf', 'assets/fonts/IBMPlexMono-Medium.ttf'],
    );
    await _loadFont(
      'MaterialIcons',
      [p.join(flutterRoot, 'bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf')],
    );
  });

  testWidgets('aperçus des écrans', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Les tests remplacent les ombres par des traits : on les rétablit le
    // temps des captures, pour voir le vrai rendu.
    debugDisableShadows = false;

    try {
      // Fichiers réels : la liste des récents vérifie leur existence.
      final root = Directory(p.join(Directory.systemTemp.path, 'omnia-apercu'));
      final album = Directory(p.join(root.path, 'Musique', 'Nocturnes'))..createSync(recursive: true);
      final films = Directory(p.join(root.path, 'Films'))..createSync(recursive: true);
      final docs = Directory(p.join(root.path, 'Documents'))..createSync(recursive: true);

      const titles = [
        '01 - Prélude',
        '02 - Clair de nuit',
        '03 - Les heures bleues',
        '04 - Nocturne en si bémol',
        '05 - Lanterne',
        '06 - Au bord du fleuve',
        '07 - Minuit passé',
        '08 - Reflets',
        '09 - Dernière lumière',
        '10 - Aube',
      ];
      final tracks = [for (final t in titles) p.join(album.path, '$t.mp3')];
      final booklet = p.join(album.path, 'Livret.pdf');
      final notes = p.join(album.path, 'Notes de pochette.txt');
      final film = p.join(films.path, 'Le Grand Voyage (2024).mkv');
      final guide = p.join(docs.path, 'Guide de l’utilisateur.pdf');
      for (final path in [...tracks, booklet, notes, film, guide]) {
        File(path).writeAsStringSync('');
      }

      final cover = (await tester.runAsync(_artwork))!;
      final durations = [
        const Duration(minutes: 3, seconds: 12),
        const Duration(minutes: 4, seconds: 5),
        const Duration(minutes: 5, seconds: 21),
        const Duration(minutes: 4, seconds: 12),
        const Duration(minutes: 2, seconds: 58),
        const Duration(minutes: 6, seconds: 3),
        const Duration(minutes: 3, seconds: 50),
        const Duration(minutes: 4, seconds: 44),
        const Duration(minutes: 5, seconds: 2),
        const Duration(minutes: 7, seconds: 18),
      ];

      final bus = PlayerCommandBus();
      final store = MemorySettingsStore(preferences: const AppPreferences(language: AppLanguage.fr));
      await store.setLastVolume(72);
      final history = MemoryHistoryStore();
      final scanner = FakeFolderScanner({
        album.path: [
          for (var i = 0; i < tracks.length; i++)
            MediaFile(
              path: tracks[i],
              type: MediaType.audio,
              size: 6200000 + i * 410000,
              modifiedAt: DateTime(2026, 3, 1 + i),
            ),
          MediaFile(path: booklet, type: MediaType.pdf, size: 2400000, modifiedAt: DateTime(2026, 3, 1)),
          MediaFile(path: notes, type: MediaType.text, size: 4200, modifiedAt: DateTime(2026, 3, 1)),
        ],
      });
      final playlist = PlaylistService(bus: bus, scanner: scanner, history: history, settings: store);
      final service = PlaybackService(
        bus: bus,
        router: MediaRouter([
          _PreviewPlayer({tracks[3]: (durations[3], const Duration(minutes: 1, seconds: 37))}),
        ]),
        window: FakeWindowService(),
        playlist: playlist,
        history: history,
        settings: store,
      );
      final container = ProviderContainer(
        overrides: [
          commandBusProvider.overrideWithValue(bus),
          settingsStoreProvider.overrideWithValue(store),
          historyStoreProvider.overrideWithValue(history),
          playbackServiceProvider.overrideWithValue(service),
          playlistServiceProvider.overrideWithValue(playlist),
          windowServiceProvider.overrideWithValue(FakeWindowService()),
          screenWakeProvider.overrideWithValue(RecordingScreenWake()),
          audioMetadataServiceProvider.overrideWithValue(
            FakeAudioMetadataService({
              tracks[3]: AudioTags(
                title: 'Nocturne en si bémol',
                artist: 'Ensemble Lumen',
                album: 'Nocturnes',
                year: 2026,
                trackNumber: 4,
                cover: cover,
                coverMime: 'image/png',
              ),
            }),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await service.dispose();
        await playlist.dispose();
        await bus.dispose();
      });

      // Historique : trois pistes écoutées, une interrompue, trois récents.
      for (var i = 0; i < 3; i++) {
        await history.savePosition(tracks[i],
            position: const Duration(minutes: 1), duration: durations[i], now: DateTime(2026, 9, 10, 20, i));
        await history.markCompleted(tracks[i], now: DateTime(2026, 9, 10, 20, 10 + i));
      }
      await history.savePosition(tracks[6],
          position: const Duration(minutes: 1, seconds: 20),
          duration: durations[6],
          now: DateTime(2026, 9, 11, 22));
      await history.touch(guide, now: DateTime(2026, 9, 12, 9, 15));
      await history.touch(film, now: DateTime(2026, 9, 13, 21, 40));
      await history.touch(tracks[3], now: DateTime(2026, 9, 14, 8, 5));

      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const OmniaApp()),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '01-accueil');

      // Lecture d'un album : pochette, panneau du dossier, faisceau.
      bus.dispatch(OpenFile(tracks[3]));
      await _drain(tester);
      await tester.runAsync(() async {
        await precacheImage(MemoryImage(cover), tester.element(find.byType(PlayerScreen)));
      });
      await tester.pumpAndSettle();
      await _capture(tester, key, '02-lecture-audio');

      container.read(settingsUiProvider.notifier).show(SettingsSection.general);
      await tester.pumpAndSettle();
      await _capture(tester, key, '03-parametres');

      container.read(settingsUiProvider.notifier).select(SettingsSection.shortcuts);
      await tester.pumpAndSettle();
      await _capture(tester, key, '04-raccourcis');

      container.read(settingsUiProvider.notifier).hide();
      await tester.pumpAndSettle();
      container.read(helpVisibleProvider.notifier).toggle();
      await tester.pumpAndSettle();
      await _capture(tester, key, '05-aide');
      container.read(helpVisibleProvider.notifier).hide();
      await tester.pumpAndSettle();
    } finally {
      debugDisableShadows = true;
    }
  }, skip: !_enabled);
}
