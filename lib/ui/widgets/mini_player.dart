import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playlist_sort.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../audio_tags_provider.dart';
import '../chrome_controller.dart';
import '../document_search.dart';
import '../document_search_provider.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_handler.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import '../wheel_steps.dart';
import 'beam_progress_bar.dart';
import 'image_stage.dart';
import 'omnia_icon_button.dart';
import 'pdf_stage.dart';
import 'playlist_tile.dart';
import 'stage.dart';
import 'stage_context_menu.dart';
import 'text_view.dart';

/// Mini-lecteur : la fenêtre compacte au premier plan.
///
/// Universel : vidéo (façon VLC), image fixe avec zoom/rotation, document
/// (PDF et texte/code avec navigation), et son avec pochette/faisceau.
///
/// Un tiroir inférieur coulissant (style YouTube mini-player) présente la liste
/// de lecture et ses filtres (Tout, Vidéos, Audios, Documents, Images) lors de
/// l'appui sur `Tab` ou sur le bouton dédié.
///
/// Toute la surface déplace la fenêtre ; le double-clic revient à la fenêtre
/// entière (et n'agrandit surtout pas, contrairement à `DragToMoveArea`).
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  /// En deçà, « précédent » et « suivant » cèdent la place à la lecture seule.
  static const double skipButtonsWidth = 260;

  /// En deçà, le timecode s'efface : le faisceau suffit.
  static const double timecodeWidth = 300;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  final FocusNode _focus = FocusNode(debugLabel: 'omnia.mini');

  /// Molette au-dessus du mini-lecteur : crans de volume regroupés, comme sur
  /// la scène de l'écran principal.
  final WheelSteps _volumeWheel = WheelSteps();

  late final ChromeController _chrome = ref.read(chromeProvider.notifier);
  StreamSubscription<PlayerCommand>? _commandSub;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _commandSub = ref.read(commandBusProvider).commands.listen((cmd) {
      if (!mounted) return;
      if (cmd is ToggleSidePanel) {
        _toggleDrawer();
      } else if (cmd is SetSidePanelVisible) {
        if (_drawerOpen != cmd.visible) {
          setState(() => _drawerOpen = cmd.visible);
        }
      }
    });
  }

  void _toggleDrawer() {
    setState(() => _drawerOpen = !_drawerOpen);
  }

  void _closeDrawer() {
    if (_drawerOpen) {
      setState(() => _drawerOpen = false);
      ref.dispatch(const SetSidePanelVisible(false));
    }
  }

  @override
  void dispose() {
    _commandSub?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    // Défilement horizontal (molette inclinable, pavé tactile) : pas de volume.
    if (dy == 0) return;
    // Par le résolveur : le faisceau, sous le curseur, passe avant le volume.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final step = _volumeWheel.add(dy);
      if (step != 0) ref.dispatch(VolumeRelative(5.0 * step));
    });
  }

  /// Glissement : la fenêtre suit. Clic : lecture/pause si média AV.
  /// Double-clic : retour à la fenêtre entière.
  Widget _windowGestures({required Widget child, required bool hasMedia}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: hasMedia
          ? () {
              _focus.requestFocus();
              ref.dispatch(const TogglePlay());
            }
          : _focus.requestFocus,
      onDoubleTap: () => ref.dispatch(const ToggleMiniPlayer()),
      child: DragToMoveArea(
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(playbackStateProvider);

    Widget content;
    if (state.hasVideo) {
      content = _video(state);
    } else if (state.mediaType == MediaType.image && state.hasFile) {
      content = _image(state);
    } else if (state.isDocument && state.hasFile) {
      content = _document(state);
    } else {
      content = _audioStrip(context, state);
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            ref.dispatch(const ToggleSidePanel());
            return KeyEventResult.handled;
          }
          if (_drawerOpen && event.logicalKey == LogicalKeyboardKey.escape) {
            _closeDrawer();
            return KeyEventResult.handled;
          }
        }
        return handleShortcut(event, ref, panelDrawerOpen: _drawerOpen);
      },
      child: MouseRegion(
        onHover: (_) => _chrome.activity(),
        onExit: (_) => _chrome.pointerLeft(),
        child: Listener(
          onPointerDown: (_) => _chrome.activity(),
          onPointerMove: (_) => _chrome.activity(),
          onPointerSignal: _onPointerSignal,
          child: ColoredBox(
            color: colors.velvet,
            child: Stack(
              fit: StackFit.expand,
              children: [
                content,
                // Tiroir inférieur de liste de lecture (style YouTube)
                if (_drawerOpen) _MiniPlaylistBottomDrawer(onClose: _closeDrawer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Vidéo : la vidéo occupe toute la fenêtre ---------------------------

  Widget _video(PlaybackState state) {
    final surface = ref.watch(videoSurfaceProvider);
    final hasMedia = state.hasFile && state.mediaType.isAv;

    return Stack(
      fit: StackFit.expand,
      children: [
        StageContextMenu(
          child: _windowGestures(
            hasMedia: hasMedia,
            child: surface(context, fit: BoxFit.contain, aspectRatio: null),
          ),
        ),
        _MiniOverlay(state: state),
      ],
    );
  }

  // --- Image : affichage compact avec zoom et rotation --------------------

  Widget _image(PlaybackState state) {
    return Stack(
      fit: StackFit.expand,
      children: [
        StageContextMenu(
          child: _windowGestures(
            hasMedia: false,
            child: ImageStage(
              key: ValueKey('mini-image:${state.file!.path}'),
              file: state.file!,
            ),
          ),
        ),
        _MiniImageOverlay(state: state),
      ],
    );
  }

  // --- Document (PDF / Texte / Code) --------------------------------------

  Widget _document(PlaybackState state) {
    final textDocument = ref.watch(textDocumentProvider);
    Widget docWidget;
    if (textDocument != null) {
      docWidget = TextView(
        key: ValueKey('mini-text:${textDocument.path}'),
        document: textDocument,
        search: ref.watch(documentSearchProvider) as PlainTextSearch?,
      );
    } else if (state.mediaType == MediaType.pdf) {
      docWidget = const PdfStage(key: ValueKey('mini-pdf'));
    } else {
      docWidget = const SizedBox.shrink();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        StageContextMenu(
          child: _windowGestures(
            hasMedia: false,
            child: docWidget,
          ),
        ),
        _MiniDocumentOverlay(state: state),
      ],
    );
  }

  // --- Sans image : le bandeau audio --------------------------------------

  Widget _audioStrip(BuildContext context, PlaybackState state) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final tags = ref.watch(audioTagsProvider);

    final title = tags?.title ?? state.file?.baseName ?? l10n.appTitle;
    final subtitle = tags?.artist ??
        (state.file == null ? '' : formatTimecode(state.position, reference: state.duration));
    final cover = tags?.hasCover == true ? tags!.cover : null;
    final hasMedia = state.hasFile && state.mediaType.isAv;
    final hasPlaylist = state.playlist.length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxHeight < 110 ? OmniaMetrics.space2 : OmniaMetrics.space3;
        final inner = math.max(0.0, constraints.maxHeight - 2 * inset);
        final compact = inner < 92;
        final coverSide = math.min(inner, 100.0);
        final beamHeight = math.min(inner * 0.3, compact ? 18.0 : 26.0);
        final rowHeight = math.min(inner * 0.45, compact ? 28.0 : 34.0);
        final columnWidth = math.max(
          0.0,
          constraints.maxWidth - 2 * inset - coverSide - OmniaMetrics.space3,
        );
        final buttonSize = math.max(18.0, rowHeight - 4);
        final buttonIcon = math.max(10.0, buttonSize - 8);

        return Stack(
          fit: StackFit.expand,
          children: [
            _windowGestures(
              hasMedia: false,
              child: const SizedBox.expand(),
            ),
            Padding(
              padding: EdgeInsets.all(inset),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: OmniaMetrics.controlRadius,
                    child: SizedBox(
                      width: coverSide,
                      height: coverSide,
                      child: cover != null
                          ? Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true)
                          : ColoredBox(
                              color: colors.curtain,
                              child: Icon(
                                state.mediaType == MediaType.video
                                    ? Icons.movie_outlined
                                    : Icons.music_note_rounded,
                                color: colors.dust,
                                size: math.min(36.0, coverSide * 0.4),
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
                        Flexible(
                          child: Text(
                            title,
                            style: type.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!compact)
                          Flexible(
                            child: Text(
                              subtitle,
                              style: type.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        SizedBox(
                          height: beamHeight,
                          child: BeamProgressBar(
                            progress: state.progress,
                            duration: state.duration,
                            enabled: hasMedia && state.duration > Duration.zero,
                            onSeek: (position) => ref.dispatch(SeekAbsolute(position)),
                          ),
                        ),
                        SizedBox(
                          height: rowHeight,
                          child: Row(
                            children: [
                              if (columnWidth >= 170)
                                OmniaIconButton(
                                  icon: Icons.skip_previous_rounded,
                                  size: buttonSize,
                                  iconSize: buttonIcon,
                                  tooltip: l10n.previousFile,
                                  onPressed:
                                      hasPlaylist ? () => ref.dispatch(const PreviousFile()) : null,
                                ),
                              OmniaIconButton(
                                icon:
                                    state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: buttonSize + 4,
                                iconSize: buttonIcon + 4,
                                tooltip: state.isPlaying ? l10n.pause : l10n.play,
                                onPressed: hasMedia ? () => ref.dispatch(const TogglePlay()) : null,
                              ),
                              if (columnWidth >= 170)
                                OmniaIconButton(
                                  icon: Icons.skip_next_rounded,
                                  size: buttonSize,
                                  iconSize: buttonIcon,
                                  tooltip: l10n.nextFile,
                                  onPressed:
                                      hasPlaylist ? () => ref.dispatch(const NextFile()) : null,
                                ),
                              const Spacer(),
                              OmniaIconButton(
                                icon: Icons.playlist_play_rounded,
                                size: buttonSize,
                                iconSize: buttonIcon,
                                tooltip: ref.tooltipWith(
                                  l10n.panelShow,
                                  ShortcutAction.toggleSidePanel,
                                  l10n,
                                ),
                                onPressed: () => ref.dispatch(const ToggleSidePanel()),
                              ),
                              if (columnWidth >= 120)
                                OmniaIconButton(
                                  icon: state.muted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: buttonSize,
                                  iconSize: buttonIcon,
                                  tooltip: state.muted ? l10n.unmute : l10n.mute,
                                  onPressed: () => ref.dispatch(const ToggleMute()),
                                ),
                              OmniaIconButton(
                                icon: state.alwaysOnTop
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                size: buttonSize,
                                iconSize: buttonIcon - 2,
                                active: state.alwaysOnTop,
                                tooltip: l10n.alwaysOnTop,
                                onPressed: () => ref.dispatch(
                                  const ToggleAlwaysOnTop(forMiniPlayer: true),
                                ),
                              ),
                              OmniaIconButton(
                                icon: Icons.open_in_full_rounded,
                                size: buttonSize,
                                iconSize: buttonIcon - 2,
                                tooltip: ref.tooltipWith(
                                  l10n.miniPlayerExit,
                                  ShortcutAction.miniPlayer,
                                  l10n,
                                ),
                                onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Les commandes posées sur l'image vidéo du mini-lecteur.
class _MiniOverlay extends ConsumerWidget {
  const _MiniOverlay({required this.state});

  final PlaybackState state;

  static const double _shadeHeight = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final visible = ref.watch(chromeProvider);

    final hasMedia = state.hasFile && state.mediaType.isAv;
    final hasPlaylist = state.playlist.length > 1;
    final seekStep = ref.watch(preferencesProvider).seekStepSeconds;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: visible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showSkip = width >= MiniPlayer.skipButtonsWidth;
            final showTime = width >= MiniPlayer.timecodeWidth;

            return Stack(
              fit: StackFit.expand,
              children: [
                _shade(colors, top: true),
                _shade(colors, top: false),
                Positioned(
                  top: OmniaMetrics.space1,
                  right: OmniaMetrics.space1,
                  child: _plate(
                    colors,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OmniaIconButton(
                          icon: Icons.playlist_play_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: ref.tooltipWith(
                            l10n.panelShow,
                            ShortcutAction.toggleSidePanel,
                            l10n,
                          ),
                          onPressed: () => ref.dispatch(const ToggleSidePanel()),
                        ),
                        OmniaIconButton(
                          icon: state.alwaysOnTop
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          active: state.alwaysOnTop,
                          tooltip: l10n.alwaysOnTop,
                          onPressed: () => ref.dispatch(
                            const ToggleAlwaysOnTop(forMiniPlayer: true),
                          ),
                        ),
                        OmniaIconButton(
                          icon: Icons.open_in_full_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: ref.tooltipWith(
                            l10n.miniPlayerExit,
                            ShortcutAction.miniPlayer,
                            l10n,
                          ),
                          onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
                        ),
                      ],
                    ),
                  ),
                ),

                Center(
                  child: _plate(
                    colors,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showSkip)
                          OmniaIconButton(
                            icon: Icons.skip_previous_rounded,
                            size: OmniaMetrics.iconButtonSize - 8,
                            iconSize: OmniaMetrics.iconSize - 4,
                            tooltip: l10n.previousFile,
                            onPressed:
                                hasPlaylist ? () => ref.dispatch(const PreviousFile()) : null,
                          ),
                        OmniaIconButton(
                          icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: OmniaMetrics.iconButtonSize,
                          iconSize: OmniaMetrics.iconSize,
                          tooltip: state.isPlaying ? l10n.pause : l10n.play,
                          onPressed: hasMedia ? () => ref.dispatch(const TogglePlay()) : null,
                        ),
                        if (showSkip)
                          OmniaIconButton(
                            icon: Icons.skip_next_rounded,
                            size: OmniaMetrics.iconButtonSize - 8,
                            iconSize: OmniaMetrics.iconSize - 4,
                            tooltip: l10n.nextFile,
                            onPressed: hasPlaylist ? () => ref.dispatch(const NextFile()) : null,
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: OmniaMetrics.space2,
                  right: OmniaMetrics.space2,
                  bottom: OmniaMetrics.space1,
                  child: Row(
                    children: [
                      Expanded(
                        child: BeamProgressBar(
                          progress: state.progress,
                          duration: state.duration,
                          enabled: hasMedia && state.duration > Duration.zero,
                          onSeek: (position) => ref.dispatch(SeekAbsolute(position)),
                          onScrollSeek: (direction) =>
                              ref.dispatch(SeekRelative(seekStep * direction.toDouble())),
                        ),
                      ),
                      if (showTime) ...[
                        const SizedBox(width: OmniaMetrics.space2),
                        Text(
                          formatTimecode(state.position, reference: state.duration),
                          style: type.timecode.copyWith(color: colors.screen),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _shade(OmniaColors colors, {required bool top}) => Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: _shadeHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [colors.velvet.withValues(alpha: 0.55), Colors.transparent],
            ),
          ),
        ),
      );

  Widget _plate(OmniaColors colors, Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.velvet.withValues(alpha: 0.45),
          borderRadius: OmniaMetrics.controlRadius,
        ),
        child: child,
      );
}

/// Commandes superposées pour le mode image en mini-lecteur.
class _MiniImageOverlay extends ConsumerWidget {
  const _MiniImageOverlay({required this.state});

  final PlaybackState state;
  static const double _shadeHeight = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final visible = ref.watch(chromeProvider);
    final hasPlaylist = state.playlist.length > 1;
    final fileName = state.file?.baseName ?? '';

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: visible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _shade(colors, top: true),
            _shade(colors, top: false),
            Positioned(
              top: OmniaMetrics.space1,
              left: OmniaMetrics.space2,
              right: OmniaMetrics.space1,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style: type.caption.copyWith(color: colors.screen),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _plate(
                    colors,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OmniaIconButton(
                          icon: Icons.playlist_play_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: ref.tooltipWith(
                            l10n.panelShow,
                            ShortcutAction.toggleSidePanel,
                            l10n,
                          ),
                          onPressed: () => ref.dispatch(const ToggleSidePanel()),
                        ),
                        OmniaIconButton(
                          icon: state.alwaysOnTop
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          active: state.alwaysOnTop,
                          tooltip: l10n.alwaysOnTop,
                          onPressed: () => ref.dispatch(
                            const ToggleAlwaysOnTop(forMiniPlayer: true),
                          ),
                        ),
                        OmniaIconButton(
                          icon: Icons.open_in_full_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: ref.tooltipWith(
                            l10n.miniPlayerExit,
                            ShortcutAction.miniPlayer,
                            l10n,
                          ),
                          onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: OmniaMetrics.space2,
              right: OmniaMetrics.space2,
              bottom: OmniaMetrics.space1,
              child: Center(
                child: _plate(
                  colors,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasPlaylist)
                        OmniaIconButton(
                          icon: Icons.skip_previous_rounded,
                          size: OmniaMetrics.iconButtonSize - 8,
                          iconSize: OmniaMetrics.iconSize - 4,
                          tooltip: l10n.previousFile,
                          onPressed: () => ref.dispatch(const PreviousFile()),
                        ),
                      OmniaIconButton(
                        icon: Icons.remove_rounded,
                        size: OmniaMetrics.iconButtonSize - 8,
                        iconSize: OmniaMetrics.iconSize - 4,
                        tooltip: l10n.docZoomOut,
                        onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.25)),
                      ),
                      OmniaIconButton(
                        icon: Icons.add_rounded,
                        size: OmniaMetrics.iconButtonSize - 8,
                        iconSize: OmniaMetrics.iconSize - 4,
                        tooltip: l10n.docZoomIn,
                        onPressed: () => ref.dispatch(const ZoomRelative(1.25)),
                      ),
                      OmniaIconButton(
                        icon: Icons.rotate_right_rounded,
                        size: OmniaMetrics.iconButtonSize - 8,
                        iconSize: OmniaMetrics.iconSize - 4,
                        tooltip: 'Pivoter de 90°',
                        active: state.rotation != 0,
                        onPressed: () => ref.dispatch(const RotateDocument()),
                      ),
                      OmniaIconButton(
                        icon: Icons.fit_screen_outlined,
                        size: OmniaMetrics.iconButtonSize - 8,
                        iconSize: OmniaMetrics.iconSize - 4,
                        tooltip: 'Ajuster à la fenêtre',
                        onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
                      ),
                      if (hasPlaylist)
                        OmniaIconButton(
                          icon: Icons.skip_next_rounded,
                          size: OmniaMetrics.iconButtonSize - 8,
                          iconSize: OmniaMetrics.iconSize - 4,
                          tooltip: l10n.nextFile,
                          onPressed: () => ref.dispatch(const NextFile()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shade(OmniaColors colors, {required bool top}) => Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: _shadeHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [colors.velvet.withValues(alpha: 0.55), Colors.transparent],
            ),
          ),
        ),
      );

  Widget _plate(OmniaColors colors, Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.velvet.withValues(alpha: 0.45),
          borderRadius: OmniaMetrics.controlRadius,
        ),
        child: child,
      );
}

/// Commandes superposées pour le mode document (PDF/texte/code) en mini-lecteur.
class _MiniDocumentOverlay extends ConsumerWidget {
  const _MiniDocumentOverlay({required this.state});

  final PlaybackState state;
  static const double _shadeHeight = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final visible = ref.watch(chromeProvider);
    final fileName = state.file?.baseName ?? '';
    final isPdf = state.mediaType == MediaType.pdf;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: visible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _shade(colors, top: true),
            _shade(colors, top: false),
            Positioned(
              top: OmniaMetrics.space1,
              left: OmniaMetrics.space2,
              right: OmniaMetrics.space1,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style: type.caption.copyWith(color: colors.screen),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _plate(
                    colors,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OmniaIconButton(
                          icon: Icons.playlist_play_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: ref.tooltipWith(
                            l10n.panelShow,
                            ShortcutAction.toggleSidePanel,
                            l10n,
                          ),
                          onPressed: () => ref.dispatch(const ToggleSidePanel()),
                        ),
                        OmniaIconButton(
                          icon: state.alwaysOnTop
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          active: state.alwaysOnTop,
                          tooltip: l10n.alwaysOnTop,
                          onPressed: () => ref.dispatch(
                            const ToggleAlwaysOnTop(forMiniPlayer: true),
                          ),
                        ),
                        OmniaIconButton(
                          icon: Icons.open_in_full_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: ref.tooltipWith(
                            l10n.miniPlayerExit,
                            ShortcutAction.miniPlayer,
                            l10n,
                          ),
                          onPressed: () => ref.dispatch(const ToggleMiniPlayer()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: OmniaMetrics.space2,
              right: OmniaMetrics.space2,
              bottom: OmniaMetrics.space1,
              child: Center(
                child: _plate(
                  colors,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPdf) ...[
                        OmniaIconButton(
                          icon: Icons.keyboard_arrow_up_rounded,
                          size: OmniaMetrics.iconButtonSize - 8,
                          iconSize: OmniaMetrics.iconSize - 4,
                          tooltip: l10n.docPreviousPage,
                          onPressed: () => ref.dispatch(const PreviousPage()),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space1),
                          child: Text(
                            l10n.docPageOf(state.currentPage, state.totalPages),
                            style: type.caption.copyWith(color: colors.screen, fontSize: 11),
                          ),
                        ),
                        OmniaIconButton(
                          icon: Icons.keyboard_arrow_down_rounded,
                          size: OmniaMetrics.iconButtonSize - 8,
                          iconSize: OmniaMetrics.iconSize - 4,
                          tooltip: l10n.docNextPage,
                          onPressed: () => ref.dispatch(const NextPage()),
                        ),
                      ],
                      OmniaIconButton(
                        icon: Icons.remove_rounded,
                        size: OmniaMetrics.iconButtonSize - 8,
                        iconSize: OmniaMetrics.iconSize - 4,
                        tooltip: l10n.docZoomOut,
                        onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.25)),
                      ),
                      OmniaIconButton(
                        icon: Icons.add_rounded,
                        size: OmniaMetrics.iconButtonSize - 8,
                        iconSize: OmniaMetrics.iconSize - 4,
                        tooltip: l10n.docZoomIn,
                        onPressed: () => ref.dispatch(const ZoomRelative(1.25)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shade(OmniaColors colors, {required bool top}) => Positioned(
        left: 0,
        right: 0,
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: _shadeHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [colors.velvet.withValues(alpha: 0.55), Colors.transparent],
            ),
          ),
        ),
      );

  Widget _plate(OmniaColors colors, Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.velvet.withValues(alpha: 0.45),
          borderRadius: OmniaMetrics.controlRadius,
        ),
        child: child,
      );
}

/// Tiroir inférieur de liste de lecture pour le mini-lecteur (style YouTube).
class _MiniPlaylistBottomDrawer extends ConsumerWidget {
  const _MiniPlaylistBottomDrawer({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final playlist = ref.watch(playlistStateProvider);
    final currentFilter = playlist.filter;
    final visibleEntries = playlist.visible;

    return Align(
      alignment: Alignment.bottomCenter,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final drawerHeight = constraints.maxHeight < 200
              ? constraints.maxHeight
              : math.min(constraints.maxHeight * 0.85, 300.0);
          return Container(
            height: drawerHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.curtain.withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(OmniaMetrics.radiusLarge),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
              border: Border(
                top: BorderSide(color: colors.screen.withValues(alpha: 0.12), width: 1),
              ),
            ),
            child: Column(
              children: [
                // En-tête
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OmniaMetrics.space3,
                    OmniaMetrics.space2,
                    OmniaMetrics.space2,
                    OmniaMetrics.space1,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.playlist_play_rounded, size: 20, color: colors.projector),
                      const SizedBox(width: OmniaMetrics.space2),
                      Expanded(
                        child: Text(
                          '${l10n.panelTabFolder} (${visibleEntries.length})',
                          style: type.bodyStrong.copyWith(color: colors.screen, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OmniaIconButton(
                        icon: Icons.close_rounded,
                        size: 26,
                        iconSize: 16,
                        tooltip: l10n.closePanel,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                // Filtres par type de média (Tout, Vidéos, Audios, Documents, Images)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OmniaMetrics.space3,
                    vertical: OmniaMetrics.space1,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in PlaylistFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: OmniaMetrics.space1),
                            child: _MiniFilterChip(
                              label: _labelForFilter(filter, l10n),
                              selected: filter == currentFilter,
                              onTap: () => ref.dispatch(SetPlaylistFilter(filter)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
                // Liste des fichiers
                Expanded(
                  child: visibleEntries.isEmpty
                      ? Center(
                          child: Text(
                            l10n.panelEmpty,
                            style: type.caption.copyWith(color: colors.dust),
                          ),
                        )
                      : ListView.builder(
                          itemCount: visibleEntries.length,
                          itemExtent: 40,
                          itemBuilder: (context, index) {
                            final entry = visibleEntries[index];
                            final isCurrent = entry.path == playlist.currentPath;
                            return PlaylistTile(
                              key: ValueKey('mini-pl:${entry.path}'),
                              entry: entry,
                              current: isCurrent,
                              height: 40,
                              onTap: () => ref.dispatch(OpenFile(entry.path)),
                              onSecondaryTap: (_) {},
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _labelForFilter(PlaylistFilter f, AppLocalizations l10n) => switch (f) {
        PlaylistFilter.all => l10n.filterAll,
        PlaylistFilter.video => l10n.filterVideo,
        PlaylistFilter.audio => l10n.filterAudio,
        PlaylistFilter.documents => l10n.filterDocuments,
        PlaylistFilter.images => l10n.filterImages,
      };
}

class _MiniFilterChip extends StatefulWidget {
  const _MiniFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_MiniFilterChip> createState() => _MiniFilterChipState();
}

class _MiniFilterChipState extends State<_MiniFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: OmniaMotion.hover,
          curve: OmniaMotion.hoverCurve,
          padding: const EdgeInsets.symmetric(horizontal: OmniaMetrics.space2, vertical: 3),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.projector.withValues(alpha: 0.22)
                : (_hovered ? colors.screen.withValues(alpha: 0.1) : Colors.transparent),
            borderRadius: const BorderRadius.all(Radius.circular(OmniaMetrics.radiusSmall)),
            border: Border.all(
              color: widget.selected
                  ? colors.projector.withValues(alpha: 0.6)
                  : colors.screen.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Text(
            widget.label,
            style: type.caption.copyWith(
              color: widget.selected ? colors.projector : colors.dust,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
