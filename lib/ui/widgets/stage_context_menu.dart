import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/end_of_playback_mode.dart';
import '../../core/models/playback_status.dart';
import '../../core/models/video_adjust.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../file_dialogs.dart';
import '../panel_controller.dart';
import '../tool_panel_controller.dart';
import 'omnia_menu.dart';
import 'track_menus.dart';

/// Menu contextuel de la scène (clic droit sur la vidéo).
///
/// Enveloppe [child] et ouvre le menu à l'endroit du clic. Les sections
/// sous-titres, pistes audio, image et capture arrivent en Phase 5 : le menu
/// est déjà structuré pour les accueillir.
class StageContextMenu extends ConsumerStatefulWidget {
  const StageContextMenu({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StageContextMenu> createState() => _StageContextMenuState();
}

class _StageContextMenuState extends ConsumerState<StageContextMenu> {
  final MenuController _controller = MenuController();

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    final panelVisible = ref.watch(panelStateProvider.select((p) => p.visible));

    final hasMedia =
        state.hasFile && state.status != PlaybackStatus.error && state.mediaType.isAv;
    final hasPlaylist = state.playlist.length > 1;
    final path = state.file?.path;

    String aspectLabel(AspectMode mode) => switch (mode) {
          AspectMode.auto => l10n.aspectAuto,
          AspectMode.wide => l10n.aspectWide,
          AspectMode.standard => l10n.aspectStandard,
          AspectMode.fill => l10n.aspectFill,
        };

    String endModeLabel(EndOfPlaybackMode mode) => switch (mode) {
          EndOfPlaybackMode.stop => l10n.endModeStop,
          EndOfPlaybackMode.next => l10n.endModeNext,
          EndOfPlaybackMode.repeatOne => l10n.endModeRepeatOne,
          EndOfPlaybackMode.loopFolder => l10n.endModeLoopFolder,
          EndOfPlaybackMode.shuffle => l10n.endModeShuffle,
        };

    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      menuChildren: [
        OmniaMenuItem(
          icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: state.isPlaying ? l10n.pause : l10n.play,
          trailing: 'Espace',
          enabled: hasMedia,
          onPressed: () => ref.dispatch(const TogglePlay()),
        ),
        OmniaMenuItem(
          icon: Icons.skip_previous_rounded,
          label: l10n.previousFile,
          trailing: 'P',
          enabled: hasPlaylist,
          onPressed: () => ref.dispatch(const PreviousFile()),
        ),
        OmniaMenuItem(
          icon: Icons.skip_next_rounded,
          label: l10n.nextFile,
          trailing: 'N',
          enabled: hasPlaylist,
          onPressed: () => ref.dispatch(const NextFile()),
        ),
        const OmniaMenuDivider(),
        OmniaSubmenu(
          icon: Icons.speed_rounded,
          label: l10n.menuSpeed,
          trailing: l10n.speedValue(_formatSpeed(state.speed)),
          children: [
            for (final speed in _speeds)
              OmniaMenuItem(
                label: l10n.speedValue(_formatSpeed(speed)),
                active: (state.speed - speed).abs() < 0.001,
                icon: (state.speed - speed).abs() < 0.001 ? Icons.check_rounded : null,
                onPressed: () => ref.dispatch(SetSpeed(speed)),
              ),
          ],
        ),
        OmniaSubmenu(
          icon: Icons.repeat_rounded,
          label: l10n.endModeLabel,
          trailing: endModeLabel(state.endMode),
          children: [
            for (final mode in EndOfPlaybackMode.values)
              OmniaMenuItem(
                label: endModeLabel(mode),
                active: state.endMode == mode,
                icon: state.endMode == mode ? Icons.check_rounded : null,
                onPressed: () => ref.dispatch(SetLoopMode(mode)),
              ),
          ],
        ),
        if (hasMedia && state.hasVideo) ...[
          const OmniaMenuDivider(),
          OmniaSubmenu(
            icon: Icons.subtitles_outlined,
            label: l10n.subtitles,
            children: subtitleMenuItems(context, ref, state),
          ),
          if (state.audioTracks.length > 1)
            OmniaSubmenu(
              icon: Icons.audiotrack_rounded,
              label: l10n.audioTracks,
              children: audioTrackMenuItems(context, ref, state),
            ),
          OmniaSubmenu(
            icon: Icons.tune_rounded,
            label: l10n.image,
            children: [
              OmniaSubmenu(
                label: l10n.aspectRatio,
                trailing: aspectLabel(state.aspectMode),
                children: [
                  for (final mode in AspectMode.values)
                    OmniaMenuItem(
                      label: aspectLabel(mode),
                      active: state.aspectMode == mode,
                      icon: state.aspectMode == mode ? Icons.check_rounded : null,
                      onPressed: () => ref.dispatch(SetAspectMode(mode)),
                    ),
                ],
              ),
              OmniaMenuItem(
                icon: Icons.zoom_in_rounded,
                label: l10n.docZoomIn,
                onPressed: () => ref.dispatch(const VideoZoomRelative(0.1)),
              ),
              OmniaMenuItem(
                icon: Icons.zoom_out_rounded,
                label: l10n.docZoomOut,
                onPressed: () => ref.dispatch(const VideoZoomRelative(-0.1)),
              ),
              OmniaMenuItem(
                icon: Icons.crop_free_rounded,
                label: l10n.videoZoomReset,
                enabled: state.videoZoom != 0,
                onPressed: () => ref.dispatch(const ResetVideoZoom()),
              ),
              OmniaMenuItem(
                icon: Icons.rotate_right_rounded,
                label: l10n.videoRotate,
                trailing: state.videoRotation == 0 ? null : '${state.videoRotation * 90}°',
                onPressed: () => ref.dispatch(const RotateVideo()),
              ),
              const OmniaMenuDivider(),
              OmniaMenuItem(
                icon: Icons.brightness_6_outlined,
                label: l10n.imageAdjust,
                onPressed: () => ref.read(toolPanelProvider.notifier).toggle(ToolPanel.image),
              ),
            ],
          ),
          OmniaMenuItem(
            icon: Icons.photo_camera_outlined,
            label: l10n.screenshot,
            trailing: 'S',
            onPressed: () => ref.dispatch(const TakeScreenshot()),
          ),
        ],
        if (hasMedia) ...[
          OmniaMenuItem(
            icon: Icons.repeat_rounded,
            label: l10n.abLoop,
            trailing: 'A',
            active: state.loopA != null,
            onPressed: () => ref.dispatch(const CycleAbLoop()),
          ),
          OmniaMenuItem(
            icon: Icons.equalizer_rounded,
            label: l10n.equalizer,
            active: state.equalizerEnabled,
            onPressed: () => ref.read(toolPanelProvider.notifier).toggle(ToolPanel.equalizer),
          ),
        ],
        const OmniaMenuDivider(),
        OmniaMenuItem(
          icon: state.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          label: state.fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
          trailing: 'F',
          onPressed: () => ref.dispatch(const ToggleFullscreen()),
        ),
        if (hasMedia)
          OmniaMenuItem(
            icon: Icons.picture_in_picture_alt_outlined,
            label: l10n.miniPlayer,
            trailing: 'Ctrl+Maj+M',
            onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
          ),
        OmniaMenuItem(
          icon: Icons.push_pin_outlined,
          label: l10n.alwaysOnTop,
          trailing: 'T',
          active: state.alwaysOnTop,
          onPressed: () => ref.dispatch(const ToggleAlwaysOnTop()),
        ),
        OmniaMenuItem(
          icon: Icons.view_sidebar_outlined,
          label: panelVisible ? l10n.panelHide : l10n.panelShow,
          trailing: 'Tab',
          onPressed: () => ref.dispatch(const ToggleSidePanel()),
        ),
        const OmniaMenuDivider(),
        OmniaMenuItem(
          icon: Icons.insert_drive_file_outlined,
          label: l10n.openFile,
          trailing: 'Ctrl+O',
          onPressed: () => pickAndOpenFile(ref),
        ),
        OmniaMenuItem(
          icon: Icons.folder_outlined,
          label: l10n.openFolder,
          trailing: 'Ctrl+Maj+O',
          onPressed: () => pickAndOpenFolder(ref),
        ),
        if (path != null)
          OmniaMenuItem(
            icon: Icons.folder_open_rounded,
            label: l10n.contextReveal,
            onPressed: () => ref.dispatch(RevealInFolder(path)),
          ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => _controller.open(position: details.localPosition),
        child: widget.child,
      ),
    );
  }

  static String _formatSpeed(double speed) => formatSpeed(speed);
}
