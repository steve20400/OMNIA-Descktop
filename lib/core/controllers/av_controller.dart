import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../commands/player_command.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import 'media_controller.dart';

/// Contrôleur audio/vidéo basé sur media_kit (libmpv).
///
/// Un seul [Player] pour toute la vie de l'application : ouvrir un nouveau
/// fichier remplace le précédent sans recréer le moteur (ouverture < 1 s).
class AvController implements MediaController {
  AvController({Player? player}) : player = player ?? Player() {
    videoController = VideoController(this.player);
    _listen();
  }

  /// Moteur mpv.
  final Player player;

  /// Surface de rendu vidéo, consommée par le widget `Video` de l'interface.
  late final VideoController videoController;

  PlaybackStateSink? _sink;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Vrai entre `open()` et le premier événement de lecture, pour ne pas
  /// afficher « en pause » pendant le chargement.
  bool _opening = false;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  void _listen() {
    final s = player.stream;
    _subscriptions.addAll([
      s.position.listen((position) => _update((st) => st.copyWith(position: position))),
      s.duration.listen((duration) => _update((st) => st.copyWith(duration: duration))),
      s.buffering.listen((buffering) => _update((st) => st.copyWith(buffering: buffering))),
      s.volume.listen((volume) => _update((st) => st.copyWith(volume: volume))),
      s.rate.listen((rate) => _update((st) => st.copyWith(speed: rate))),
      s.width.listen((width) {
        if (width == null) return;
        _update((st) => st.copyWith(hasVideo: width > 0));
      }),
      s.playing.listen((playing) {
        if (playing) _opening = false;
        _update((st) {
          if (st.status == PlaybackStatus.error) return st;
          if (!playing && _opening) return st;
          return st.copyWith(
            status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
          );
        });
      }),
      s.completed.listen((completed) {
        if (!completed) return;
        _update((st) => st.copyWith(status: PlaybackStatus.ended));
      }),
      s.error.listen((message) {
        _opening = false;
        _update(
          (st) => st.copyWith(
            status: PlaybackStatus.error,
            error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: message),
          ),
        );
      }),
    ]);
  }

  void _update(PlaybackState Function(PlaybackState) reducer) {
    _sink?.update(reducer);
  }

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    _opening = true;

    if (!File(file.path).existsSync()) {
      _opening = false;
      sink.update(
        (st) => st.copyWith(
          file: file,
          status: PlaybackStatus.error,
          error: const PlaybackError(PlaybackErrorCode.fileNotFound),
        ),
      );
      return;
    }

    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: file.type == MediaType.video,
        clearError: true,
      ),
    );

    try {
      await player.open(Media(file.path), play: true);
      // La vitesse et le volume sont conservés d'un fichier à l'autre.
      await player.setRate(sink.state.speed);
    } on Object catch (e) {
      _opening = false;
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(_classify(e), detail: e.toString()),
        ),
      );
    }
  }

  PlaybackErrorCode _classify(Object error) {
    if (error is FileSystemException) {
      return error.osError?.errorCode == 13
          ? PlaybackErrorCode.permissionDenied
          : PlaybackErrorCode.fileNotFound;
    }
    return PlaybackErrorCode.decodeFailed;
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final state = _sink?.state;
    if (state == null || !state.hasFile) return false;

    switch (command) {
      case Play():
        await player.play();
      case Pause():
        await player.pause();
      case TogglePlay():
        if (state.status == PlaybackStatus.ended) {
          await player.seek(Duration.zero);
          await player.play();
        } else {
          await player.playOrPause();
        }
      case SeekRelative(:final seconds):
        await _seekTo(state.position + Duration(milliseconds: (seconds * 1000).round()));
      case SeekAbsolute(:final position):
        await _seekTo(position);
      case SetVolume(:final volume):
        await _setVolume(volume);
      case VolumeRelative(:final delta):
        await _setVolume(state.volume + delta);
      case ToggleMute():
        await _setMuted(!state.muted);
      case SetSpeed(:final speed):
        await _setSpeed(speed);
      case SpeedRelative(:final delta):
        await _setSpeed(state.speed + delta);
      default:
        return false;
    }
    return true;
  }

  Future<void> _seekTo(Duration target) async {
    final duration = _sink?.state.duration ?? Duration.zero;
    var clamped = target.isNegative ? Duration.zero : target;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    // Retour visuel immédiat : la position est mise à jour avant que mpv confirme.
    _update((st) => st.copyWith(position: clamped));
    await player.seek(clamped);
    // Reprendre après un seek depuis la fin.
    if (_sink?.state.status == PlaybackStatus.ended) await player.play();
  }

  Future<void> _setVolume(double volume) async {
    final v = volume.clamp(PlaybackState.minVolume, PlaybackState.maxVolume);
    if (_sink?.state.muted ?? false) await _setMuted(false);
    await player.setVolume(v);
    _update((st) => st.copyWith(volume: v));
  }

  Future<void> _setMuted(bool muted) async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('mute', muted ? 'yes' : 'no');
    }
    _update((st) => st.copyWith(muted: muted));
  }

  Future<void> _setSpeed(double speed) async {
    // Arrondi au pas de 0,25 puis bornage 0,25×–4×.
    final steps = (speed / PlaybackState.speedStep).round();
    final s = (steps * PlaybackState.speedStep)
        .clamp(PlaybackState.minSpeed, PlaybackState.maxSpeed);
    await player.setRate(s);
    _update((st) => st.copyWith(speed: s));
  }

  @override
  Future<void> close() async {
    _opening = false;
    await player.stop();
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        clearError: true,
      ),
    );
    _sink = null;
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await player.dispose();
  }
}
