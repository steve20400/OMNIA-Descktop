import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/services/screen_wake.dart';
import '../../core/utils/launch_arguments.dart';
import '../../core/utils/platform_session.dart';
import '../../l10n/app_localizations.dart';
import '../document_search_provider.dart';
import '../document_ui_controller.dart';
import '../panel_controller.dart';
import '../shortcuts/shortcut_handler.dart';
import '../theme/omnia_theme.dart';
import '../widgets/control_bar.dart';
import '../widgets/document_bar.dart';
import '../widgets/find_bar.dart';
import '../widgets/help_overlay.dart';
import '../widgets/mini_player.dart';
import '../widgets/osd_overlay.dart';
import '../widgets/side_panel.dart';
import '../widgets/stage.dart';
import '../widgets/stage_context_menu.dart';
import '../widgets/title_bar.dart';
import '../widgets/tool_panels.dart';

/// Écran unique d'OMNIA : barre de titre, panneau de dossier, scène,
/// contrôles flottants.
///
/// Gère aussi le glisser-déposer, les raccourcis clavier, la molette (volume)
/// et le masquage automatique des contrôles en plein écran.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'omnia.root');
  bool _dragging = false;
  bool _chromeVisible = true;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    // Argument en ligne de commande : `omnia /chemin/fichier.mkv`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final command = commandForLaunchArguments(ref.read(launchArgumentsProvider));
      if (command != null) ref.dispatch(command, source: CommandSource.cli);
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // --- Visibilité des contrôles ------------------------------------------

  void _revealChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _armIdleTimer();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (!ref.read(playbackStateProvider).fullscreen) return;
    _idleTimer = Timer(OmniaMotion.idleHide, () {
      if (!mounted) return;
      setState(() => _chromeVisible = false);
    });
  }

  // --- Glisser-déposer -----------------------------------------------------

  void _onDrop(DropDoneDetails details) {
    setState(() => _dragging = false);
    for (final xfile in details.files) {
      final path = xfile.path;
      if (FileSystemEntity.isDirectorySync(path)) {
        ref.dispatch(OpenFolder(path));
        return;
      }
      if (MediaRouter.isSupported(path)) {
        ref.dispatch(OpenFile(path));
        return;
      }
    }
    // Aucun fichier lisible : on tente quand même le premier, pour afficher
    // un message d'erreur clair plutôt que de rester silencieux.
    final first = details.files.firstOrNull?.path;
    if (first != null) ref.dispatch(OpenFile(first));
  }

  // --- Molette : volume (média) ou zoom avec Ctrl (document) ----------------

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final state = ref.read(playbackStateProvider);
    if (state.isDocument) {
      if (!HardwareKeyboard.instance.isControlPressed) return;
      // On consomme l'événement : la vue ne doit pas défiler en plus de zoomer.
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        ref.dispatch(ZoomRelative(event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1));
      });
      return;
    }
    if (!state.mediaType.isAv) return;
    final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
    ref.dispatch(VolumeRelative(delta));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    // On n'observe que les champs dont dépend la structure de l'écran : la
    // position de lecture change plusieurs fois par seconde et ne doit pas
    // reconstruire tout l'arbre.
    final fullscreen = ref.watch(playbackStateProvider.select((s) => s.fullscreen));
    final hasFile = ref.watch(playbackStateProvider.select((s) => s.hasFile));
    final canToggleByClick = ref.watch(
      playbackStateProvider.select(
        (s) => s.hasFile && s.status != PlaybackStatus.error && s.mediaType.isAv,
      ),
    );
    final isDocument = ref.watch(playbackStateProvider.select((s) => s.isDocument));
    final miniPlayer = ref.watch(playbackStateProvider.select((s) => s.miniPlayer));
    if (miniPlayer) return const MiniPlayer();
    final findVisible = ref.watch(documentUiProvider.select((u) => u.findVisible));
    final search = ref.watch(documentSearchProvider);
    final panelVisible = ref.watch(panelStateProvider.select((p) => p.visible));

    ref.listen<bool>(playbackStateProvider.select((s) => s.fullscreen), (_, fullscreen) {
      if (fullscreen) {
        _armIdleTimer();
      } else {
        _idleTimer?.cancel();
        if (!_chromeVisible) setState(() => _chromeVisible = true);
      }
    });

    // L'écran reste allumé tant qu'une vidéo joue, et seulement là.
    ref.listen<bool>(
      playbackStateProvider.select(
        (s) => shouldKeepScreenAwake(playing: s.isPlaying, hasVideo: s.hasVideo),
      ),
      (_, keepAwake) => ref.read(screenWakeProvider).setKeepAwake(keepAwake),
    );

    final hideCursor = fullscreen && !_chromeVisible;
    // En plein écran, la scène occupe tout : le panneau se retire.
    final showPanel = panelVisible && !fullscreen;

    final content = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) => handleShortcut(event, ref),
      child: MouseRegion(
        cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
        onHover: (_) => _revealChrome(),
        child: Listener(
          onPointerDown: (_) => _revealChrome(),
          child: ColoredBox(
            color: colors.velvet,
            child: Column(
              children: [
                if (!fullscreen) const TitleBar(),
                Expanded(
                  child: Row(
                    children: [
                      if (!fullscreen) const SidePanel(),
                      if (showPanel) const PanelResizeHandle(),
                      Expanded(
                        child: Listener(
                          onPointerSignal: _onPointerSignal,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              StageContextMenu(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: canToggleByClick
                                      ? () {
                                          _focusNode.requestFocus();
                                          ref.dispatch(const TogglePlay());
                                        }
                                      : _focusNode.requestFocus,
                                  onDoubleTap: hasFile
                                      ? () => ref.dispatch(const ToggleFullscreen())
                                      : null,
                                  child: const Stage(),
                                ),
                              ),
                              const OsdOverlay(),
                              if (isDocument && findVisible && search != null)
                                Positioned(
                                  right: OmniaMetrics.space4,
                                  top: OmniaMetrics.space4,
                                  child: FindBar(search: search),
                                ),
                              if (!showPanel && !fullscreen)
                                const Positioned(
                                  left: OmniaMetrics.space3,
                                  top: OmniaMetrics.space3,
                                  child: PanelRevealButton(),
                                ),
                              Positioned(
                                right: OmniaMetrics.controlBarMargin,
                                bottom: OmniaMetrics.controlBarMargin + 96,
                                child: const ToolPanelHost(),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  ignoring: !_chromeVisible,
                                  child: AnimatedOpacity(
                                    opacity: _chromeVisible ? 1 : 0,
                                    duration: OmniaMotion.reveal,
                                    curve: _chromeVisible
                                        ? OmniaMotion.revealCurve
                                        : OmniaMotion.concealCurve,
                                    child: AnimatedSlide(
                                      offset: _chromeVisible
                                          ? Offset.zero
                                          : const Offset(0, 0.12),
                                      duration: OmniaMotion.reveal,
                                      curve: OmniaMotion.revealCurve,
                                      child: isDocument
                                          ? const DocumentBar()
                                          : const ControlBar(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

    // Le voile de dépôt couvre toute la fenêtre, panneau compris.
    final dropOverlay = IgnorePointer(
      child: AnimatedOpacity(
        opacity: _dragging ? 1 : 0,
        duration: OmniaMotion.reveal,
        curve: OmniaMotion.revealCurve,
        child: Container(
          color: colors.overlayScrim,
          padding: const EdgeInsets.all(OmniaMetrics.space4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: OmniaMetrics.overlayRadius,
              border: Border.all(color: colors.projector, width: 1.5),
            ),
            child: Center(child: Text(l10n.dropToPlay, style: type.viewTitle)),
          ),
        ),
      ),
    );

    Widget root = DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Stack(
        fit: StackFit.expand,
        children: [content, const HelpOverlay(), dropOverlay],
      ),
    );

    // Sous Linux, masquer la barre de titre retire aussi les bordures de
    // redimensionnement de GTK : OMNIA doit les fournir lui-même, sans quoi la
    // fenêtre ne peut plus être redimensionnée à la souris.
    if (needsCustomResizeEdges && !fullscreen) {
      root = DragToResizeArea(resizeEdgeSize: 5, child: root);
    }
    return root;
  }
}
