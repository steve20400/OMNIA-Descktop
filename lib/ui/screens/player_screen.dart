import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/services/screen_wake.dart';
import '../../core/utils/launch_arguments.dart';
import '../../core/utils/platform_session.dart';
import '../../l10n/app_localizations.dart';
import '../document_search_provider.dart';
import '../document_ui_controller.dart';
import '../panel_controller.dart';
import '../player_focus.dart';
import '../settings/settings_screen.dart';
import '../shortcuts/shortcut_handler.dart';
import '../theme/omnia_theme.dart';
import '../widgets/control_bar.dart';
import '../widgets/document_bar.dart';
import '../widgets/find_bar.dart';
import '../widgets/help_overlay.dart';
import '../widgets/mini_player.dart';
import '../widgets/osd_overlay.dart';
import '../widgets/resume_prompt.dart';
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

  /// Point de retour du focus clavier, pour les panneaux qui se ferment.
  late final PlayerFocus _playerFocus = ref.read(playerFocusProvider);

  @override
  void initState() {
    super.initState();
    _playerFocus.attach(_focusNode);
    // Argument en ligne de commande : `omnia /chemin/fichier.mkv`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final command = commandForLaunchArguments(ref.read(launchArgumentsProvider));
      if (command != null) ref.dispatch(command, source: CommandSource.cli);
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _playerFocus.detach(_focusNode);
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

  /// Même règle que pour un fichier déposé sur l'icône : premier dossier ou
  /// fichier lisible ; un sous-titre déposé sur une vidéo s'y charge.
  void _onDrop(DropDoneDetails details) {
    setState(() => _dragging = false);
    final state = ref.read(playbackStateProvider);
    final command = commandForPaths(
      [for (final file in details.files) file.path],
      videoPlaying: state.hasFile && state.hasVideo,
    );
    if (command != null) ref.dispatch(command);
  }

  /// Toute la fenêtre accepte fichiers et dossiers, sous un voile qui
  /// confirme le dépôt — mini-lecteur compris.
  ///
  /// L'écran n'a pas de Scaffold : ce Material transparent fournit le style
  /// de texte par défaut (sans lui, Flutter souligne tout texte en jaune) et
  /// l'ancêtre qu'exigent les champs de saisie et les boutons à encre.
  Widget _dropZone(Widget child) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final veil = IgnorePointer(
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
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(fit: StackFit.expand, children: [child, veil]),
      ),
    );
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
    if (miniPlayer) return _dropZone(const MiniPlayer());
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
                              // Invite de reprise, au-dessus des contrôles ;
                              // sans taille quand il n'y a rien à proposer.
                              const Positioned(
                                left: 0,
                                right: 0,
                                bottom: OmniaMetrics.resumePromptBottom,
                                child: Center(child: ResumePrompt()),
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
    Widget root = _dropZone(
      Stack(
        fit: StackFit.expand,
        children: [content, const HelpOverlay(), const SettingsOverlay()],
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
