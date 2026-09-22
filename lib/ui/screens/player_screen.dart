import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../core/services/screen_wake.dart';
import '../../core/utils/launch_arguments.dart';
import '../../core/utils/platform_session.dart';
import '../../l10n/app_localizations.dart';
import '../chrome_controller.dart';
import '../document_search_provider.dart';
import '../document_ui_controller.dart';
import '../panel_controller.dart';
import '../player_focus.dart';
import '../settings/settings_screen.dart';
import '../shortcuts/shortcut_handler.dart';
import '../theme/omnia_theme.dart';
import '../tool_panel_controller.dart';
import '../wheel_steps.dart';
import '../widgets/control_bar.dart';
import '../widgets/document_bar.dart';
import '../widgets/find_bar.dart';
import '../widgets/help_overlay.dart';
import '../widgets/image_bar.dart';
import '../widgets/mini_player.dart';
import '../widgets/osd_overlay.dart';
import '../widgets/recording_indicator.dart';
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

  /// Point de retour du focus clavier, pour les panneaux qui se ferment.
  late final PlayerFocus _playerFocus = ref.read(playerFocusProvider);

  @override
  void initState() {
    super.initState();
    _playerFocus.attach(_focusNode);
    // Argument en ligne de commande : `omnia /chemin/fichier.mkv` ou reprise de session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final command = commandForLaunchArguments(ref.read(launchArgumentsProvider));
      if (command != null) {
        ref.dispatch(command, source: CommandSource.cli);
      } else {
        final prefs = ref.read(preferencesProvider);
        if (prefs.restoreLastSession) {
          final lastPath = ref.read(settingsStoreProvider).lastOpenPath;
          if (lastPath != null && File(lastPath).existsSync()) {
            ref.dispatch(OpenFile(lastPath), source: CommandSource.system);
          }
        }
      }
      _chrome.setAutoHide(_autoHideFor(ref.read(playbackStateProvider)));
    });
  }

  @override
  void dispose() {
    _playerFocus.detach(_focusNode);
    _focusNode.dispose();
    super.dispose();
  }

  // --- Visibilité des contrôles ------------------------------------------

  /// Masquage automatique des contrôles, dans tous les modes d'affichage :
  /// - une vidéo qui joue ;
  /// - en plein écran, tout média audio ou vidéo qui joue, et les documents
  ///   (mode lecture).
  /// En pause, en fin de lecture ou en erreur, la barre reste : c'est là qu'on
  /// s'en sert. Un son en fenêtre la garde aussi, rien n'est caché dessous ;
  /// un document en fenêtre également, on y navigue de page en page.
  static bool _autoHideFor(PlaybackState s) {
    if (!s.hasFile || s.status == PlaybackStatus.error) return false;
    if (s.isDocument || s.mediaType == MediaType.image) return s.fullscreen;
    if (!s.mediaType.isAv || s.status != PlaybackStatus.playing) return false;
    return s.hasVideo || s.fullscreen;
  }

  /// Molette au-dessus du média : crans de volume regroupés.
  final WheelSteps _volumeWheel = WheelSteps();

  ChromeController get _chrome => ref.read(chromeProvider.notifier);

  // Ce qui retient les contrôles affichés.
  static const _barHold = 'chrome:control-bar';
  static const _toolPanelHold = 'chrome:tool-panel';
  static const _resumeHold = 'chrome:resume-prompt';

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
    final dy = event.scrollDelta.dy;
    // Défilement horizontal (molette inclinable, pavé tactile) : ni volume ni
    // zoom.
    if (dy == 0) return;
    final state = ref.read(playbackStateProvider);
    if (state.isDocument || state.mediaType == MediaType.image) {
      if (!HardwareKeyboard.instance.isControlPressed) return;
      // On consomme l'événement : la vue ne doit pas défiler en plus de zoomer.
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        ref.dispatch(ZoomRelative(dy < 0 ? 1.1 : 1 / 1.1));
      });
      return;
    }
    if (!state.mediaType.isAv) return;
    // Par le résolveur : un élément plus précis sous le curseur (la barre de
    // progression, qui fait avancer la lecture) passe avant le volume.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final step = _volumeWheel.add(dy);
      if (step != 0) ref.dispatch(VolumeRelative(5.0 * step));
    });
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
    final isImage = ref.watch(playbackStateProvider.select((s) => s.mediaType == MediaType.image));
    final miniPlayer = ref.watch(playbackStateProvider.select((s) => s.miniPlayer));

    // Les écoutes avant toute sortie anticipée : flutter_riverpod les referme
    // à chaque construction, et le mini-lecteur les perdrait en chemin — plus
    // de masquage automatique, plus d'écran qui reste allumé.
    ref.listen<bool>(
      playbackStateProvider.select(_autoHideFor),
      (_, enabled) => _chrome.setAutoHide(enabled),
    );
    ref.listen<ToolPanel>(
      toolPanelProvider,
      (_, panel) => panel == ToolPanel.none
          ? _chrome.release(_toolPanelHold)
          : _chrome.hold(_toolPanelHold),
    );
    ref.listen<bool>(
      playbackStateProvider.select((s) => s.resumeOffer != null),
      (_, offered) => offered ? _chrome.hold(_resumeHold) : _chrome.release(_resumeHold),
    );
    // L'écran reste allumé tant qu'une vidéo joue, et seulement là.
    ref.listen<bool>(
      playbackStateProvider.select(
        (s) => shouldKeepScreenAwake(playing: s.isPlaying, hasVideo: s.hasVideo),
      ),
      (_, keepAwake) => ref.read(screenWakeProvider).setKeepAwake(keepAwake),
    );

    // Le mini-lecteur remplace tout l'écran : il a besoin des mêmes bordures
    // de redimensionnement que la fenêtre principale.
    if (miniPlayer) return _resizable(_dropZone(const MiniPlayer()), enabled: true);

    final findVisible = ref.watch(documentUiProvider.select((u) => u.findVisible));
    final search = ref.watch(documentSearchProvider);
    final panelVisible = ref.watch(panelStateProvider.select((p) => p.visible));
    final panelWidth = ref.watch(panelStateProvider.select((p) => p.width));
    final chromeVisible = ref.watch(chromeProvider);

    // Contrôles masqués : le pointeur s'efface aussi, au-dessus du média
    // seulement (la barre de titre et le panneau le gardent).
    final hideCursor = !chromeVisible;
    // Fenêtre étroite ou plein écran : le panneau se pose en tiroir sur la
    // scène, qui garde toute sa largeur. Sinon il s'ancre à côté d'elle.
    final drawer = panelIsDrawer(
      windowWidth: MediaQuery.sizeOf(context).width,
      panelWidth: panelWidth,
      fullscreen: fullscreen,
    );
    final showDrawer = panelVisible && drawer;
    final showDocked = panelVisible && !drawer;

    final content = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (_, event) =>
          handleShortcut(event, ref, panelDrawerOpen: showDrawer),
      child: MouseRegion(
        onHover: (_) => _chrome.activity(),
        child: Listener(
          onPointerDown: (_) => _chrome.activity(),
          // Un glissement bouton enfoncé n'est pas un survol : il compte aussi.
          onPointerMove: (_) => _chrome.activity(),
          child: ColoredBox(
            color: colors.velvet,
            child: Column(
              children: [
                // Frontières de rafraîchissement : chaque image vidéo redessine
                // la scène, pas la barre de titre ni le panneau.
                if (!fullscreen) const RepaintBoundary(child: TitleBar()),
                Expanded(
                  child: Row(
                    children: [
                      if (!drawer) const RepaintBoundary(child: SidePanel()),
                      if (showDocked) const PanelResizeHandle(),
                      Expanded(
                        child: MouseRegion(
                          cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
                          onExit: (_) => _chrome.pointerLeft(),
                          child: Listener(
                            onPointerSignal: _onPointerSignal,
                            // La hauteur de la scène décide de la place laissée
                            // aux surfaces qui s'y posent : sur 200 pixels, la
                            // barre de contrôles ne peut pas tout réserver.
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final stageHeight = constraints.hasBoundedHeight
                                    ? constraints.maxHeight
                                    : MediaQuery.sizeOf(context).height;
                                return Stack(
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
                                    // Témoin « REC » : visible même contrôles
                                    // masqués, tant qu'un extrait s'écrit.
                                    const Positioned(
                                      right: OmniaMetrics.space4,
                                      top: OmniaMetrics.space4,
                                      child: RecordingIndicator(),
                                    ),
                                    // Bornée à la scène : étroite, la barre de
                                    // recherche se resserre au lieu de sortir.
                                    if (isDocument && findVisible && search != null)
                                      Positioned(
                                        left: OmniaMetrics.space4,
                                        right: OmniaMetrics.space4,
                                        top: OmniaMetrics.space4,
                                        child: Align(
                                          alignment: Alignment.topRight,
                                          child: FindBar(search: search),
                                        ),
                                      ),
                                    // La languette : le panneau replié, au bord
                                    // gauche de la scène.
                                    if (!panelVisible)
                                      const Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Center(child: PanelEdgeTab()),
                                      ),
                                    Positioned(
                                      left: OmniaMetrics.space4,
                                      top: OmniaMetrics.space4,
                                      right: OmniaMetrics.space4,
                                      bottom: OmniaMetrics.controlBarClearance(stageHeight),
                                      child: const Align(
                                        alignment: Alignment.bottomRight,
                                        child: ToolPanelHost(),
                                      ),
                                    ),
                                    // Invite de reprise, au-dessus des contrôles ;
                                    // sans taille quand il n'y a rien à proposer.
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: OmniaMetrics.resumePromptBottomFor(stageHeight),
                                      child: const Center(child: ResumePrompt()),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: IgnorePointer(
                                        ignoring: !chromeVisible,
                                        // Pointeur sur la barre : elle reste
                                        // affichée tant qu'on s'en sert.
                                        child: MouseRegion(
                                          onEnter: (_) => _chrome.hold(_barHold),
                                          onExit: (_) => _chrome.release(_barHold),
                                          child: AnimatedOpacity(
                                            opacity: chromeVisible ? 1 : 0,
                                            duration: OmniaMotion.reveal,
                                            curve: chromeVisible
                                                ? OmniaMotion.revealCurve
                                                : OmniaMotion.concealCurve,
                                            child: AnimatedSlide(
                                              offset: chromeVisible
                                                  ? Offset.zero
                                                  : const Offset(0, 0.12),
                                              duration: OmniaMotion.reveal,
                                              curve: OmniaMotion.revealCurve,
                                              child: RepaintBoundary(
                                                child: isDocument
                                                    ? const DocumentBar()
                                                    : (isImage
                                                        ? const ImageBar()
                                                        : const ControlBar()),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Le tiroir et son voile par-dessus tout le
                                    // reste : c'est lui qu'on manipule.
                                    if (showDrawer) ...[
                                      Positioned.fill(
                                        child: GestureDetector(
                                          key: const ValueKey('panel-drawer-scrim'),
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () =>
                                              ref.dispatch(const SetSidePanelVisible(false)),
                                          child: ColoredBox(color: colors.overlayScrim),
                                        ),
                                      ),
                                      const Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: RepaintBoundary(
                                          child: SidePanel(drawer: true),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
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
        ),
      ),
    );

    // Le voile de dépôt couvre toute la fenêtre, panneau compris.
    return _resizable(
      _dropZone(
        Stack(
          fit: StackFit.expand,
          children: [content, const HelpOverlay(), const SettingsOverlay()],
        ),
      ),
      enabled: !fullscreen,
    );
  }

  /// Sous Linux, masquer la barre de titre retire aussi les bordures de
  /// redimensionnement de GTK : OMNIA doit les fournir lui-même, sans quoi la
  /// fenêtre ne peut plus être redimensionnée à la souris — mini-lecteur
  /// compris, qui n'a pas de barre de titre non plus.
  ///
  /// Toujours le même widget, plein écran ou non (bords simplement
  /// désactivés) : changer de type démonterait tout l'écran, vidéo comprise.
  Widget _resizable(Widget child, {required bool enabled}) {
    if (!needsCustomResizeEdges) return child;
    return DragToResizeArea(
      resizeEdgeSize: 8,
      enableResizeEdges: enabled ? null : const [],
      child: child,
    );
  }

}
