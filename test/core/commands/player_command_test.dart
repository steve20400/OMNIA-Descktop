import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/end_of_playback_mode.dart';

void main() {
  group('PlayerCommand — sérialisation JSON', () {
    // Une instance de chaque commande : l'aller-retour JSON doit être exact.
    const samples = <PlayerCommand>[
      Play(),
      Pause(),
      TogglePlay(),
      Stop(),
      SeekRelative(-5),
      SeekAbsolute(Duration(minutes: 1, seconds: 30)),
      SetVolume(42.5),
      VolumeRelative(-5),
      ToggleMute(),
      NextFile(),
      PreviousFile(),
      SetSpeed(1.5),
      SpeedRelative(0.25),
      NextPage(),
      PreviousPage(),
      GoToPage(12),
      SetZoom(1.25),
      ToggleFullscreen(),
      ExitFullscreen(),
      TakeScreenshot(),
      SetLoopMode(EndOfPlaybackMode.loopFolder),
      CycleLoopMode(),
      ToggleAlwaysOnTop(),
      ToggleSidePanel(),
      OpenFile('/videos/ep2.mkv'),
      OpenFolder('/videos'),
    ];

    for (final command in samples) {
      test('${command.type} survit à toJson → fromJson', () {
        final json = command.toJson();
        expect(json['type'], command.type);
        final restored = PlayerCommand.fromJson(json);
        expect(restored, equals(command));
        expect(restored.hashCode, command.hashCode);
        expect(restored.runtimeType, command.runtimeType);
      });
    }

    test('chaque commande a un type unique', () {
      final types = samples.map((c) => c.type).toSet();
      expect(types.length, samples.length);
    });

    test('les arguments sont conservés', () {
      final seek = PlayerCommand.fromJson({'type': 'seekAbsolute', 'positionMs': 90000});
      expect(seek, isA<SeekAbsolute>());
      expect((seek as SeekAbsolute).position, const Duration(seconds: 90));

      final page = PlayerCommand.fromJson({'type': 'goToPage', 'page': 7});
      expect((page as GoToPage).page, 7);
    });

    test('un entier est accepté pour un argument décimal', () {
      final v = PlayerCommand.fromJson({'type': 'setVolume', 'volume': 80});
      expect((v as SetVolume).volume, 80.0);
    });

    test('type inconnu → FormatException', () {
      expect(
        () => PlayerCommand.fromJson({'type': 'teleport'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('argument manquant → FormatException', () {
      expect(
        () => PlayerCommand.fromJson({'type': 'seekRelative'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => PlayerCommand.fromJson({'type': 'openFile'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('mode de boucle inconnu → repli sur « suivant »', () {
      final c = PlayerCommand.fromJson({'type': 'setLoopMode', 'mode': '???'});
      expect((c as SetLoopMode).mode, EndOfPlaybackMode.next);
    });

    test('égalité structurelle', () {
      expect(const SeekRelative(5), equals(const SeekRelative(5)));
      expect(const SeekRelative(5), isNot(equals(const SeekRelative(-5))));
      expect(const Play(), isNot(equals(const Pause())));
    });
  });
}
