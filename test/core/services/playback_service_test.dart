import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/models/end_of_playback_mode.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/window_service.dart';

/// Contrôleur factice : enregistre ce qu'il reçoit et simule une lecture.
class FakeAvController implements MediaController {
  final List<MediaFile> opened = [];
  final List<PlayerCommand> handled = [];
  int closeCount = 0;
  PlaybackStateSink? sink;

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
        duration: const Duration(minutes: 10),
        clearError: true,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    handled.add(command);
    if (command is Pause) {
      sink?.update((s) => s.copyWith(status: PlaybackStatus.paused));
    }
    return true;
  }

  @override
  Future<void> close() async {
    closeCount++;
    sink?.update((s) => s.copyWith(clearFile: true, status: PlaybackStatus.idle));
  }

  @override
  Future<void> dispose() async {}
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late PlayerCommandBus bus;
  late FakeAvController av;
  late FakeWindowService window;
  late PlaybackService service;

  setUp(() {
    bus = PlayerCommandBus();
    av = FakeAvController();
    window = FakeWindowService();
    service = PlaybackService(bus: bus, router: MediaRouter([av]), window: window);
  });

  tearDown(() async {
    await service.dispose();
    await bus.dispose();
  });

  group('PlaybackService — ouverture', () {
    test('OpenFile route vers le contrôleur du type', () async {
      bus.dispatch(const OpenFile('/videos/ep1.mkv'));
      await settle();

      expect(av.opened.single.path, '/videos/ep1.mkv');
      expect(av.opened.single.type, MediaType.video);
      expect(service.state.status, PlaybackStatus.playing);
      expect(service.state.file?.name, 'ep1.mkv');
      expect(service.activeController, same(av));
    });

    test('extension inconnue → erreur unsupportedFormat, pas de crash', () async {
      bus.dispatch(const OpenFile('/x/archive.zip'));
      await settle();

      expect(av.opened, isEmpty);
      expect(service.state.status, PlaybackStatus.error);
      expect(service.state.error?.code, PlaybackErrorCode.unsupportedFormat);
      expect(service.state.file?.name, 'archive.zip');
    });

    test('ouvrir un second fichier sur le même contrôleur ne le ferme pas', () async {
      bus.dispatch(const OpenFile('/a.mp4'));
      bus.dispatch(const OpenFile('/b.mp3'));
      await settle();

      expect(av.opened.map((f) => f.name), ['a.mp4', 'b.mp3']);
      expect(av.closeCount, 0);
      expect(service.state.file?.name, 'b.mp3');
    });

    test('le flux d’état émet chaque changement', () async {
      final statuses = <PlaybackStatus>[];
      final sub = service.stream.listen((s) => statuses.add(s.status));
      bus.dispatch(const OpenFile('/a.mp4'));
      bus.dispatch(const Pause());
      await settle();

      expect(statuses, [PlaybackStatus.playing, PlaybackStatus.paused]);
      await sub.cancel();
    });
  });

  group('PlaybackService — délégation', () {
    test('les commandes média sont transmises au contrôleur actif', () async {
      bus.dispatch(const OpenFile('/a.mp4'));
      bus.dispatch(const SeekRelative(5));
      bus.dispatch(const SetVolume(50));
      bus.dispatch(const ToggleMute());
      await settle();

      expect(av.handled, [const SeekRelative(5), const SetVolume(50), const ToggleMute()]);
    });

    test('sans fichier ouvert, les commandes média sont ignorées', () async {
      bus.dispatch(const TogglePlay());
      await settle();
      expect(av.handled, isEmpty);
      expect(service.state.status, PlaybackStatus.idle);
    });

    test('les commandes arrivent dans l’ordre malgré l’asynchrone', () async {
      bus.dispatch(const OpenFile('/a.mp4'));
      for (var i = 0; i < 20; i++) {
        bus.dispatch(SeekRelative(i.toDouble()));
      }
      await settle();
      expect(
        av.handled.whereType<SeekRelative>().map((c) => c.seconds).toList(),
        List.generate(20, (i) => i.toDouble()),
      );
    });

    test('Stop ferme le contrôleur et revient à l’état vide', () async {
      bus.dispatch(const OpenFile('/a.mp4'));
      bus.dispatch(const Stop());
      await settle();

      expect(av.closeCount, 1);
      expect(service.state.hasFile, isFalse);
      expect(service.state.status, PlaybackStatus.idle);
      expect(service.activeController, isNull);
    });
  });

  group('PlaybackService — fenêtre et modes', () {
    test('ToggleFullscreen pilote la fenêtre et l’état', () async {
      bus.dispatch(const ToggleFullscreen());
      await settle();
      expect(window.fullscreen, isTrue);
      expect(service.state.fullscreen, isTrue);

      bus.dispatch(const ToggleFullscreen());
      await settle();
      expect(window.fullscreen, isFalse);
      expect(service.state.fullscreen, isFalse);
    });

    test('ExitFullscreen ne fait rien hors plein écran', () async {
      bus.dispatch(const ExitFullscreen());
      await settle();
      expect(window.fullscreen, isFalse);
      expect(service.state.fullscreen, isFalse);
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
  });

  group('PlaybackService — dossier', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('omnia_test_');
      for (final name in ['b.mp4', 'a.mkv', 'notes.txt', 'ignore.zip']) {
        await File('${dir.path}${Platform.pathSeparator}$name').writeAsString('x');
      }
    });

    tearDown(() => dir.delete(recursive: true));

    test('OpenFolder lit le premier fichier lisible par ordre de nom', () async {
      bus.dispatch(OpenFolder(dir.path));
      await settle();
      expect(av.opened.single.name, 'a.mkv');
    });

    test('dossier inexistant → erreur sans crash', () async {
      bus.dispatch(OpenFolder('${dir.path}/nope'));
      await settle();
      expect(service.state.status, PlaybackStatus.error);
      expect(service.state.error?.code, PlaybackErrorCode.permissionDenied);
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
      endMode: EndOfPlaybackMode.repeatOne,
      fullscreen: true,
      playlist: ['/a/b.mkv', '/a/c.mkv'],
      playlistIndex: 0,
      error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: 'x'),
    );
    final restored = PlaybackState.fromJson(state.toJson());
    expect(restored.toJson(), state.toJson());
    expect(restored.file, state.file);
    expect(restored.progress, closeTo(42 / 180, 1e-9));
    expect(restored.remaining, const Duration(minutes: 2, seconds: 18));
  });
}
