import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/playback_status.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import '../shortcuts/shortcut_handler.dart';
import '../theme/omnia_theme.dart';
import '../widgets/control_bar.dart';
import '../widgets/stage.dart';
import '../widgets/title_bar.dart';

/// Écran unique d'OMNIA : barre de titre, scène, contrôles flottants.
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
      final args = ref.read(launchArgumentsProvider);
      final path = args.where((a) => !a.startsWith('-')).firstOrNull;
      if (path == null) return;
      final entity = FileSystemEntity.typeSync(path);
      final command = switch (entity) {
        FileSystemEntityType.directory => OpenFolder(path),
        FileSystemEntityType.file => OpenFile(path),
        _ => null,
      };
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

  // --- Molette : volume ----------------------------------------------------

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!ref.read(playbackStateProvider).mediaType.isAv) return;
    final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
    ref.dispatch(VolumeRelative(delta));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playbackStateProvider);

    ref.listen<bool>(playbackStateProvider.select((s) => s.fullscreen), (_, fullscreen) {
      if (fullscreen) {
        _armIdleTimer();
      } else {
        _idleTimer?.cancel();
        if (!_chromeVisible) setState(() => _chromeVisible = true);
      }
    });

    final hideCursor = state.fullscreen && !_chromeVisible;
    final canToggleByClick = state.hasFile && state.status != PlaybackStatus.error && state.mediaType.isAv;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (_, event) => handleShortcut(event, ref),
        child: MouseRegion(
          cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
          onHover: (_) => _revealChrome(),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerDown: (_) {
              _focusNode.requestFocus();
              _revealChrome();
            },
            child: ColoredBox(
              color: colors.velvet,
              child: Column(
                children: [
                  if (!state.fullscreen) const TitleBar(),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: canToggleByClick ? () => ref.dispatch(const TogglePlay()) : null,
                          onDoubleTap: state.hasFile ? () => ref.dispatch(const ToggleFullscreen()) : null,
                          child: const Stage(),
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
                              curve: _chromeVisible ? OmniaMotion.revealCurve : OmniaMotion.concealCurve,
                              child: AnimatedSlide(
                                offset: _chromeVisible ? Offset.zero : const Offset(0, 0.12),
                                duration: OmniaMotion.reveal,
                                curve: OmniaMotion.revealCurve,
                                child: const ControlBar(),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
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
                                child: Center(
                                  child: Text(l10n.dropToPlay, style: type.viewTitle),
                                ),
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
      ),
    );
  }
}
