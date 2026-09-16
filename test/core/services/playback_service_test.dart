import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/frame_capturer.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/controllers/stream_recorder.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/document_layout.dart';
import 'package:omnia/core/models/end_of_playback_mode.dart';
import 'package:omnia/core/models/equalizer.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/models/recording_failure.dart';
import 'package:omnia/core/models/resume_offer.dart';
import 'package:omnia/core/models/track_info.dart';
import 'package:omnia/core/models/video_adjust.dart';
import 'package:omnia/core/models/window_sizes.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/screenshot_service.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/system_integration.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:path/path.dart' as p;

/// Un extrait plausible : la signature Matroska, puis assez d'octets pour que
/// le service n'y voie pas un fichier réduit à son en-tête de conteneur.
List<int> matroskaClip([int bytes = 16 * 1024]) => <int>[
      0x1A,
      0x45,
      0xDF,
      0xA3,
      ...List<int>.filled(bytes - 4, 0),
    ];

/// Contrôleur factice : enregistre ce qu'il reçoit et simule une lecture.
class FakeAvController implements MediaController, FrameCapturer, StreamRecorder {
  final List<MediaFile> opened = [];
  final List<PlayerCommand> handled = [];
  int closeCount = 0;
  PlaybackStateSink? sink;

  /// Durée annoncée à l'ouverture.
  Duration duration = const Duration(minutes: 10);

  /// Image annoncée à l'ouverture : présence et dimensions d'affichage (0 :
  /// pas encore connues, comme au début d'une vraie ouverture).
  bool hasVideo = false;
  int videoWidth = 0;
  int videoHeight = 0;

  /// Image renvoyée par la capture ; `null` simule un flux sans vidéo.
  Uint8List? frame = Uint8List.fromList([1, 2, 3]);

  @override
  Future<Uint8List?> captureFrame() async => frame;

  /// Extrait en cours, et ce que l'arrêt écrit dans son fichier (vide :
  /// l'enregistreur n'a rien reçu, lecture restée en pause par exemple).
  String? recordingPath;
  List<int> recordedBytes = matroskaClip();

  /// Ce que le repli par le cache écrit quand l'arrêt n'a rien laissé. Vide :
  /// le moteur n'a rien en cache non plus.
  List<int> dumpedBytes = const [];

  /// Nombre de replis demandés.
  int dumpCount = 0;

  /// Raison rendue par le moteur au démarrage d'un extrait :
  /// [RecordingFailure.none] pour un moteur qui accepte.
  RecordingFailure recordingRefusal = RecordingFailure.none;

  /// Nombre de fois où le moteur a retrouvé ses réglages d'avant l'extrait.
  int releaseCount = 0;

  @override
  Future<RecordingFailure> startRecording(String path) async {
    if (recordingRefusal != RecordingFailure.none) return recordingRefusal;
    recordingPath = path;
    return RecordingFailure.none;
  }

  @override
  Future<void> stopRecording() async {
    final path = recordingPath;
    recordingPath = null;
    if (path != null) await File(path).writeAsBytes(recordedBytes);
  }

  @override
  Future<bool> dumpRecording(String path) async {
    dumpCount++;
    if (dumpedBytes.isEmpty) return false;
    await File(path).writeAsBytes(dumpedBytes);
    return true;
  }

  @override
  Future<void> releaseRecording() async => releaseCount++;

  @override
  Future<String> recordingDiagnostics() async => 'Contrôleur factice : rien à rapporter.';

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
        hasVideo: hasVideo,
        videoWidth: videoWidth,
        videoHeight: videoHeight,
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

  /// Simule l'arrivée des dimensions de l'image, après l'ouverture.
  void reportVideoSize(int width, int height) {
    sink?.update(
      (s) => s.copyWith(hasVideo: width > 0, videoWidth: width, videoHeight: height),
    );
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

/// Compare une géométrie à la tolérance près : les tailles du mini-lecteur
/// viennent de divisions par le ratio de l'image.
void expectRect(Rect actual, double left, double top, double width, double height) {
  expect(actual.left, closeTo(left, 1e-6), reason: 'gauche');
  expect(actual.top, closeTo(top, 1e-6), reason: 'haut');
  expect(actual.width, closeTo(width, 1e-6), reason: 'largeur');
  expect(actual.height, closeTo(height, 1e-6), reason: 'hauteur');
}

void expectSize(Size actual, double width, double height) {
  expect(actual.width, closeTo(width, 1e-6), reason: 'largeur');
  expect(actual.height, closeTo(height, 1e-6), reason: 'hauteur');
}

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

  group('Extraits', () {
    late Directory clips;
    late PlaybackService clipService;
    late PlaylistService clipPlaylist;

    setUp(() {
      clips = Directory.systemTemp.createTempSync('omnia_clips_');
      clipPlaylist = PlaylistService(bus: bus, scanner: scanner);
      clipService = PlaybackService(
        bus: bus,
        router: MediaRouter([av]),
        window: window,
        playlist: clipPlaylist,
        screenshots: ScreenshotService(defaultFolder: () async => clips),
        recordingCheckDelay: Duration.zero,
      );
    });

    tearDown(() async {
      await clipService.dispose();
      await clipPlaylist.dispose();
      try {
        clips.deleteSync(recursive: true);
      } on FileSystemException {
        // Nettoyé par le système.
      }
    });

    Future<void> toggle() async {
      bus.dispatch(const ToggleRecording());
      await settle();
      await clipService.idle;
    }

    test('un extrait de vidéo s’écrit en .mkv dans le dossier des captures', () async {
      await clipService.openPath('/serie/ep1.mkv');
      clipService.update((s) => s.copyWith(hasVideo: true));
      await toggle();

      final path = clipService.state.recordingPath;
      expect(path, isNotNull);
      expect(p.dirname(path!), clips.path);
      expect(p.basename(path), startsWith('ep1 '));
      expect(p.extension(path), '.mkv');
      expect(av.recordingPath, path);
      expect(clipService.state.recordingStartedAt, isNotNull);

      await toggle();
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingStartedAt, isNull);
      expect(clipService.state.lastRecording, path);
      expect(clipService.state.recordingFailed, isFalse);
      expect(File(path).existsSync(), isTrue);
    });

    test('un son seul s’écrit en .mka', () async {
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      expect(p.extension(clipService.state.recordingPath!), '.mka');
      await toggle();
    });

    test('un extrait qui s’écrit ne passe pas par le repli', () async {
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      await toggle();
      expect(av.dumpCount, 0);
      expect(clipService.state.recordingFailure, RecordingFailure.none);
    });

    test('rien d’écrit ni en cache : échec signalé et fichier vide supprimé', () async {
      av.recordedBytes = const [];
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      final path = clipService.state.recordingPath!;
      await toggle();

      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailed, isTrue);
      expect(clipService.state.recordingFailure, RecordingFailure.nothingRecorded);
      expect(av.dumpCount, 1, reason: 'le repli par le cache doit être tenté');
      expect(clipService.state.lastRecording, isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('un fichier réduit à son en-tête passe quand même par le repli', () async {
      // mpv ouvre le fichier et écrit l'en-tête du conteneur avant de renoncer :
      // le fichier existe, mais ne contient aucune image ni aucun son.
      av.recordedBytes = matroskaClip(512);
      av.dumpedBytes = matroskaClip();
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      final path = clipService.state.recordingPath!;
      await toggle();

      expect(av.dumpCount, 1, reason: 'un en-tête seul n’est pas un extrait');
      expect(File(path).lengthSync(), matroskaClip().length);
      expect(clipService.state.lastRecording, path);
      expect(clipService.state.recordingFailed, isFalse);
    });

    test('le cache ne rend qu’un en-tête : ce n’est pas un extrait', () async {
      // Écrit depuis le cache, le fichier est complet dès le retour : s'il n'a
      // que son en-tête de conteneur, il ne contient aucun paquet. L'annoncer
      // donnerait un extrait qui ne s'ouvre pas.
      av.recordedBytes = const [];
      av.dumpedBytes = matroskaClip(512);
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      final path = clipService.state.recordingPath!;
      await toggle();

      expect(av.dumpCount, 1);
      expect(clipService.state.recordingFailure, RecordingFailure.nothingRecorded);
      expect(clipService.state.lastRecording, isNull);
      expect(File(path).existsSync(), isFalse);
    });

    test('rien au fil de l’eau : le repli par le cache sauve l’extrait', () async {
      av.recordedBytes = const [];
      av.dumpedBytes = matroskaClip();
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      final path = clipService.state.recordingPath!;
      await toggle();

      expect(av.dumpCount, 1);
      expect(clipService.state.lastRecording, path);
      expect(clipService.state.recordingFailed, isFalse);
      expect(File(path).lengthSync(), greaterThan(0));
    });

    test('en pause, l’extrait est refusé et la raison est dite', () async {
      await clipService.openPath('/serie/ep1.mkv');
      bus.dispatch(const Pause());
      await settle();
      await clipService.idle;
      await toggle();

      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailure, RecordingFailure.notPlaying);
      expect(av.recordingPath, isNull, reason: 'le moteur n’est même pas sollicité');
      expect(clips.listSync(), isEmpty);
    });

    test('un document ne s’enregistre pas, et le dit', () async {
      await clipService.openPath('/docs/notes.pdf');
      await toggle();

      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailure, RecordingFailure.unsupportedMedia);
      expect(clips.listSync(), isEmpty);
    });

    test('dossier des captures inaccessible : refus immédiat, avec sa raison', () async {
      // Un fichier à la place du dossier : impossible d'y créer quoi que ce soit.
      final blocker = File(p.join(clips.path, 'pas-un-dossier'))..writeAsStringSync('x');
      final ownBus = PlayerCommandBus();
      final ownPlaylist = PlaylistService(bus: ownBus, scanner: scanner);
      final failing = PlaybackService(
        bus: ownBus,
        router: MediaRouter([av]),
        window: window,
        playlist: ownPlaylist,
        screenshots: ScreenshotService(defaultFolder: () async => Directory(blocker.path)),
        recordingCheckDelay: Duration.zero,
      );

      await failing.openPath('/serie/ep1.mkv');
      ownBus.dispatch(const ToggleRecording());
      await settle();
      await failing.idle;

      expect(failing.state.recording, isFalse);
      expect(failing.state.recordingFailure, RecordingFailure.folderUnavailable);
      expect(failing.state.status, PlaybackStatus.playing);

      await failing.dispose();
      await ownPlaylist.dispose();
      await ownBus.dispose();
    });

    test('changer de fichier arrête l’extrait et le garde', () async {
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      final path = clipService.state.recordingPath!;

      await clipService.openPath('/serie/ep2.mkv');
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.lastRecording, path);
      expect(File(path).existsSync(), isTrue);
    });

    test('la fin du fichier arrête l’extrait', () async {
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      av.finish();
      await settle();
      await clipService.idle;
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.lastRecording, isNotNull);
    });

    test('un moteur qui refuse : échec, rien en cours', () async {
      av.recordingRefusal = RecordingFailure.engineRefused;
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailed, isTrue);
      expect(clipService.state.recordingFailure, RecordingFailure.engineRefused);
      expect(av.recordingPath, isNull);
      expect(clips.listSync(), isEmpty);
    });

    test('un conteneur qui refuse ces pistes : la raison est dite telle quelle', () async {
      // mpv recopie les paquets sans les réencoder : tous les codecs n'ont pas
      // leur place dans un Matroska. Il le dit avant d'allumer le voyant.
      av.recordingRefusal = RecordingFailure.containerRefused;
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailure, RecordingFailure.containerRefused);
      expect(clips.listSync(), isEmpty);
    });

    test('le moteur ne peut pas écrire dans le dossier : la raison passe telle quelle',
        () async {
      // Le dossier existe (le service a su y calculer un nom), mais le moteur
      // n'y écrit pas : disque plein, droits en lecture seule, volume retiré
      // entre-temps. Le message doit désigner le dossier, pas le moteur.
      av.recordingRefusal = RecordingFailure.folderUnavailable;
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailure, RecordingFailure.folderUnavailable);
      expect(clips.listSync(), isEmpty);
    });

    test('le moteur dit que rien ne défile : refus, même en état « en lecture »', () async {
      // L'état dit « en lecture », mais la position du moteur, elle, ne bouge
      // pas : c'est le moteur qui tranche, et son refus passe tel quel.
      av.recordingRefusal = RecordingFailure.notPlaying;
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailure, RecordingFailure.notPlaying);
    });

    test('le moteur retrouve ses réglages, extrait réussi ou manqué', () async {
      await clipService.openPath('/serie/ep1.mkv');
      await toggle();
      await toggle();
      expect(av.releaseCount, 1, reason: 'après un extrait écrit');

      av.recordingRefusal = RecordingFailure.engineRefused;
      await toggle();
      expect(av.releaseCount, 2, reason: 'après un démarrage refusé');
    });

    test('sans média, la commande ne fait rien', () async {
      await toggle();
      expect(clipService.state.recording, isFalse);
      expect(clipService.state.recordingFailed, isFalse);
      expect(clipService.state.recordingFailure, RecordingFailure.none);
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
      // Sans image : le bandeau, dans le coin bas-droit de la fenêtre d'avant
      // (à 24 px des bords), sans verrou de ratio.
      expect(window.bounds, const Rect.fromLTWH(876, 684, 400, 132));
      expect(window.minimumSize, WindowSizes.miniAudioMinimum);
      expect(window.aspectRatio, 0);

      bus.dispatch(const ToggleMiniPlayer());
      await settle();

      expect(service.state.miniPlayer, isFalse);
      expect(service.state.alwaysOnTop, isFalse);
      expect(window.alwaysOnTop, isFalse);
      expect(window.bounds, const Rect.fromLTWH(100, 80, 1200, 760));
      expect(window.minimumSize, WindowSizes.mainMinimum);
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

    test('un document déposé sur le mini-lecteur rend la fenêtre entière', () async {
      window.bounds = const Rect.fromLTWH(100, 80, 1200, 760);
      await service.openPath('/serie/ep1.mkv');
      bus.dispatch(const ToggleMiniPlayer());
      await settle();
      expect(service.state.miniPlayer, isTrue);

      // Une autre vidéo : le mini-lecteur sait l'afficher, il reste.
      await service.openPath('/serie/ep2.mkv');
      expect(service.state.miniPlayer, isTrue);

      // Un PDF : il faut la fenêtre entière pour le lire.
      await service.openPath('/serie/notes.pdf');
      expect(service.state.miniPlayer, isFalse);
      expect(window.bounds, const Rect.fromLTWH(100, 80, 1200, 760));
      expect(window.minimumSize, WindowSizes.mainMinimum);
    });

    group('à la forme de l’image', () {
      // Bus, fenêtre et réglages propres : le service du setUp général écoute
      // le bus partagé et réagirait aussi aux commandes.
      late PlayerCommandBus ownBus;
      late FakeAvController ownAv;
      late FakeWindowService ownWindow;
      late MemorySettingsStore store;
      late PlaylistService ownPlaylist;
      late PlaybackService ownService;

      const mainBounds = Rect.fromLTWH(100, 80, 1200, 760);

      setUp(() {
        ownBus = PlayerCommandBus();
        // Une vidéo 16:9 dont l'image est connue dès l'ouverture.
        ownAv = FakeAvController()
          ..hasVideo = true
          ..videoWidth = 1920
          ..videoHeight = 1080;
        ownWindow = FakeWindowService()..bounds = mainBounds;
        store = MemorySettingsStore();
        ownPlaylist = PlaylistService(bus: ownBus, scanner: FakeFolderScanner(folders));
        ownService = PlaybackService(
          bus: ownBus,
          router: MediaRouter([ownAv]),
          window: ownWindow,
          playlist: ownPlaylist,
          settings: store,
        );
      });

      tearDown(() async {
        await ownService.dispose();
        await ownPlaylist.dispose();
        await ownBus.dispose();
      });

      Future<void> drain() async {
        await settle();
        await ownService.idle;
      }

      Future<void> send(PlayerCommand command) async {
        ownBus.dispatch(command);
        await drain();
      }

      Future<void> play([String path = '/serie/ep1.mkv']) async {
        await ownService.openPath(path);
        await drain();
      }

      test('une vidéo 16:9 : 400 × 225 dans le coin bas-droit, ratio verrouillé', () async {
        await play();
        await send(const ToggleMiniPlayer());

        expect(ownService.state.miniPlayer, isTrue);
        expect(ownService.state.alwaysOnTop, isTrue);
        // (1300 - 400 - 24, 840 - 225 - 24) : à 24 px des bords de la fenêtre
        // d'avant.
        expectRect(ownWindow.bounds, 876, 591, 400, 225);
        expect(ownWindow.aspectRatio, closeTo(16 / 9, 1e-9));
        expectSize(ownWindow.minimumSize, 200, 112.5);
      });

      test('une vidéo verticale 9:16 : 225 × 400', () async {
        ownAv
          ..videoWidth = 1080
          ..videoHeight = 1920;
        await play();
        await send(const ToggleMiniPlayer());

        expectRect(ownWindow.bounds, 1051, 416, 225, 400);
        expect(ownWindow.aspectRatio, closeTo(9 / 16, 1e-9));
        expectSize(ownWindow.minimumSize, 112.5, 200);
      });

      test('sortir : verrou levé, géométrie et plancher rendus', () async {
        await play();
        await send(const ToggleMiniPlayer());
        await send(const ToggleMiniPlayer());

        expect(ownService.state.miniPlayer, isFalse);
        expect(ownWindow.aspectRatio, 0);
        expect(ownWindow.bounds, mainBounds);
        expect(ownWindow.minimumSize, WindowSizes.mainMinimum);
        expect(ownWindow.alwaysOnTop, isFalse);
      });

      test('une fenêtre agrandie est désagrandie, puis agrandie de nouveau à la sortie', () async {
        ownWindow
          ..maximized = true
          ..bounds = const Rect.fromLTWH(0, 0, 1920, 1040);
        await play();
        await send(const ToggleMiniPlayer());

        expect(ownWindow.maximized, isFalse);
        // Rangé dans le coin de l'écran qu'occupait la fenêtre agrandie.
        expectRect(ownWindow.bounds, 1496, 791, 400, 225);

        await send(const ToggleMiniPlayer());
        expect(ownWindow.maximized, isTrue);
        expect(ownWindow.bounds, const Rect.fromLTWH(0, 0, 1920, 1040));
        expect(ownWindow.aspectRatio, 0);
      });

      test('entrer avant que l’image soit connue : le bandeau, puis la forme de l’image', () async {
        ownAv
          ..videoWidth = 0
          ..videoHeight = 0;
        await play();
        await send(const ToggleMiniPlayer());
        expectRect(ownWindow.bounds, 876, 684, 400, 132);
        expect(ownWindow.aspectRatio, 0);

        ownAv.reportVideoSize(1920, 1080);
        await drain();
        // Le coin bas-droit ne bouge pas : le mini-lecteur reste rangé.
        expectRect(ownWindow.bounds, 876, 591, 400, 225);
        expect(ownWindow.aspectRatio, closeTo(16 / 9, 1e-9));
        expectSize(ownWindow.minimumSize, 200, 112.5);
      });

      test('l’image change de ratio : même grand côté, nouveau verrou, coin gardé', () async {
        await play();
        await send(const ToggleMiniPlayer());

        ownAv.reportVideoSize(1080, 1920);
        await drain();

        expectRect(ownWindow.bounds, 1051, 416, 225, 400);
        expect(ownWindow.aspectRatio, closeTo(9 / 16, 1e-9));
        expectSize(ownWindow.minimumSize, 112.5, 200);
      });

      test('fichier suivant : pas de bandeau en attendant son image, puis sa forme au grand côté choisi',
          () async {
        await play();
        await send(const ToggleMiniPlayer());
        // L'utilisateur agrandit le mini-lecteur (ratio gardé, coin bas-droit
        // en place).
        ownWindow.bounds = const Rect.fromLTWH(676, 478.5, 600, 337.5);

        // Vidéo suivante : son image n'est pas connue à l'ouverture.
        ownAv
          ..videoWidth = 0
          ..videoHeight = 0;
        await play('/serie/ep2.mkv');
        expect(ownWindow.bounds, const Rect.fromLTWH(676, 478.5, 600, 337.5));
        expect(ownWindow.aspectRatio, closeTo(16 / 9, 1e-9));

        // Elle arrive en 4:3 : même grand côté, même coin.
        ownAv.reportVideoSize(1440, 1080);
        await drain();
        expectRect(ownWindow.bounds, 676, 366, 600, 450);
        expect(ownWindow.aspectRatio, closeTo(4 / 3, 1e-9));
      });

      test('les battements de position ne touchent pas la fenêtre', () async {
        await play();
        await send(const ToggleMiniPlayer());
        var changes = 0;
        final sub = ownWindow.geometryChanges.listen((_) => changes++);

        ownAv
          ..advanceTo(const Duration(seconds: 5))
          ..advanceTo(const Duration(seconds: 6))
          // Mêmes dimensions republiées : même forme, rien à faire.
          ..reportVideoSize(1920, 1080);
        await drain();

        expect(changes, 0);
        expectRect(ownWindow.bounds, 876, 591, 400, 225);
        await sub.cancel();
      });

      test('de la vidéo au son : le bandeau, sans verrou', () async {
        await play();
        await send(const ToggleMiniPlayer());

        ownAv
          ..hasVideo = false
          ..videoWidth = 0
          ..videoHeight = 0;
        await play('/serie/generique.mp3');

        expect(ownService.state.miniPlayer, isTrue);
        expectRect(ownWindow.bounds, 876, 684, 400, 132);
        expect(ownWindow.aspectRatio, 0);
        expect(ownWindow.minimumSize, WindowSizes.miniAudioMinimum);
      });

      test('du son à la vidéo : la forme de l’image, au grand côté des réglages', () async {
        await store.setMiniLongSide(480);
        ownAv
          ..hasVideo = false
          ..videoWidth = 0
          ..videoHeight = 0;
        await play('/serie/generique.mp3');
        await send(const ToggleMiniPlayer());
        expectRect(ownWindow.bounds, 876, 684, 400, 132);

        ownAv
          ..hasVideo = true
          ..videoWidth = 1920
          ..videoHeight = 1080;
        await play('/serie/ep1.mkv');
        expectRect(ownWindow.bounds, 796, 546, 480, 270);
        expect(ownWindow.aspectRatio, closeTo(16 / 9, 1e-9));
      });

      test('la place et la taille retenues sont reprises', () async {
        await store.setMiniPosition(const Offset(50, 60));
        await store.setMiniLongSide(600);
        await play();
        await send(const ToggleMiniPlayer());

        expectRect(ownWindow.bounds, 50, 60, 600, 337.5);
        expect(ownWindow.aspectRatio, closeTo(16 / 9, 1e-9));
      });

      test('le plein écran depuis le mini-lecteur passe par la fenêtre entière', () async {
        await play();
        await send(const ToggleMiniPlayer());
        await send(const ToggleFullscreen());

        expect(ownService.state.miniPlayer, isFalse);
        expect(ownService.state.fullscreen, isTrue);
        expect(ownWindow.fullscreen, isTrue);
        expect(ownWindow.aspectRatio, 0);
        expect(ownWindow.bounds, mainBounds);
        expect(ownWindow.minimumSize, WindowSizes.mainMinimum);
      });

      test('des bascules rapprochées ne s’entremêlent pas', () async {
        await play();
        for (var i = 0; i < 4; i++) {
          ownBus.dispatch(const ToggleMiniPlayer());
        }
        await drain();

        expect(ownService.state.miniPlayer, isFalse);
        expect(ownWindow.bounds, mainBounds);
        expect(ownWindow.aspectRatio, 0);
        expect(ownWindow.minimumSize, WindowSizes.mainMinimum);
        expect(ownWindow.alwaysOnTop, isFalse);
      });
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
    expect(restored.resumeOffer, isNull);
    expect(restored.screenshotFailed, isFalse);
  });

  test('PlaybackState — l’offre de reprise survit au JSON', () {
    const state = PlaybackState(resumeOffer: ResumeOffer(page: 12));
    expect(PlaybackState.fromJson(state.toJson()).resumeOffer, const ResumeOffer(page: 12));
  });

  // --- Phase 6 --------------------------------------------------------------------

  group('Préférences', () {
    // Chaque test a son propre bus : le service du setUp général écoute le bus
    // partagé et réagirait aussi aux commandes.
    late PlayerCommandBus ownBus;
    late FakeAvController ownAv;
    late FakeDocController ownDoc;
    late MemoryHistoryStore ownHistory;
    late MemorySettingsStore store;
    PlaylistService? ownPlaylist;
    PlaybackService? ownService;

    PlaybackService build({
      AppPreferences prefs = AppPreferences.defaults,
      double? lastVolume,
    }) {
      store = MemorySettingsStore(preferences: prefs);
      if (lastVolume != null) store.setLastVolume(lastVolume);
      ownPlaylist = PlaylistService(bus: ownBus, scanner: FakeFolderScanner(folders));
      return ownService = PlaybackService(
        bus: ownBus,
        router: MediaRouter([ownAv, ownDoc]),
        window: FakeWindowService(),
        playlist: ownPlaylist!,
        history: ownHistory,
        settings: store,
      );
    }

    Future<void> drain(PlaybackService s) async {
      await settle();
      await s.idle;
    }

    setUp(() {
      ownBus = PlayerCommandBus();
      ownAv = FakeAvController();
      ownDoc = FakeDocController();
      ownHistory = MemoryHistoryStore();
    });

    tearDown(() async {
      await ownService?.dispose();
      await ownPlaylist?.dispose();
      await ownBus.dispose();
      ownService = null;
      ownPlaylist = null;
    });

    group('au démarrage', () {
      test('volume fixe', () {
        final s = build(
          prefs: const AppPreferences(startupVolume: StartupVolume.fixed, fixedVolume: 30),
          lastVolume: 70,
        );
        expect(s.state.volume, 30);
      });

      test('dernier volume', () {
        expect(build(lastVolume: 55).state.volume, 55);
      });

      test('dernier volume inconnu : volume par défaut', () {
        expect(build().state.volume, const PlaybackState().volume);
      });

      test('vitesse, sous-titres, égaliseur et documents', () {
        final s = build(
          prefs: AppPreferences(
            defaultSpeed: 1.5,
            subtitleScale: 1.4,
            equalizerEnabled: true,
            equalizerGains: Equalizer.presets['bass']!,
            readingDark: true,
            pdfLayout: DocumentLayout.paged,
          ),
        );
        expect(s.state.speed, 1.5);
        expect(s.state.subtitleScale, 1.4);
        expect(s.state.equalizerEnabled, isTrue);
        expect(s.state.equalizerPreset, 'bass');
        expect(s.state.readingDark, isTrue);
        expect(s.state.documentLayout, DocumentLayout.paged);
      });
    });

    test('le dernier volume est mémorisé, après une courte attente', () async {
      final s = build();
      ownBus.dispatch(const SetVolume(40));
      await drain(s);
      expect(store.lastVolume, isNull, reason: 'écriture différée');
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(store.lastVolume, 40);
    });

    test('fermer le service enregistre aussitôt une sauvegarde en attente', () async {
      final s = build();
      ownBus.dispatch(const SetVolume(25));
      await drain(s);
      await s.dispose();
      ownService = null;
      expect(store.lastVolume, 25);
    });

    test('UpdatePreferences enregistre, publie et aligne l’état', () async {
      final s = build();
      final published = <AppPreferences>[];
      final sub = s.preferencesChanges.listen(published.add);
      final next = AppPreferences.defaults.copyWith(
        seekStepSeconds: 30,
        resumePolicy: ResumePolicy.never,
        subtitleScale: 1.8,
        readingDark: true,
        pdfLayout: DocumentLayout.paged,
        equalizerEnabled: true,
        equalizerGains: Equalizer.presets['rock'],
      );

      ownBus.dispatch(UpdatePreferences.between(s.preferences, next));
      await drain(s);

      expect(store.preferences, next);
      expect(published.last, next);
      expect(s.preferences, next);
      expect(s.state.subtitleScale, 1.8);
      expect(s.state.readingDark, isTrue);
      expect(s.state.documentLayout, DocumentLayout.paged);
      expect(s.state.equalizerEnabled, isTrue);
      expect(s.state.equalizerPreset, 'rock');

      // La sauvegarde différée des réglages suivis en direct n'annule rien.
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(store.preferences, next);
      await sub.cancel();
    });

    test('deux changements rapprochés ne s’écrasent pas', () async {
      final s = build();
      // Les deux commandes partent avant que la première soit traitée.
      ownBus.dispatch(const UpdatePreferences({'seekStepSeconds': 30}));
      ownBus.dispatch(const UpdatePreferences({'themeMode': 'light'}));
      await drain(s);
      expect(store.preferences.seekStepSeconds, 30);
      expect(store.preferences.themeMode, AppThemeMode.light);
    });

    test('SetScreenshotFolder passe par le bus', () async {
      final s = build();
      ownBus.dispatch(const SetScreenshotFolder('/captures'));
      await drain(s);
      expect(store.screenshotFolder, '/captures');
      ownBus.dispatch(const SetScreenshotFolder(null));
      await drain(s);
      expect(store.screenshotFolder, isNull);
    });

    test('effacer les récents, puis les positions', () async {
      final s = build();
      await ownHistory.savePosition(
        '/serie/ep1.mkv',
        position: const Duration(minutes: 4),
        duration: const Duration(minutes: 10),
        now: DateTime(2026, 9, 14),
      );

      ownBus.dispatch(const ClearRecentFiles());
      await drain(s);
      expect(ownHistory.recent(), isEmpty);
      expect(ownHistory.entryFor('/serie/ep1.mkv')!.resumePosition, const Duration(minutes: 4));

      ownBus.dispatch(const ClearResumePositions());
      await drain(s);
      expect(ownHistory.entryFor('/serie/ep1.mkv')!.resumePosition, isNull);
    });

    group('politique de reprise', () {
      Future<void> remember() => ownHistory.savePosition(
            '/serie/ep1.mkv',
            position: const Duration(minutes: 4),
            duration: const Duration(minutes: 10),
            now: DateTime(2026, 9, 14),
          );

      test('« demander » : une offre est publiée, rien n’est appliqué', () async {
        final s = build(prefs: const AppPreferences(resumePolicy: ResumePolicy.ask));
        await remember();
        await s.openPath('/serie/ep1.mkv');
        await settle();

        expect(s.state.resumeOffer, const ResumeOffer(position: Duration(minutes: 4)));
        expect(ownAv.handled.whereType<SeekAbsolute>(), isEmpty);
        expect(s.state.position, Duration.zero);
      });

      test('accepter applique la position et retire l’offre', () async {
        final s = build(prefs: const AppPreferences(resumePolicy: ResumePolicy.ask));
        await remember();
        await s.openPath('/serie/ep1.mkv');
        ownBus.dispatch(const AcceptResume());
        await drain(s);

        expect(ownAv.handled, contains(const SeekAbsolute(Duration(minutes: 4))));
        expect(s.state.position, const Duration(minutes: 4));
        expect(s.state.resumeOffer, isNull);
      });

      test('refuser retire l’offre sans rien appliquer', () async {
        final s = build(prefs: const AppPreferences(resumePolicy: ResumePolicy.ask));
        await remember();
        await s.openPath('/serie/ep1.mkv');
        ownBus.dispatch(const DeclineResume());
        await drain(s);

        expect(s.state.resumeOffer, isNull);
        expect(ownAv.handled.whereType<SeekAbsolute>(), isEmpty);
      });

      test('ouvrir un autre fichier retire l’offre', () async {
        final s = build(prefs: const AppPreferences(resumePolicy: ResumePolicy.ask));
        await remember();
        await s.openPath('/serie/ep1.mkv');
        await s.openPath('/serie/ep2.mkv');
        expect(s.state.resumeOffer, isNull);
      });

      test('« jamais » : ni reprise ni offre', () async {
        final s = build(prefs: const AppPreferences(resumePolicy: ResumePolicy.never));
        await remember();
        await s.openPath('/serie/ep1.mkv');
        await settle();

        expect(s.state.resumeOffer, isNull);
        expect(ownAv.handled.whereType<SeekAbsolute>(), isEmpty);
      });

      test('« auto » reste le comportement par défaut', () async {
        final s = build();
        await remember();
        await s.openPath('/serie/ep1.mkv');
        await settle();

        expect(s.state.resumeOffer, isNull);
        expect(ownAv.handled, contains(const SeekAbsolute(Duration(minutes: 4))));
      });

      test('document, « demander » : offre de page, acceptée', () async {
        final s = build(prefs: const AppPreferences(resumePolicy: ResumePolicy.ask));
        await ownHistory.saveDocumentPosition(
          '/docs/manuel.pdf',
          page: 12,
          pageCount: 40,
          now: DateTime(2026, 9, 14),
        );
        await s.openPath('/docs/manuel.pdf');
        await settle();
        expect(s.state.resumeOffer, const ResumeOffer(page: 12));
        expect(s.state.currentPage, 1);

        ownBus.dispatch(const AcceptResume());
        await drain(s);
        expect(ownDoc.handled, contains(const GoToPage(12)));
        expect(s.state.currentPage, 12);
      });
    });
  });

  test('une capture impossible est signalée, sans interrompre la lecture', () async {
    final shots = Directory.systemTemp.createTempSync('omnia_blocked_');
    // Un fichier à la place du dossier : impossible d'y créer quoi que ce soit.
    final blocker = File(p.join(shots.path, 'pas-un-dossier'))..writeAsStringSync('x');
    final ownBus = PlayerCommandBus();
    final ownPlaylist = PlaylistService(bus: ownBus, scanner: scanner);
    final failing = PlaybackService(
      bus: ownBus,
      router: MediaRouter([av]),
      window: window,
      playlist: ownPlaylist,
      screenshots: ScreenshotService(defaultFolder: () async => Directory(blocker.path)),
    );

    await failing.openPath('/serie/ep1.mkv');
    ownBus.dispatch(const TakeScreenshot());
    await settle();
    await failing.idle;

    expect(failing.state.screenshotFailed, isTrue);
    expect(failing.state.lastScreenshot, isNull);
    expect(failing.state.status, PlaybackStatus.playing);

    await failing.dispose();
    await ownPlaylist.dispose();
    await ownBus.dispose();
    try {
      shots.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });
}
