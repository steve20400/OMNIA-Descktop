import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/playback_state.dart';

/// Ce que l'OSD (affichage à l'écran) doit montrer après une action.
///
/// Données structurées, sans texte ni icône : la mise en forme et la
/// traduction appartiennent au widget. Ce modèle est ainsi testable seul.
sealed class OsdMessage {
  const OsdMessage();
}

/// Avance ou recul, avec la position atteinte.
final class OsdSeek extends OsdMessage {
  const OsdSeek({
    required this.deltaSeconds,
    required this.position,
    required this.duration,
  });
  final double deltaSeconds;
  final Duration position;
  final Duration duration;
}

/// Volume après réglage, 0–100, et état de la sourdine.
final class OsdVolume extends OsdMessage {
  const OsdVolume({required this.volume, required this.muted});
  final double volume;
  final bool muted;
}

final class OsdSpeed extends OsdMessage {
  const OsdSpeed(this.speed);
  final double speed;
}

final class OsdPlayState extends OsdMessage {
  const OsdPlayState({required this.playing});
  final bool playing;
}

/// Changement de fichier par la playlist.
final class OsdFileChanged extends OsdMessage {
  const OsdFileChanged({required this.name, required this.forward});
  final String name;
  final bool forward;
}

final class OsdEndMode extends OsdMessage {
  const OsdEndMode(this.mode);
  final EndOfPlaybackMode mode;
}

final class OsdAlwaysOnTop extends OsdMessage {
  const OsdAlwaysOnTop({required this.enabled});
  final bool enabled;
}

final class OsdFullscreen extends OsdMessage {
  const OsdFullscreen({required this.enabled});
  final bool enabled;
}

/// Décide si une action mérite un retour à l'écran.
///
/// Une action au clavier, en ligne de commande ou depuis la télécommande n'a
/// aucun contrôle visible qui bouge : l'OSD est son seul retour. Un clic sur
/// la barre de contrôles, lui, fait déjà bouger le contrôle cliqué — sauf en
/// plein écran, où la barre peut être masquée.
bool osdWantedFor(CommandSource source, {required bool fullscreen}) =>
    switch (source) {
      CommandSource.ui => fullscreen,
      CommandSource.keyboard ||
      CommandSource.cli ||
      CommandSource.system ||
      CommandSource.remote =>
        true,
    };

/// Message à afficher pour [command], sachant l'état [after] une fois la
/// commande traitée. `null` si l'action ne mérite pas de retour visuel.
OsdMessage? osdFor(PlayerCommand command, PlaybackState after) {
  // Sans fichier, la plupart des actions ne changent rien de visible.
  final hasMedia = after.hasFile && after.mediaType.isAv;

  return switch (command) {
    SeekRelative(:final seconds) when hasMedia => OsdSeek(
        deltaSeconds: seconds,
        position: after.position,
        duration: after.duration,
      ),
    SeekAbsolute() when hasMedia => OsdSeek(
        deltaSeconds: 0,
        position: after.position,
        duration: after.duration,
      ),
    SetVolume() || VolumeRelative() || ToggleMute() => OsdVolume(
        volume: after.volume,
        muted: after.muted,
      ),
    SetSpeed() || SpeedRelative() when hasMedia => OsdSpeed(after.speed),
    Play() || Pause() || TogglePlay() when hasMedia => OsdPlayState(
        playing: after.isPlaying,
      ),
    NextFile() when after.file != null => OsdFileChanged(
        name: after.file!.name,
        forward: true,
      ),
    PreviousFile() when after.file != null => OsdFileChanged(
        name: after.file!.name,
        forward: false,
      ),
    SetLoopMode() || CycleLoopMode() => OsdEndMode(after.endMode),
    ToggleAlwaysOnTop() => OsdAlwaysOnTop(enabled: after.alwaysOnTop),
    ToggleFullscreen() || ExitFullscreen() => OsdFullscreen(
        enabled: after.fullscreen,
      ),
    _ => null,
  };
}
