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
import '../../core/models/window_sizes.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../app_close.dart';
import '../audio_tags_provider.dart';
import '../chrome_controller.dart';
import '../document_search.dart';
import '../document_search_provider.dart';
import '../document_ui_controller.dart';
import '../panel_controller.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_handler.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import '../wheel_steps.dart';
import 'beam_progress_bar.dart';
import 'image_edit_dialog.dart';
import 'image_stage.dart';
import 'omnia_icon_button.dart';
import 'omnia_menu.dart';
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

  /// Seuil de largeur au-delà duquel la liste de lecture se déploie à GAUCHE
  /// (comme le lecteur normal) ; en deçà, elle se déroule EN DESSOUS (vers le bas).
  static const double sidePanelBreakpoint = 520;

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
  double _windowExpandedHeight = 0;
  double? _customPanelWidth;
  double _bottomPlaylistFraction = 0.5;

  @override
  void initState() {
    super.initState();
    _commandSub = ref.read(commandBusProvider).commands.listen((cmd) {
      if (!mounted) return;
      if (cmd is ToggleSidePanel) {
        _toggleDrawer();
      } else if (cmd is SetSidePanelVisible) {
        if (_drawerOpen != cmd.visible) {
          if (cmd.visible) {
            _toggleDrawer();
          } else {
            _closeDrawer();
          }
        }
      }
    });
  }

  Future<void> _toggleDrawer() async {
    final nextState = !_drawerOpen;
    setState(() => _drawerOpen = nextState);
    ref.dispatch(SetSidePanelVisible(nextState));

    try {
      final window = ref.read(windowServiceProvider);
      final bounds = await window.getBounds();
      if (bounds.width < MiniPlayer.sidePanelBreakpoint) {
        if (nextState && bounds.height < 360) {
          await window.setAspectRatio(0);
          _windowExpandedHeight = 160;
          await window.setBounds(Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            bounds.height + _windowExpandedHeight,
          ));
        } else if (!nextState && _windowExpandedHeight > 0) {
          final targetHeight = math.max(
            WindowSizes.miniAudioMinimum.height,
            bounds.height - _windowExpandedHeight,
          );
          _windowExpandedHeight = 0;
          await window.setBounds(Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            targetHeight,
          ));
        }
      }
    } catch (_) {}
  }

  Future<void> _closeDrawer() async {
    if (_drawerOpen) {
      setState(() => _drawerOpen = false);
      ref.dispatch(const SetSidePanelVisible(false));
      try {
        if (_windowExpandedHeight > 0) {
          final window = ref.read(windowServiceProvider);
          final bounds = await window.getBounds();
          final targetHeight = math.max(
            WindowSizes.miniAudioMinimum.height,
            bounds.height - _windowExpandedHeight,
          );
          _windowExpandedHeight = 0;
          await window.setBounds(Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.width,
            targetHeight,
          ));
        }
      } catch (_) {}
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
    // Défilement horizontal (molette inclinable, pavé tactile) : ignoré.
    if (dy == 0) return;

    final state = ref.read(playbackStateProvider);
    if (state.isDocument) {
      if (HardwareKeyboard.instance.isControlPressed) {
        ref.dispatch(ZoomRelative(dy < 0 ? 1.15 : 1 / 1.15));
      } else if (state.mediaType == MediaType.pdf) {
        if (state.documentLayout == DocumentLayout.continuous) {
          ref.dispatch(ScrollDocument(dy > 0 ? 175.0 : -175.0));
        } else {
          ref.dispatch(dy > 0 ? const NextPage() : const PreviousPage());
        }
      } else {
        // Document texte / code : défilement du document (~5 crans pour traverser une vue)
        final currentFraction = state.scrollFraction;
        final step = dy > 0 ? 0.05 : -0.05;
        ref.dispatch(ScrollTo((currentFraction + step).clamp(0.0, 1.0)));
      }
      return;
    }

    if (state.mediaType == MediaType.image) {
      ref.dispatch(ZoomRelative(dy < 0 ? 1.15 : 1 / 1.15));
      return;
    }

    if (!state.mediaType.isAv) return;

    // Par le résolveur : le faisceau, sous le curseur, passe avant le volume.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final step = _volumeWheel.add(dy);
      if (step != 0) ref.dispatch(VolumeRelative(5.0 * step));
    });
  }

  /// Glissement : la fenêtre suit. Clic : lecture/pause si média AV.
  /// Double-clic : retour à la fenêtre entière.
  Widget _windowGestures({
    required Widget child,
    required bool hasMedia,
    bool allowWindowDrag = true,
  }) {
    if (!allowWindowDrag) return child;
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

    final mediaContent = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _onPointerSignal,
      child: content,
    );

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
          child: ColoredBox(
            color: colors.velvet,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= MiniPlayer.sidePanelBreakpoint;
                if (isWide) {
                  // Mode grande fenêtre : la barre latérale s'affiche à GAUCHE comme pour le lecteur normal
                  final storedWidth = ref.watch(panelStateProvider.select((p) => p.width));
                  const minPanelWidth = 160.0;
                  final maxPanelWidth = math.max(minPanelWidth, constraints.maxWidth - 200.0);
                  final initialWidth = math.min(storedWidth, constraints.maxWidth * 0.42);
                  final panelWidth =
                      (_customPanelWidth ?? initialWidth).clamp(minPanelWidth, maxPanelWidth);

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_drawerOpen) ...[
                        SizedBox(
                          width: panelWidth,
                          child: _MiniSidePanel(onClose: _closeDrawer),
                        ),
                        _MiniPanelHorizontalResizeHandle(
                          onResize: (dx) {
                            setState(() {
                              final newWidth =
                                  (panelWidth + dx).clamp(minPanelWidth, maxPanelWidth);
                              _customPanelWidth = newWidth;
                            });
                            ref.read(panelStateProvider.notifier).setWidth(
                                  (panelWidth + dx).clamp(
                                    OmniaMetrics.panelMinWidth,
                                    OmniaMetrics.panelMaxWidth,
                                  ),
                                );
                          },
                        ),
                      ],
                      Expanded(child: mediaContent),
                    ],
                  );
                } else {
                  // Mode compact : la playlist se déroule EN DESSOUS (vers le bas) sous la vidéo.
                  // La vidéo reste toujours visible en haut et n'est jamais masquée !
                  if (!_drawerOpen) {
                    return mediaContent;
                  }
                  final flexMedia =
                      (math.max(0.2, 1.0 - _bottomPlaylistFraction) * 1000).round();
                  final flexPlaylist =
                      (math.max(0.2, _bottomPlaylistFraction) * 1000).round();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: flexMedia,
                        child: mediaContent,
                      ),
                      _MiniPanelVerticalResizeHandle(
                        onResize: (dy) {
                          setState(() {
                            final totalHeight = constraints.maxHeight;
                            if (totalHeight > 100) {
                              final newFraction =
                                  (_bottomPlaylistFraction - dy / totalHeight).clamp(0.2, 0.8);
                              _bottomPlaylistFraction = newFraction;
                            }
                          });
                        },
                      ),
                      Expanded(
                        flex: flexPlaylist,
                        child: _MiniBottomPlaylist(onClose: _closeDrawer),
                      ),
                    ],
                  );
                }
              },
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
            child: IgnorePointer(
              child: ImageStage(
                key: ValueKey('mini-image:${state.file!.path}'),
                file: state.file!,
              ),
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
    final isEditing = ref.watch(documentUiProvider.select((u) => u.isEditing));
    Widget docWidget;
    if (textDocument != null) {
      docWidget = isEditing
          ? TextView(
              key: ValueKey('text:${textDocument.path}'),
              document: textDocument,
              search: ref.watch(documentSearchProvider) as PlainTextSearch?,
            )
          : IgnorePointer(
              child: TextView(
                key: ValueKey('text:${textDocument.path}'),
                document: textDocument,
                search: ref.watch(documentSearchProvider) as PlainTextSearch?,
              ),
            );
    } else if (state.mediaType == MediaType.pdf) {
      docWidget = const IgnorePointer(
        child: PdfStage(key: ValueKey('pdf')),
      );
    } else {
      docWidget = const SizedBox.shrink();
    }

    return Listener(
      onPointerDown: (_) => ref.read(documentUiProvider.notifier).setDocumentFocused(true),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          StageContextMenu(
            child: _windowGestures(
              hasMedia: false,
              allowWindowDrag: !isEditing,
              child: docWidget,
            ),
          ),
          _MiniDocumentOverlay(state: state),
        ],
      ),
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
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: math.max(columnWidth, 180.0),
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
                                  OmniaIconButton(
                                    icon: Icons.close_rounded,
                                    size: buttonSize,
                                    iconSize: buttonIcon - 2,
                                    tooltip: l10n.closeWindow,
                                    danger: true,
                                    onPressed: () => closeApplication(ref, context),
                                  ),
                                ],
                              ),
                            ),
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
                const Positioned.fill(
                  child: DragToMoveArea(child: SizedBox.expand()),
                ),
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
                        OmniaIconButton(
                          icon: Icons.close_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: l10n.closeWindow,
                          danger: true,
                          onPressed: () => closeApplication(ref, context),
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
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [colors.velvet.withValues(alpha: 0.55), Colors.transparent],
              ),
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
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
            _shade(colors, top: true),
            _shade(colors, top: false),
            Positioned(
              top: OmniaMetrics.space1,
              left: OmniaMetrics.space2,
              right: OmniaMetrics.space1,
              child: Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(
                      child: Text(
                        fileName,
                        style: type.caption.copyWith(color: colors.screen),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        OmniaIconButton(
                          icon: Icons.close_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: l10n.closeWindow,
                          danger: true,
                          onPressed: () => closeApplication(ref, context),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 340;
                    if (isCompact) {
                      return _plate(
                        colors,
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                            if (state.file != null)
                              OmniaIconButton(
                                icon: Icons.tune_rounded,
                                size: OmniaMetrics.iconButtonSize - 8,
                                iconSize: OmniaMetrics.iconSize - 4,
                                tooltip: 'Retoucher l’image',
                                onPressed: () => ImageEditDialog.show(context, state.file!),
                              ),
                            _MiniOverflowMenu(
                              menuChildren: [
                                OmniaMenuItem(
                                  icon: Icons.rotate_right_rounded,
                                  label: 'Pivoter de 90°',
                                  active: state.rotation != 0,
                                  onPressed: () => ref.dispatch(const RotateDocument()),
                                ),
                                OmniaMenuItem(
                                  icon: Icons.fit_screen_outlined,
                                  label: 'Ajuster à la fenêtre',
                                  onPressed: () => ref.dispatch(const FitZoom(FitMode.width)),
                                ),
                                if (hasPlaylist) ...[
                                  const OmniaMenuDivider(),
                                  OmniaMenuItem(
                                    icon: Icons.skip_previous_rounded,
                                    label: l10n.previousFile,
                                    onPressed: () => ref.dispatch(const PreviousFile()),
                                  ),
                                  OmniaMenuItem(
                                    icon: Icons.skip_next_rounded,
                                    label: l10n.nextFile,
                                    onPressed: () => ref.dispatch(const NextFile()),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    return _plate(
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
                          if (state.file != null)
                            OmniaIconButton(
                              icon: Icons.tune_rounded,
                              size: OmniaMetrics.iconButtonSize - 8,
                              iconSize: OmniaMetrics.iconSize - 4,
                              tooltip: 'Retoucher et redimensionner',
                              onPressed: () => ImageEditDialog.show(context, state.file!),
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
                    );
                  },
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
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [colors.velvet.withValues(alpha: 0.55), Colors.transparent],
              ),
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
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
            _shade(colors, top: true),
            _shade(colors, top: false),
            Positioned(
              top: OmniaMetrics.space1,
              left: OmniaMetrics.space2,
              right: OmniaMetrics.space1,
              child: Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(
                      child: Text(
                        fileName,
                        style: type.caption.copyWith(color: colors.screen),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        OmniaIconButton(
                          icon: Icons.close_rounded,
                          size: OmniaMetrics.iconButtonSize - 6,
                          iconSize: OmniaMetrics.iconSize - 6,
                          tooltip: l10n.closeWindow,
                          danger: true,
                          onPressed: () => closeApplication(ref, context),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final ui = ref.watch(documentUiProvider);
                    final canEdit = !isPdf && (state.mediaType == MediaType.text || state.mediaType == MediaType.doc);
                    final isCompact = constraints.maxWidth < 340;

                    if (isCompact) {
                      return _plate(
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
                            ] else if (canEdit) ...[
                              if (ui.isEditing) ...[
                                OmniaIconButton(
                                  icon: Icons.save_rounded,
                                  size: OmniaMetrics.iconButtonSize - 8,
                                  iconSize: OmniaMetrics.iconSize - 4,
                                  tooltip: 'Enregistrer les modifications',
                                  active: ui.hasUnsavedChanges,
                                  onPressed: () => ref.read(documentUiProvider.notifier).requestSave(),
                                ),
                                OmniaIconButton(
                                  icon: Icons.visibility_outlined,
                                  size: OmniaMetrics.iconButtonSize - 8,
                                  iconSize: OmniaMetrics.iconSize - 4,
                                  tooltip: 'Terminer la modification (Lecture seule)',
                                  active: true,
                                  onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
                                ),
                              ] else ...[
                                OmniaIconButton(
                                  icon: Icons.edit_outlined,
                                  size: OmniaMetrics.iconButtonSize - 8,
                                  iconSize: OmniaMetrics.iconSize - 4,
                                  tooltip: 'Modifier le document',
                                  onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
                                ),
                              ],
                            ],
                            _MiniOverflowMenu(
                              menuChildren: [
                                OmniaMenuItem(
                                  icon: Icons.remove_rounded,
                                  label: l10n.docZoomOut,
                                  onPressed: () => ref.dispatch(const ZoomRelative(1 / 1.25)),
                                ),
                                OmniaMenuItem(
                                  icon: Icons.add_rounded,
                                  label: l10n.docZoomIn,
                                  onPressed: () => ref.dispatch(const ZoomRelative(1.25)),
                                ),
                                if (canEdit && !ui.isEditing)
                                  OmniaMenuItem(
                                    icon: Icons.edit_outlined,
                                    label: 'Modifier le document',
                                    onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    return _plate(
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
                          if (canEdit) ...[
                            if (ui.isEditing) ...[
                              OmniaIconButton(
                                icon: Icons.save_rounded,
                                size: OmniaMetrics.iconButtonSize - 8,
                                iconSize: OmniaMetrics.iconSize - 4,
                                tooltip: 'Enregistrer les modifications',
                                active: ui.hasUnsavedChanges,
                                onPressed: () => ref.read(documentUiProvider.notifier).requestSave(),
                              ),
                              OmniaIconButton(
                                icon: Icons.visibility_outlined,
                                size: OmniaMetrics.iconButtonSize - 8,
                                iconSize: OmniaMetrics.iconSize - 4,
                                tooltip: 'Terminer la modification (Lecture seule)',
                                active: true,
                                onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
                              ),
                            ] else ...[
                              OmniaIconButton(
                                icon: Icons.edit_outlined,
                                size: OmniaMetrics.iconButtonSize - 8,
                                iconSize: OmniaMetrics.iconSize - 4,
                                tooltip: 'Modifier le document',
                                onPressed: () => ref.read(documentUiProvider.notifier).toggleEdit(),
                              ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
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
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [colors.velvet.withValues(alpha: 0.55), Colors.transparent],
              ),
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

/// Panneau latéral de liste de lecture pour le mini-lecteur en mode grand format (déploiement à gauche).
class _MiniSidePanel extends ConsumerWidget {
  const _MiniSidePanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final playlist = ref.watch(playlistStateProvider);
    final currentFilter = playlist.filter;
    final visibleEntries = playlist.visible;

    return Container(
      decoration: BoxDecoration(
        color: colors.curtain,
        border: Border(right: BorderSide(color: colors.seam)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête panneau latéral gauche
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OmniaMetrics.space3,
              OmniaMetrics.space2,
              OmniaMetrics.space2,
              OmniaMetrics.space1,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.panelTabFolder,
                        style: type.bodyStrong.copyWith(color: colors.screen, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        l10n.panelFileCountFiltered(visibleEntries.length, playlist.entries.length),
                        style: type.caption.copyWith(color: colors.dust, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                OmniaIconButton(
                  icon: Icons.keyboard_double_arrow_left_rounded,
                  size: 26,
                  iconSize: 16,
                  tooltip: l10n.closePanel,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Filtres par type de média (Wrap pour que tous les filtres dont Images restent toujours visibles)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              OmniaMetrics.space3,
              OmniaMetrics.space1,
              OmniaMetrics.space3,
              OmniaMetrics.space1,
            ),
            child: Wrap(
              spacing: OmniaMetrics.space1,
              runSpacing: OmniaMetrics.space1,
              children: [
                for (final filter in PlaylistFilter.values)
                  _MiniFilterChip(
                    label: _labelForFilter(filter, l10n),
                    selected: filter == currentFilter,
                    onTap: () => ref.dispatch(SetPlaylistFilter(filter)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          // Liste des éléments
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
                        key: ValueKey('mini-side-pl:${entry.path}'),
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
  }
}

/// Déroulé inférieur de liste de lecture pour le mini-lecteur (style YouTube : en dessous, vers le bas).
class _MiniBottomPlaylist extends ConsumerWidget {
  const _MiniBottomPlaylist({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final playlist = ref.watch(playlistStateProvider);
    final state = ref.watch(playbackStateProvider);
    final currentFilter = playlist.filter;
    final visibleEntries = playlist.visible;

    final currentTitle = state.file?.baseName ?? l10n.panelTabFolder;
    final queueInfo = playlist.entries.isNotEmpty
        ? 'File d\'attente • ${playlist.currentIndex + 1} / ${playlist.entries.length}'
        : l10n.panelFileCount(visibleEntries.length);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showFilters = constraints.maxHeight >= 110;
        return Listener(
          onPointerDown: (_) => ref.read(documentUiProvider.notifier).setDocumentFocused(false),
          behavior: HitTestBehavior.translucent,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.curtain,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // En-tête : Titre, info file d'attente (YouTube) et boutons de repli
              InkWell(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OmniaMetrics.space3,
                    OmniaMetrics.space1,
                    OmniaMetrics.space2,
                    OmniaMetrics.space1,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.playlist_play_rounded, size: 20, color: colors.projector),
                      const SizedBox(width: OmniaMetrics.space2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentTitle,
                              style: type.bodyStrong.copyWith(color: colors.screen, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              queueInfo,
                              style: type.caption.copyWith(color: colors.dust, fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      OmniaIconButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        size: 26,
                        iconSize: 20,
                        tooltip: l10n.closePanel,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ),
              // Filtres par type de média (affichés si la hauteur le permet)
              if (showFilters) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OmniaMetrics.space3,
                    vertical: OmniaMetrics.space1,
                  ),
                  child: Wrap(
                    spacing: OmniaMetrics.space1,
                    runSpacing: OmniaMetrics.space1,
                    children: [
                      for (final filter in PlaylistFilter.values)
                        _MiniFilterChip(
                          label: _labelForFilter(filter, l10n),
                          selected: filter == currentFilter,
                          onTap: () => ref.dispatch(SetPlaylistFilter(filter)),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.5),
              ],
              // Liste des fichiers (clé mini-pl pour compatibilité des tests)
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
                        itemExtent: 38,
                        itemBuilder: (context, index) {
                          final entry = visibleEntries[index];
                          final isCurrent = entry.path == playlist.currentPath;
                          return PlaylistTile(
                            key: ValueKey('mini-pl:${entry.path}'),
                            entry: entry,
                            current: isCurrent,
                            height: 38,
                            onTap: () => ref.dispatch(OpenFile(entry.path)),
                            onSecondaryTap: (_) {},
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
  }
}

String _labelForFilter(PlaylistFilter f, AppLocalizations l10n) => switch (f) {
      PlaylistFilter.all => l10n.filterAll,
      PlaylistFilter.video => l10n.filterVideo,
      PlaylistFilter.audio => l10n.filterAudio,
      PlaylistFilter.documents => l10n.filterDocuments,
      PlaylistFilter.images => l10n.filterImages,
    };

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

/// Poignée de redimensionnement horizontal pour le volet latéral en mode mini-lecteur large.
class _MiniPanelHorizontalResizeHandle extends StatefulWidget {
  const _MiniPanelHorizontalResizeHandle({required this.onResize});

  final ValueChanged<double> onResize;
  static const double width = 6;

  @override
  State<_MiniPanelHorizontalResizeHandle> createState() =>
      _MiniPanelHorizontalResizeHandleState();
}

class _MiniPanelHorizontalResizeHandleState
    extends State<_MiniPanelHorizontalResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: Tooltip(
        message: l10n.resizePanel,
        waitDuration: const Duration(seconds: 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => widget.onResize(details.delta.dx),
          child: SizedBox(
            width: _MiniPanelHorizontalResizeHandle.width,
            child: Center(
              child: AnimatedContainer(
                duration: OmniaMotion.hover,
                curve: OmniaMotion.hoverCurve,
                width: _active ? 2 : 1,
                color: _active ? colors.projector : colors.seam,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Poignée de redimensionnement vertical pour la liste de lecture inférieure en mode compact.
class _MiniPanelVerticalResizeHandle extends StatefulWidget {
  const _MiniPanelVerticalResizeHandle({required this.onResize});

  final ValueChanged<double> onResize;
  static const double height = 8;

  @override
  State<_MiniPanelVerticalResizeHandle> createState() =>
      _MiniPanelVerticalResizeHandleState();
}

class _MiniPanelVerticalResizeHandleState
    extends State<_MiniPanelVerticalResizeHandle> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _active = true),
      onExit: (_) => setState(() => _active = false),
      child: Tooltip(
        message: l10n.resizePanel,
        waitDuration: const Duration(seconds: 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => widget.onResize(details.delta.dy),
          child: Container(
            height: _MiniPanelVerticalResizeHandle.height,
            color: colors.curtain,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: OmniaMotion.hover,
              curve: OmniaMotion.hoverCurve,
              width: 36,
              height: _active ? 4 : 3,
              decoration: BoxDecoration(
                color: _active
                    ? colors.projector
                    : colors.screen.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Menu contextuel 3 points compact pour les barres du mini-lecteur.
class _MiniOverflowMenu extends StatelessWidget {
  const _MiniOverflowMenu({required this.menuChildren});

  final List<Widget> menuChildren;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, _) => OmniaIconButton(
        icon: Icons.more_horiz_rounded,
        size: OmniaMetrics.iconButtonSize - 8,
        iconSize: OmniaMetrics.iconSize - 4,
        tooltip: 'Plus d’actions',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: menuChildren,
    );
  }
}
