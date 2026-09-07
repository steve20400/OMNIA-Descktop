import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../theme/omnia_theme.dart';
import 'beam_progress_bar.dart';
import 'floating_surface.dart';
import 'omnia_icon_button.dart';
import 'slim_slider.dart';

/// Barre de contrôles flottante : faisceau de progression, lecture/pause,
/// timecodes, vitesse, volume, plein écran.
///
/// Chaque interaction émet une [PlayerCommand] sur le bus ; ce widget ne
/// connaît aucun contrôleur.
class ControlBar extends ConsumerStatefulWidget {
  const ControlBar({super.key});

  @override
  ConsumerState<ControlBar> createState() => _ControlBarState();
}

class _ControlBarState extends ConsumerState<ControlBar> {
  /// Clic sur la durée : bascule durée totale ↔ temps restant.
  bool _showRemaining = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackStateProvider);
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);

    final hasMedia = state.hasFile && state.status != PlaybackStatus.error && state.mediaType.isAv;
    final canSeek = hasMedia && state.duration > Duration.zero;
    final mutedColor = colors.dust;
    final timeColor = hasMedia ? colors.screen : mutedColor;

    final elapsed = formatTimecode(state.position, reference: state.duration);
    final total = _showRemaining
        ? '-${formatTimecode(state.remaining, reference: state.duration)}'
        : formatTimecode(state.duration);

    final volumeIcon = state.muted || state.volume <= 0
        ? Icons.volume_off_rounded
        : state.volume < 50
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    final isPlaying = state.status == PlaybackStatus.playing;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: OmniaMetrics.controlBarMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(OmniaMetrics.controlBarMargin),
          child: FloatingSurface(
            padding: const EdgeInsets.fromLTRB(
              OmniaMetrics.controlBarPadding,
              0,
              OmniaMetrics.controlBarPadding,
              OmniaMetrics.space2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BeamProgressBar(
                  progress: state.progress,
                  duration: state.duration,
                  enabled: canSeek,
                  onSeek: (position) => ref.dispatch(SeekAbsolute(position)),
                ),
                Row(
                  children: [
                    OmniaIconButton(
                      icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: OmniaMetrics.playButtonSize,
                      iconSize: OmniaMetrics.iconSizeLarge,
                      tooltip: isPlaying ? l10n.pause : l10n.play,
                      onPressed: hasMedia ? () => ref.dispatch(const TogglePlay()) : null,
                    ),
                    const SizedBox(width: OmniaMetrics.space3),
                    Text(elapsed, style: type.timecode.copyWith(color: timeColor)),
                    Text('  /  ', style: type.timecode.copyWith(color: mutedColor)),
                    Tooltip(
                      message: _showRemaining ? l10n.showTotalTime : l10n.showRemainingTime,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _showRemaining = !_showRemaining),
                          child: Text(total, style: type.timecode.copyWith(color: mutedColor)),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _SpeedChip(speed: state.speed, enabled: hasMedia),
                    const SizedBox(width: OmniaMetrics.space3),
                    OmniaIconButton(
                      icon: volumeIcon,
                      tooltip: state.muted ? l10n.unmute : l10n.mute,
                      onPressed: () => ref.dispatch(const ToggleMute()),
                    ),
                    SlimSlider(
                      value: state.muted ? 0 : state.volume / PlaybackState.maxVolume,
                      muted: state.muted,
                      onChanged: (v) => ref.dispatch(SetVolume(v * PlaybackState.maxVolume)),
                    ),
                    const SizedBox(width: OmniaMetrics.space3),
                    OmniaIconButton(
                      icon: state.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      tooltip: state.fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
                      onPressed: () => ref.dispatch(const ToggleFullscreen()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vitesse courante en mono ; un clic revient à 1×.
class _SpeedChip extends ConsumerWidget {
  const _SpeedChip({required this.speed, required this.enabled});

  final double speed;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final isDefault = speed == 1.0;
    return Tooltip(
      message: l10n.resetSpeed,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => ref.dispatch(const SetSpeed(1.0)) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2),
            child: Text(
              l10n.speedValue(formatSpeed(speed)),
              style: type.timecode.copyWith(
                color: isDefault ? colors.dust : colors.projector,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
