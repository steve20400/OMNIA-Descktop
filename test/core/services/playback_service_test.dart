import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/frame_capturer.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/models/document_layout.dart';
import 'package:omnia/core/models/end_of_playback_mode.dart';
import 'package:omnia/core/models/equalizer.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/models/track_info.dart';
import 'package:omnia/core/models/video_adjust.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/screenshot_service.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/system_integration.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:path/path.dart' as p;

/// Contrôleur factice : enregistre ce qu'il reçoit et simule une lecture.
class FakeAvController implements MediaController, FrameCapturer {
  final List<MediaFile> opened = [];
  final List<PlayerCommand> handled = [];
  int closeCount = 0;
  PlaybackStateSink? sink;

  /// Durée annoncée à l'ouverture.
  Duration duration = const Duration(minutes: 10);

  /// Image renvoyée par la capture ; `null` simule un flux sans vidéo.
  Uint8List? frame = Uint8List.fromList([1, 2, 3]);

  @override
  Future<Uint8List?> captureFrame() async => frame;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    this.sink = sink;
    opened.add(file);
    sink.update(
      (s) => s.copyWith(
        file: file,
        status: PlaybackStatus.playing,
        position: Duration.zero,
        duration: duration,
        clearError: true,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    handled.add(command);
    switch (command) {
      case Pause():
        sink?.update((s) => s.copyWith(status: PlaybackStatus.paused));
      case SeekAbsolute(:final position):
        sink?.update((s) => s.copyWith(position: position));
      default:
        break;
    }
    return true;
  }

  /// Simule la fin naturelle du fichier.
  void finish() {
    sink?.update((s) => s.copyWith(status: PlaybackStatus.ended));
  }

  /// Simule l'avancée de la lecture.
  void advanceTo(Duration position) {
    sink?.update((s) => s.copyWith(position: position));
  }

  @override
  Future<void> close() async {
    closeCount++;
    sink?.update((s) => s.copyWith(clearFile: true, status: PlaybackStatus.idle));
  }

  @override
  Future<void> dispose() async {}
}

/// Contrôleur de documents factice : 40 pages, réagit aux commandes de page.
class FakeDocController implements MediaController {
  final List<PlayerCommand> handled = [];
  PlaybackStateSink? sink;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.pdf, MediaType.text};

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    this.sink = sink;
    sink.update(
      (s) => s.copyWith(
        file: file,
        status: PlaybackStatus.playing,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        currentPage: file.type == MediaType.pdf ? 1 : 0,
        totalPages: file.type == MediaType.pdf ? 40 : 0,
        scrollFraction: 0,
        clearError: true,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    handled.add(command);
    switch (command) {
      case GoToPage(:final page):
        sink?.update((s) => s.copyWith(currentPage: page.clamp(1, 40)));
      case NextPage():
        sink?.update((s) => s.copyWith(currentPage: (s.currentPage + 1).clamp(1, 40)));
      case ScrollTo(:final fraction):
        sink?.update((s) => s.copyWith(scrollFraction: fraction));
      default:
        return false;
    }
    return true;
  }

  @override
  Future<void> close() async {
    sink?.update((s) => s.copyWith(clearFile: true, status: PlaybackStatus.idle));
  }

  @override
  Future<void> dispose() async {}
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

MediaFile mf(String path, MediaType type) => MediaFile(path: path, type: type);

void main() {
  late PlayerCommandBus bus;
  late FakeAvController av;
  late FakeWindowService window;
  late FakeFolderScanner scanner;
  late MemoryHistoryStore history;
  late RecordingSystemIntegration system;
  late PlaylistService playlist;
  late PlaybackService service;

  final folders = <String, List<MediaFile>>{
    // Modifiable : certains tests y ajoutent un dossier.
    '/serie': [
      mf('/serie/ep1.mkv', MediaType.video),
      mf('/serie/ep2.mkv', MediaType.video),
      mf('/serie/ep3.mkv', MediaType.video),
    ],
    '/vide': [],
  };

  setUp(() {
    bus = PlayerCommandBus();
    av = FakeAvController();
    window = FakeWindowService();
    scanner = FakeFolderScanner(folders);
    history = MemoryHistoryStore();
    system = RecordingSystemIntegration();
    playlist = PlaylistService(bus: bus, scanner: scanner, history: history);
    service = PlaybackService(
      bus: bus,
      router: MediaRouter([av]),
      window: window,
      playlist: playlist,
      history: history,
      system: system,
    );
  });

  tearDown(() async {
    await service.dispose();
    await playlist.dispose();
    await bus.dispose();
  });

  group('Ouverture', () {
    test('OpenFile route vers le contrôleur du type', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();

      expect(av.opened.single.path, '/serie/ep1.mkv');
      expect(av.opened.single.type, MediaType.video);
      expect(service.state.status, PlaybackStatus.playing);
      expect(service.activeController, same(av));
    });

    test('ouvrir un fichier scanne son dossier et remplit la playlist', () async {
      bus.dispatch(const OpenFile('/serie/ep2.mkv'));
      await settle();

      expect(scanner.scannedFolders, ['/serie']);
      expect(playlist.state.entries, hasLength(3));
      expect(playlist.state.currentPath, '/serie/ep2.mkv');
      expect(service.state.playlist, [
        '/serie/ep1.mkv',
        '/serie/ep2.mkv',
        '/serie/ep3.mkv',
      ]);
      expect(service.state.playlistIndex, 1);
    });

    test('la lecture démarre sans attendre la fin du scan', () async {
      final slowPlaylist = PlaylistService(
        bus: bus,
        scanner: FakeFolderScanner(folders, delay: const Duration(milliseconds: 200)),
      );
      final slowService = PlaybackService(
        bus: bus,
        router: MediaRouter([av]),
        window: window,
        playlist: slowPlaylist,
      );

      await slowService.openPath('/serie/ep1.mkv');
      // Le scan est toujours en cours, mais le fichier joue déjà.
      expect(slowService.state.status, PlaybackStatus.playing);
      expect(slowPlaylist.state.entries, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(slowPlaylist.state.entries, hasLength(3));

      await slowService.dispose();
      await slowPlaylist.dispose();
    });

    test('extension inconnue → erreur, pas de crash', () async {
      bus.dispatch(const OpenFile('/x/archive.zip'));
      await settle();

      expect(av.opened, isEmpty);
      expect(service.state.status, PlaybackStatus.error);
      expect(service.state.error?.code, PlaybackErrorCode.unsupportedFormat);
    });

    test('ouvrir un second fichier du même contrôleur ne le ferme pas', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      bus.dispatch(const OpenFile('/serie/ep2.mkv'));
      await settle();

      expect(av.opened.map((f) => f.name), ['ep1.mkv', 'ep2.mkv']);
      expect(av.closeCount, 0);
    });

    test('le flux d’état émet chaque changement', () async {
      final statuses = <PlaybackStatus>[];
      final sub = service.stream.listen((s) => statuses.add(s.status));
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      bus.dispatch(const Pause());
      await settle();

      expect(statuses, contains(PlaybackStatus.playing));
      expect(statuses.last, PlaybackStatus.paused);
      await sub.cancel();
    });
  });

  group('Délégation', () {
    test('les commandes média vont au contrôleur actif', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      bus.dispatch(const SeekRelative(5));
      bus.dispatch(const SetVolume(50));
      bus.dispatch(const ToggleMute());
      await settle();

      expect(
        av.handled.where((c) => c is! SeekAbsolute),
        [const SeekRelative(5), const SetVolume(50), const ToggleMute()],
      );
    });

    test('sans fichier ouvert, les commandes média sont ignorées', () async {
      bus.dispatch(const TogglePlay());
      await settle();
      expect(av.handled, isEmpty);
      expect(service.state.status, PlaybackStatus.idle);
    });

    test('les commandes arrivent dans l’ordre malgré l’asynchrone', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      for (var i = 0; i < 20; i++) {
        bus.dispatch(SeekRelative(i.toDouble()));
      }
      await settle();
      expect(
        av.handled.whereType<SeekRelative>().map((c) => c.seconds).toList(),
        List.generate(20, (i) => i.toDouble()),
      );
    });

    test('Stop ferme le contrôleur et vide l’état', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      bus.dispatch(const Stop());
      await settle();

      expect(av.closeCount, 1);
      expect(service.state.hasFile, isFalse);
      expect(service.activeController, isNull);
      expect(playlist.state.currentPath, isNull);
    });

    test('RevealInFolder passe par l’intégration système', () async {
      bus.dispatch(const RevealInFolder('/serie/ep1.mkv'));
      await settle();
      expect(system.revealed, ['/serie/ep1.mkv']);
    });
  });

  group('Navigation dans la playlist', () {
    test('NextFile et PreviousFile suivent la liste affichée', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();

      bus.dispatch(const NextFile());
      await settle();
      expect(service.state.file?.name, 'ep2.mkv');

      bus.dispatch(const NextFile());
      await settle();
      expect(service.state.file?.name, 'ep3.mkv');

      bus.dispatch(const PreviousFile());
      await settle();
      expect(service.state.file?.name, 'ep2.mkv');
    });

    test('NextFile boucle à la fin de la liste', () async {
      bus.dispatch(const OpenFile('/serie/ep3.mkv'));
      await settle();
      bus.dispatch(const NextFile());
      await settle();
      expect(service.state.file?.name, 'ep1.mkv');
    });

    test('NextFile sans playlist ne fait rien', () async {
      bus.dispatch(const NextFile());
      await settle();
      expect(service.state.hasFile, isFalse);
    });
  });

  group('Fin de lecture', () {
    Future<void> openFirst() async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
    }

    test('mode « suivant » enchaîne sur le fichier suivant', () async {
      await openFirst();
      av.finish();
      await settle();
      expect(service.state.file?.name, 'ep2.mkv');
    });

    test('la fin d’un fichier n’avance que d’un cran, même si l’état bouge entre-temps', () async {
      await openFirst();
      av.finish();
      await settle();
      // Une mise à jour d'état pendant que le suivant se charge (statut encore
      // « terminé ») ne doit pas relancer l'enchaînement.
      expect(service.state.file?.name, 'ep2.mkv');
      expect(av.opened.map((f) => f.name), ['ep1.mkv', 'ep2.mkv']);
    });

    test('mode « suivant » s’arrête au dernier fichier', () async {
      bus.dispatch(const OpenFile('/serie/ep3.mkv'));
      await settle();
      av.finish();
      await settle();
      expect(service.state.file?.name, 'ep3.mkv');
    });

    test('mode « stop » ne fait rien', () async {
      bus.dispatch(const SetLoopMode(EndOfPlaybackMode.stop));
      await openFirst();
      av.finish();
      await settle();
      expect(service.state.file?.name, 'ep1.mkv');
      expect(av.opened, hasLength(1));
    });

    test('mode « répéter » rejoue sans rouvrir le fichier', () async {
      bus.dispatch(const SetLoopMode(EndOfPlaybackMode.repeatOne));
      await openFirst();
      av.finish();
      await settle();

      expect(av.opened, hasLength(1));
      expect(av.handled, contains(const SeekAbsolute(Duration.zero)));
      expect(av.handled, contains(const Play()));
    });

    test('mode « boucler le dossier » revient au début', () async {
      bus.dispatch(const SetLoopMode(EndOfPlaybackMode.loopFolder));
      bus.dispatch(const OpenFile('/serie/ep3.mkv'));
      await settle();
      av.finish();
      await settle();
      expect(service.state.file?.name, 'ep1.mkv');
    });

    test('la fin marque le fichier comme vu', () async {
      await openFirst();
      av.finish();
      await settle();
      expect(history.entryFor('/serie/ep1.mkv')?.completed, isTrue);
    });
  });

  group('Reprise de lecture', () {
    test('la position est sauvegardée en changeant de fichier', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      av.advanceTo(const Duration(minutes: 4));
      await settle();

      bus.dispatch(const OpenFile('/serie/ep2.mkv'));
      await settle();

      expect(
        history.entryFor('/serie/ep1.mkv')?.resumePosition,
        const Duration(minutes: 4),
      );
    });

    test('la position mémorisée est réappliquée à la réouverture', () async {
      await history.savePosition(
        '/serie/ep1.mkv',
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 10),
        now: DateTime(2026, 9, 6),
      );

      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();

      expect(av.handled, contains(const SeekAbsolute(Duration(minutes: 4))));
      expect(service.state.position, const Duration(minutes: 4));
    });

    test('la reprise ne s’applique qu’au fichier qu’elle concerne', () async {
      // Seul ep2 a une position mémorisée.
      await history.savePosition(
        '/serie/ep2.mkv',
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 10),
        now: DateTime(2026, 9, 6),
      );

      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      // ep1 joue depuis le début : aucun seek de reprise ne doit lui parvenir.
      expect(av.handled.whereType<SeekAbsolute>(), isEmpty);

      bus.dispatch(const OpenFile('/serie/ep2.mkv'));
      await settle();
      expect(av.handled, contains(const SeekAbsolute(Duration(minutes: 4))));
      expect(service.state.file?.name, 'ep2.mkv');
      expect(service.state.position, const Duration(minutes: 4));
    });

    test('ouvrir un fichier l’inscrit aussitôt dans les récents', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      expect(history.recent().map((e) => e.path), ['/serie/ep1.mkv']);
    });

    test('ClearHistory vide les récents et les pastilles du panneau', () async {
      await history.savePosition(
        '/serie/ep2.mkv',
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 10),
        now: DateTime(2026, 9, 6),
      );
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      expect(playlist.state.entryFor('/serie/ep2.mkv')!.hasProgressBadge, isTrue);

      bus.dispatch(const ClearHistory());
      await settle();
      expect(history.recent(), isEmpty);
      expect(playlist.state.entryFor('/serie/ep2.mkv')!.hasProgressBadge, isFalse);
    });

    test('aucune reprise sous le seuil de 30 s', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      av.advanceTo(const Duration(seconds: 20));
      await settle();
      bus.dispatch(const Stop());
      await settle();

      expect(history.entryFor('/serie/ep1.mkv')?.resumePosition, isNull);
    });

    test('la progression est enregistrée au fil de la lecture', () async {
      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      av.advanceTo(const Duration(minutes: 2));
      await settle();

      expect(
        history.entryFor('/serie/ep1.mkv')?.resumePosition,
        const Duration(minutes: 2),
      );
    });
  });

  group('Fenêtre et modes', () {
    test('ToggleFullscreen pilote la fenêtre et l’état', () async {
      bus.dispatch(const ToggleFullscreen());
      await settle();
      expect(window.fullscreen, isTrue);
      expect(service.state.fullscreen, isTrue);

      bus.dispatch(const ToggleFullscreen());
      await settle();
      expect(window.fullscreen, isFalse);
    });

    test('ExitFullscreen ne fait rien hors plein écran', () async {
      bus.dispatch(const ExitFullscreen());
      await settle();
      expect(window.fullscreen, isFalse);
    });

    test('ToggleAlwaysOnTop', () async {
      bus.dispatch(const ToggleAlwaysOnTop());
      await settle();
      expect(window.alwaysOnTop, isTrue);
      expect(service.state.alwaysOnTop, isTrue);
    });

    test('SetLoopMode et CycleLoopMode', () async {
      bus.dispatch(const SetLoopMode(EndOfPlaybackMode.shuffle));
      await settle();
      expect(service.state.endMode, EndOfPlaybackMode.shuffle);

      bus.dispatch(const CycleLoopMode());
      await settle();
      expect(service.state.endMode, EndOfPlaybackMode.stop);
    });

    test('le mode de fin de lecture est relu au démarrage et sauvegardé', () async {
      final store = MemorySettingsStore();
      await store.setEndOfPlaybackMode('loopFolder');

      final ownBus = PlayerCommandBus();
      final ownPlaylist = PlaylistService(bus: ownBus, scanner: scanner);
      final restored = PlaybackService(
        bus: ownBus,
        router: MediaRouter([av]),
        window: window,
        playlist: ownPlaylist,
        settings: store,
      );
      expect(restored.state.endMode, EndOfPlaybackMode.loopFolder);

      ownBus.dispatch(const CycleLoopMode());
      await settle();
      expect(store.endOfPlaybackMode, 'shuffle');

      await restored.dispose();
      await ownPlaylist.dispose();
      await ownBus.dispose();
    });
  });

  group('Ouverture d’un dossier', () {
    test('lit le premier fichier de la liste triée', () async {
      bus.dispatch(const OpenFolder('/serie'));
      await settle();
      expect(service.state.file?.name, 'ep1.mkv');
      expect(playlist.state.entries, hasLength(3));
    });

    test('dossier sans média lisible → message dédié', () async {
      final dir = Directory.systemTemp.createTempSync('omnia_empty_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Nettoyé par le système.
        }
      });
      scanner.filesByFolder[dir.path] = [];

      bus.dispatch(OpenFolder(dir.path));
      await settle();
      await service.idle;
      expect(service.state.status, PlaybackStatus.error);
      expect(service.state.error?.code, PlaybackErrorCode.emptyFolder);
    });

    test('dossier introuvable → message dédié', () async {
      bus.dispatch(const OpenFolder('/dossier/absent/vraiment'));
      await settle();
      await service.idle;
      expect(service.state.status, PlaybackStatus.error);
      expect(service.state.error?.code, PlaybackErrorCode.fileNotFound);
    });
  });

  group('Volume sans fichier ouvert', () {
    test('SetVolume est mémorisé et appliqué au fichier suivant', () async {
      bus.dispatch(const SetVolume(40));
      await settle();
      expect(service.state.volume, 40);

      bus.dispatch(const OpenFile('/serie/ep1.mkv'));
      await settle();
      expect(service.state.volume, 40);
    });

    test('VolumeRelative est borné à 0–100', () async {
      bus.dispatch(const VolumeRelative(50));
      bus.dispatch(const VolumeRelative(50));
      await settle();
      expect(service.state.volume, 100);

      for (var i = 0; i < 30; i++) {
        bus.dispatch(const VolumeRelative(-5));
      }
      await settle();
      expect(service.state.volume, 0);
    });

    test('ToggleMute fonctionne aussi sans fichier', () async {
      bus.dispatch(const ToggleMute());
      await settle();
      expect(service.state.muted, isTrue);
    });

    test('régler le volume lève la sourdine', () async {
      bus.dispatch(const ToggleMute());
      bus.dispatch(const SetVolume(70));
      await settle();
      expect(service.state.muted, isFalse);
      expect(service.state.volume, 70);
    });
  });

  group('Fichiers non pris en charge dans le dossier', () {
    setUp(() {
      // Le dossier contient un PDF, qu'aucun contrôleur ne sait ouvrir.
      folders['/mixte'] = [
        mf('/mixte/a.mkv', MediaType.video),
        mf('/mixte/notice.pdf', MediaType.pdf),
        mf('/mixte/b.mkv', MediaType.video),
      ];
    });

    tearDown(() => folders.remove('/mixte'));

    test('la fin de lecture enjambe le fichier non lisible', () async {
      final router = MediaRouter([av]);
      final ownPlaylist = PlaylistService(
        bus: bus,
        scanner: scanner,
        isPlayable: (path) => router.controllerForPath(path) != null,
      );
      final ownService = PlaybackService(
        bus: bus,
        router: router,
        window: window,
        playlist: ownPlaylist,
      );

      await ownService.openPath('/mixte/a.mkv');
      await settle();
      av.finish();
      await settle();

      expect(ownService.state.file?.name, 'b.mkv');

      await ownService.dispose();
      await ownPlaylist.dispose();
    });

    test('le panneau montre quand même tous les fichiers', () async {
      await playlist.scanFolder('/mixte');
      expect(playlist.state.entries, hasLength(3));
    });
  });

  group('Documents', () {
    late FakeDocController doc;
    late PlaybackService docService;
    late PlaylistService docPlaylist;

    setUp(() {
      doc = FakeDocController();
      folders['/docs'] = [
        mf('/docs/manuel.pdf', MediaType.pdf),
        mf('/docs/notes.txt', MediaType.text),
      ];
      docPlaylist = PlaylistService(bus: bus, scanner: scanner, history: history);
      docService = PlaybackService(
        bus: bus,
        router: MediaRouter([av, doc]),
        window: window,
        playlist: docPlaylist,
        history: history,
      );
    });

    tearDown(() async {
      folders.remove('/docs');
      await docService.dispose();
      await docPlaylist.dispose();
    });

    test('un PDF s’ouvre via le contrôleur de documents', () async {
      await docService.openPath('/docs/manuel.pdf');
      expect(docService.state.isDocument, isTrue);
      expect(docService.state.totalPages, 40);
      expect(docService.state.currentPage, 1);
    });

    test('un changement de page est mémorisé', () async {
      await docService.openPath('/docs/manuel.pdf');
      await doc.handle(const GoToPage(12));
      await settle();
      final entry = history.entryFor('/docs/manuel.pdf')!;
      expect(entry.page, 12);
      expect(entry.pageCount, 40);
    });

    test('la dernière page lue est rouverte', () async {
      await history.saveDocumentPosition('/docs/manuel.pdf', page: 12, pageCount: 40);
      await docService.openPath('/docs/manuel.pdf');
      await settle();
      expect(doc.handled, contains(const GoToPage(12)));
      expect(docService.state.currentPage, 12);
    });

    test('le défilement d’un texte est mémorisé puis restauré', () async {
      await docService.openPath('/docs/notes.txt');
      await doc.handle(const ScrollTo(0.4));
      await settle();
      expect(history.entryFor('/docs/notes.txt')!.scrollFraction, closeTo(0.4, 1e-9));

      await docService.openPath('/docs/manuel.pdf');
      await docService.openPath('/docs/notes.txt');
      await settle();
      expect(doc.handled.whereType<ScrollTo>().last.fraction, closeTo(0.4, 1e-9));
    });

    test('un document ne déclenche jamais la fin de lecture', () async {
      await docService.openPath('/docs/manuel.pdf');
      await doc.handle(const GoToPage(40));
      await settle();
      expect(docService.state.file?.name, 'manuel.pdf');
      expect(history.entryFor('/docs/manuel.pdf')!.completed, isTrue);
    });
  });

  group('Capture d’écran', () {
    late Directory shots;
    late PlaybackService shotService;
    late PlaylistService shotPlaylist;

    setUp(() {
      shots = Directory.systemTemp.createTempSync('omnia_shots_');
      shotPlaylist = PlaylistService(bus: bus, scanner: scanner);
      shotService = PlaybackService(
        bus: bus,
        router: MediaRouter([av]),
        window: window,
        playlist: shotPlaylist,
        screenshots: ScreenshotService(defaultFolder: () async => shots),
      );
    });

    tearDown(() async {
      await shotService.dispose();
      await shotPlaylist.dispose();
      try {
        shots.deleteSync(recursive: true);
      } on FileSystemException {
        // Nettoyé par le système.
      }
    });

    test('S enregistre un PNG et publie son chemin', () async {
      await shotService.openPath('/serie/ep1.mkv');
      bus.dispatch(const TakeScreenshot());
      await settle();
      await shotService.idle;

      final path = shotService.state.lastScreenshot;
      expect(path, isNotNull);
      expect(p.dirname(path!), shots.path);
      expect(p.basename(path), startsWith('ep1 '));
      expect(File(path).existsSync(), isTrue);
    });

    test('sans image (audio), rien n’est enregistré', () async {
      av.frame = null;
      await shotService.openPath('/serie/ep1.mkv');
      bus.dispatch(const TakeScreenshot());
      await settle();
      await shotService.idle;

      expect(shotService.state.lastScreenshot, isNull);
      expect(shots.listSync(), isEmpty);
    });

    test('sans fichier ouvert, rien ne se passe', () async {
      bus.dispatch(const TakeScreenshot());
      await settle();
      expect(shotService.state.lastScreenshot, isNull);
    });
  });

  group('Mini-lecteur', () {
    test('entrer : fenêtre compacte, premier plan ; sortir : tout est rendu', () async {
      window.bounds = const Rect.fromLTWH(100, 80, 1200, 760);
      bus.dispatch(const ToggleMiniPlayer());
      await settle();

      expect(service.state.miniPlayer, isTrue);
      expect(service.state.alwaysOnTop, isTrue);
      expect(window.alwaysOnTop, isTrue);
      expect(window.bounds.topLeft, const Offset(100, 80));
      expect(window.bounds.size, PlaybackService.miniPlayerSize);
      expect(window.minimumSize, PlaybackService.miniPlayerSize);

      bus.dispatch(const ToggleMiniPlayer());
      await settle();

      expect(service.state.miniPlayer, isFalse);
      expect(service.state.alwaysOnTop, isFalse);
      expect(window.alwaysOnTop, isFalse);
      expect(window.bounds, const Rect.fromLTWH(100, 80, 1200, 760));
      expect(window.minimumSize, PlaybackService.mainMinimumSize);
    });

    test('le premier plan choisi avant est conservé à la sortie', () async {
      bus.dispatch(const ToggleAlwaysOnTop());
      bus.dispatch(const ToggleMiniPlayer());
      bus.dispatch(const ToggleMiniPlayer());
      await settle();
      expect(service.state.alwaysOnTop, isTrue);
      expect(window.alwaysOnTop, isTrue);
    });

    test('quitter le plein écran avant d’entrer en mini-lecteur', () async {
      bus.dispatch(const ToggleFullscreen());
      bus.dispatch(const ToggleMiniPlayer());
      await settle();
      expect(service.state.fullscreen, isFalse);
      expect(window.fullscreen, isFalse);
      expect(service.state.miniPlayer, isTrue);
    });
  });

  test('PlaybackState — aller-retour JSON', () {
    const state = PlaybackState(
      file: MediaFile(path: '/a/b.mkv', type: MediaType.video),
      status: PlaybackStatus.paused,
      position: Duration(seconds: 42),
      duration: Duration(minutes: 3),
      volume: 65,
      muted: true,
      speed: 1.25,
      rotation: 1,
      readingDark: true,
      documentLayout: DocumentLayout.paged,
      scrollFraction: 0.3,
      subtitleTracks: [TrackInfo(id: '1', title: 'Français', language: 'fre')],
      audioTracks: [TrackInfo(id: '1', language: 'eng'), TrackInfo(id: '2', language: 'fre')],
      subtitleTrackId: '1',
      audioTrackId: '2',
      subtitlesVisible: false,
      subtitleDelay: -0.5,
      subtitleScale: 1.5,
      loopA: Duration(seconds: 10),
      loopB: Duration(seconds: 20),
      aspectMode: AspectMode.wide,
      videoZoom: 0.2,
      videoRotation: 3,
      videoAdjust: VideoAdjust(brightness: 5, contrast: -5, saturation: 10),
      equalizerGains: [5, 4, 3, 1, -1, -1, 1, 3, 4, 5],
      equalizerEnabled: true,
      lastScreenshot: '/captures/x.png',
      miniPlayer: true,
      endMode: EndOfPlaybackMode.repeatOne,
      fullscreen: true,
      playlist: ['/a/b.mkv', '/a/c.mkv'],
      playlistIndex: 0,
      error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: 'x'),
    );
    final restored = PlaybackState.fromJson(state.toJson());
    expect(restored.toJson(), state.toJson());
    expect(restored.progress, closeTo(42 / 180, 1e-9));
    expect(restored.remaining, const Duration(minutes: 2, seconds: 18));
    expect(restored.abLoopActive, isTrue);
    expect(restored.equalizerPreset, 'rock');
    expect(restored.subtitleTracks.single.label, 'Français');
  });

  test('PlaybackState — JSON minimal : valeurs de repli', () {
    final restored = PlaybackState.fromJson(const {});
    expect(restored.subtitlesVisible, isTrue);
    expect(restored.equalizerGains, Equalizer.flat);
    expect(restored.abLoopActive, isFalse);
    expect(restored.videoAdjust, VideoAdjust.neutral);
  });
}
