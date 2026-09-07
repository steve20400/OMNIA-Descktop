import 'package:collection/collection.dart';

import '../models/end_of_playback_mode.dart';

/// Commandes du lecteur.
///
/// Règle d'or d'OMNIA : l'interface n'appelle jamais un contrôleur directement.
/// Chaque action utilisateur devient une [PlayerCommand] publiée sur le
/// [PlayerCommandBus]. Les commandes sont sérialisables en JSON pour qu'une
/// future télécommande (WebSocket) puisse émettre exactement les mêmes.
sealed class PlayerCommand {
  const PlayerCommand();

  /// Identifiant stable de la commande (clé `type` du JSON).
  String get type;

  /// Arguments de la commande, fusionnés dans le JSON.
  Map<String, Object?> get arguments => const {};

  Map<String, Object?> toJson() => {'type': type, ...arguments};

  /// Reconstruit une commande depuis son JSON.
  ///
  /// Lève une [FormatException] si le type est inconnu ou un argument absent.
  static PlayerCommand fromJson(Map<String, Object?> json) {
    final type = json['type'];
    return switch (type) {
      'play' => const Play(),
      'pause' => const Pause(),
      'togglePlay' => const TogglePlay(),
      'stop' => const Stop(),
      'seekRelative' => SeekRelative(_num(json, 'seconds').toDouble()),
      'seekAbsolute' =>
        SeekAbsolute(Duration(milliseconds: _num(json, 'positionMs').toInt())),
      'setVolume' => SetVolume(_num(json, 'volume').toDouble()),
      'volumeRelative' => VolumeRelative(_num(json, 'delta').toDouble()),
      'toggleMute' => const ToggleMute(),
      'nextFile' => const NextFile(),
      'previousFile' => const PreviousFile(),
      'setSpeed' => SetSpeed(_num(json, 'speed').toDouble()),
      'speedRelative' => SpeedRelative(_num(json, 'delta').toDouble()),
      'nextPage' => const NextPage(),
      'previousPage' => const PreviousPage(),
      'goToPage' => GoToPage(_num(json, 'page').toInt()),
      'setZoom' => SetZoom(_num(json, 'zoom').toDouble()),
      'toggleFullscreen' => const ToggleFullscreen(),
      'exitFullscreen' => const ExitFullscreen(),
      'takeScreenshot' => const TakeScreenshot(),
      'setLoopMode' => SetLoopMode(EndOfPlaybackMode.fromJson(json['mode'])),
      'cycleLoopMode' => const CycleLoopMode(),
      'toggleAlwaysOnTop' => const ToggleAlwaysOnTop(),
      'toggleSidePanel' => const ToggleSidePanel(),
      'openFile' => OpenFile(_string(json, 'path')),
      'openFolder' => OpenFolder(_string(json, 'path')),
      _ => throw FormatException('Commande inconnue : $type'),
    };
  }

  static num _num(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is num) return v;
    throw FormatException('Argument numérique manquant : $key');
  }

  static String _string(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is String) return v;
    throw FormatException('Argument texte manquant : $key');
  }

  static const _equality = DeepCollectionEquality();

  @override
  bool operator ==(Object other) =>
      other is PlayerCommand &&
      other.runtimeType == runtimeType &&
      _equality.equals(other.toJson(), toJson());

  @override
  int get hashCode => _equality.hash(toJson());

  @override
  String toString() => 'PlayerCommand${toJson()}';
}

// --- Transport -------------------------------------------------------------

final class Play extends PlayerCommand {
  const Play();
  @override
  String get type => 'play';
}

final class Pause extends PlayerCommand {
  const Pause();
  @override
  String get type => 'pause';
}

final class TogglePlay extends PlayerCommand {
  const TogglePlay();
  @override
  String get type => 'togglePlay';
}

/// Arrête la lecture et ferme le fichier courant.
final class Stop extends PlayerCommand {
  const Stop();
  @override
  String get type => 'stop';
}

/// Avance (positif) ou recule (négatif) de [seconds] secondes.
final class SeekRelative extends PlayerCommand {
  const SeekRelative(this.seconds);
  final double seconds;
  @override
  String get type => 'seekRelative';
  @override
  Map<String, Object?> get arguments => {'seconds': seconds};
}

final class SeekAbsolute extends PlayerCommand {
  const SeekAbsolute(this.position);
  final Duration position;
  @override
  String get type => 'seekAbsolute';
  @override
  Map<String, Object?> get arguments =>
      {'positionMs': position.inMilliseconds};
}

// --- Volume ---------------------------------------------------------------

/// Volume absolu, 0–100.
final class SetVolume extends PlayerCommand {
  const SetVolume(this.volume);
  final double volume;
  @override
  String get type => 'setVolume';
  @override
  Map<String, Object?> get arguments => {'volume': volume};
}

final class VolumeRelative extends PlayerCommand {
  const VolumeRelative(this.delta);
  final double delta;
  @override
  String get type => 'volumeRelative';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

final class ToggleMute extends PlayerCommand {
  const ToggleMute();
  @override
  String get type => 'toggleMute';
}

// --- Playlist -------------------------------------------------------------

final class NextFile extends PlayerCommand {
  const NextFile();
  @override
  String get type => 'nextFile';
}

final class PreviousFile extends PlayerCommand {
  const PreviousFile();
  @override
  String get type => 'previousFile';
}

// --- Vitesse --------------------------------------------------------------

final class SetSpeed extends PlayerCommand {
  const SetSpeed(this.speed);
  final double speed;
  @override
  String get type => 'setSpeed';
  @override
  Map<String, Object?> get arguments => {'speed': speed};
}

final class SpeedRelative extends PlayerCommand {
  const SpeedRelative(this.delta);
  final double delta;
  @override
  String get type => 'speedRelative';
  @override
  Map<String, Object?> get arguments => {'delta': delta};
}

// --- Documents ------------------------------------------------------------

final class NextPage extends PlayerCommand {
  const NextPage();
  @override
  String get type => 'nextPage';
}

final class PreviousPage extends PlayerCommand {
  const PreviousPage();
  @override
  String get type => 'previousPage';
}

/// Page 1-based.
final class GoToPage extends PlayerCommand {
  const GoToPage(this.page);
  final int page;
  @override
  String get type => 'goToPage';
  @override
  Map<String, Object?> get arguments => {'page': page};
}

final class SetZoom extends PlayerCommand {
  const SetZoom(this.zoom);
  final double zoom;
  @override
  String get type => 'setZoom';
  @override
  Map<String, Object?> get arguments => {'zoom': zoom};
}

// --- Fenêtre & divers -----------------------------------------------------

final class ToggleFullscreen extends PlayerCommand {
  const ToggleFullscreen();
  @override
  String get type => 'toggleFullscreen';
}

final class ExitFullscreen extends PlayerCommand {
  const ExitFullscreen();
  @override
  String get type => 'exitFullscreen';
}

final class TakeScreenshot extends PlayerCommand {
  const TakeScreenshot();
  @override
  String get type => 'takeScreenshot';
}

final class SetLoopMode extends PlayerCommand {
  const SetLoopMode(this.mode);
  final EndOfPlaybackMode mode;
  @override
  String get type => 'setLoopMode';
  @override
  Map<String, Object?> get arguments => {'mode': mode.name};
}

final class CycleLoopMode extends PlayerCommand {
  const CycleLoopMode();
  @override
  String get type => 'cycleLoopMode';
}

final class ToggleAlwaysOnTop extends PlayerCommand {
  const ToggleAlwaysOnTop();
  @override
  String get type => 'toggleAlwaysOnTop';
}

final class ToggleSidePanel extends PlayerCommand {
  const ToggleSidePanel();
  @override
  String get type => 'toggleSidePanel';
}

// --- Ouverture ------------------------------------------------------------

/// Ouvre un fichier par son chemin absolu (déclenche le scan du dossier).
final class OpenFile extends PlayerCommand {
  const OpenFile(this.path);
  final String path;
  @override
  String get type => 'openFile';
  @override
  Map<String, Object?> get arguments => {'path': path};
}

/// Ouvre un dossier : scan, puis lecture du premier fichier lisible.
final class OpenFolder extends PlayerCommand {
  const OpenFolder(this.path);
  final String path;
  @override
  String get type => 'openFolder';
  @override
  Map<String, Object?> get arguments => {'path': path};
}
