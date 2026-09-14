import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../audio_tags_provider.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_handler.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import 'beam_progress_bar.dart';
import 'omnia_icon_button.dart';

/// Mini-lecteur : fenêtre compacte au premier plan. Pochette (ou icône),
/// titre, faisceau, transport essentiel. Toute la surface se déplace.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'omnia.mini');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);
    final tags = ref.watch(audioTagsProvider);

    final title = tags?.title ?? state.file?.baseName ?? l10n.appTitle;
    final subtitle = tags?.artist ??
        (state.file == null ? '' : formatTimecode(state.position, reference: state.duration));
    final cover = tags?.hasCover == true ? tags!.cover : null;
    final hasMedia = state.hasFile && state.mediaType.isAv;
    final hasPlaylist = state.playlist.length > 1;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) => handleShortcut(event, ref),
      child: DragToMoveArea(
        child: ColoredBox(
          color: colors.velvet,
          child: Padding(
            padding: const EdgeInsets.all(OmniaMetrics.space3),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: OmniaMetrics.controlRadius,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: cover != null
                        ? Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true)
                        : ColoredBox(
                            color: colors.curtain,
                            child: Icon(
                              state.mediaType == MediaType.video
                                  ? Icons.movie_outlined
                                  : Icons.music_note_rounded,
                              color: colors.dust,
                              size: 36,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: OmniaMetrics.space3),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: type.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(subtitle, style: type.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: OmniaMetrics.space1),
                      SizedBox(
                        height: 26,
                        child: BeamProgressBar(
                          progress: state.progress,
                          duration: state.duration,
                          enabled: hasMedia && state.duration > Duration.zero,
                          onSeek: (position) => ref.dispatch(SeekAbsolute(position)),
                        ),
                      ),
                      Row(
                        children: [
                          OmniaIconButton(
                            icon: Icons.skip_previous_rounded,
                            size: OmniaMetrics.iconButtonSize - 8,
                            iconSize: OmniaMetrics.iconSize - 2,
                            tooltip: l10n.previousFile,
                            onPressed: hasPlaylist ? () => ref.dispatch(const PreviousFile()) : null,
                          ),
                          OmniaIconButton(
                            icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: OmniaMetrics.iconButtonSize - 4,
                            iconSize: OmniaMetrics.iconSize + 2,
                            tooltip: state.isPlaying ? l10n.pause : l10n.play,
                            onPressed: hasMedia ? () => ref.dispatch(const TogglePlay()) : null,
                          ),
                          OmniaIconButton(
                            icon: Icons.skip_next_rounded,
                            size: OmniaMetrics.iconButtonSize - 8,
                            iconSize: OmniaMetrics.iconSize - 2,
                            tooltip: l10n.nextFile,
                            onPressed: hasPlaylist ? () => ref.dispatch(const NextFile()) : null,
                          ),
                          const Spacer(),
                          OmniaIconButton(
                            icon: state.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            size: OmniaMetrics.iconButtonSize - 8,
                            iconSize: OmniaMetrics.iconSize - 2,
                            tooltip: state.muted ? l10n.unmute : l10n.mute,
                            onPressed: () => ref.dispatch(const ToggleMute()),
                          ),
                          OmniaIconButton(
                            icon: Icons.open_in_full_rounded,
                            size: OmniaMetrics.iconButtonSize - 8,
                            iconSize: OmniaMetrics.iconSize - 4,
                            tooltip: ref.tooltipWith(l10n.miniPlayerExit, ShortcutAction.miniPlayer, l10n),
                            onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
