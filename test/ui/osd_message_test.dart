import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/models/end_of_playback_mode.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/ui/osd/osd_message.dart';

void main() {
  const playing = PlaybackState(
    file: MediaFile(path: '/serie/ep2.mkv', type: MediaType.video),
    status: PlaybackStatus.playing,
    position: Duration(minutes: 1, seconds: 5),
    duration: Duration(minutes: 40),
    volume: 65,
    speed: 1.25,
  );
  const idle = PlaybackState();

  group('osdWantedFor', () {
    test('clavier, ligne de commande, système, télécommande : toujours', () {
      for (final source in [
        CommandSource.keyboard,
        CommandSource.cli,
        CommandSource.system,
        CommandSource.remote,
      ]) {
        expect(osdWantedFor(source, fullscreen: false), isTrue, reason: source.name);
        expect(osdWantedFor(source, fullscreen: true), isTrue, reason: source.name);
      }
    });

    test('souris : seulement en plein écran', () {
      expect(osdWantedFor(CommandSource.ui, fullscreen: false), isFalse);
      expect(osdWantedFor(CommandSource.ui, fullscreen: true), isTrue);
    });
  });

  group('osdFor', () {
    test('avance / recul', () {
      final m = osdFor(const SeekRelative(5), playing);
      expect(m, isA<OsdSeek>());
      final seek = m! as OsdSeek;
      expect(seek.deltaSeconds, 5);
      expect(seek.position, const Duration(minutes: 1, seconds: 5));
      expect(seek.duration, const Duration(minutes: 40));
    });

    test('seek absolu : pas de delta', () {
      final m = osdFor(const SeekAbsolute(Duration(minutes: 10)), playing)! as OsdSeek;
      expect(m.deltaSeconds, 0);
    });

    test('volume et sourdine', () {
      final v = osdFor(const VolumeRelative(5), playing)! as OsdVolume;
      expect(v.volume, 65);
      expect(v.muted, isFalse);

      final muted = osdFor(const ToggleMute(), playing.copyWith(muted: true))! as OsdVolume;
      expect(muted.muted, isTrue);
    });

    test('le volume s’affiche même sans fichier', () {
      expect(osdFor(const SetVolume(30), idle.copyWith(volume: 30)), isA<OsdVolume>());
    });

    test('vitesse', () {
      final s = osdFor(const SpeedRelative(0.25), playing)! as OsdSpeed;
      expect(s.speed, 1.25);
    });

    test('lecture / pause', () {
      final p = osdFor(const TogglePlay(), playing)! as OsdPlayState;
      expect(p.playing, isTrue);
      final paused = osdFor(const TogglePlay(), playing.copyWith(status: PlaybackStatus.paused))!
          as OsdPlayState;
      expect(paused.playing, isFalse);
    });

    test('changement de fichier', () {
      final n = osdFor(const NextFile(), playing)! as OsdFileChanged;
      expect(n.name, 'ep2.mkv');
      expect(n.forward, isTrue);
      final p = osdFor(const PreviousFile(), playing)! as OsdFileChanged;
      expect(p.forward, isFalse);
    });

    test('mode de fin, premier plan, plein écran', () {
      expect(
        (osdFor(const CycleLoopMode(), playing.copyWith(endMode: EndOfPlaybackMode.shuffle))!
                as OsdEndMode)
            .mode,
        EndOfPlaybackMode.shuffle,
      );
      expect(
        (osdFor(const ToggleAlwaysOnTop(), playing.copyWith(alwaysOnTop: true))!
                as OsdAlwaysOnTop)
            .enabled,
        isTrue,
      );
      expect(
        (osdFor(const ToggleFullscreen(), playing.copyWith(fullscreen: true))! as OsdFullscreen)
            .enabled,
        isTrue,
      );
    });

    test('sans fichier, les actions de lecture ne produisent rien', () {
      expect(osdFor(const SeekRelative(5), idle), isNull);
      expect(osdFor(const TogglePlay(), idle), isNull);
      expect(osdFor(const SpeedRelative(0.25), idle), isNull);
      expect(osdFor(const NextFile(), idle), isNull);
    });

    test('capture : chemin enregistré, ou échec signalé', () {
      expect(
        osdFor(const TakeScreenshot(), playing.copyWith(lastScreenshot: '/c/a.png')),
        isA<OsdScreenshot>(),
      );
      expect(
        osdFor(const TakeScreenshot(), playing.copyWith(screenshotFailed: true)),
        isA<OsdScreenshotFailed>(),
      );
      // Rien d'enregistré (fichier audio) : pas de message.
      expect(osdFor(const TakeScreenshot(), playing), isNull);
    });

    test('les commandes sans retour visuel ne produisent rien', () {
      expect(osdFor(const OpenFile('/x.mkv'), playing), isNull);
      expect(osdFor(const SetPlaylistQuery('a'), playing), isNull);
      expect(osdFor(const ToggleSidePanel(), playing), isNull);
      expect(osdFor(const Stop(), playing), isNull);
    });
  });
}
