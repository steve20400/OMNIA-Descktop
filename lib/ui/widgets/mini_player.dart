import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/media_type.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../../core/utils/time_format.dart';
import '../../l10n/app_localizations.dart';
import '../audio_tags_provider.dart';
import '../chrome_controller.dart';
import '../shortcuts/default_keymap.dart';
import '../shortcuts/shortcut_handler.dart';
import '../shortcuts/shortcut_labels.dart';
import '../theme/omnia_theme.dart';
import '../wheel_steps.dart';
import 'beam_progress_bar.dart';
import 'omnia_icon_button.dart';
import 'stage.dart';
import 'stage_context_menu.dart';
import 'window_drag_area.dart';

/// Mini-lecteur : la fenêtre compacte au premier plan.
///
/// Avec une image, c'est un vrai lecteur vidéo (façon VLC) : la vidéo occupe
/// toute la fenêtre, les commandes se posent dessus et s'effacent comme
/// ailleurs. Sans image, un bandeau : pochette, titre, faisceau et transport.
///
/// Toute la surface déplace la fenêtre, sauf les commandes elles-mêmes ; le
/// double-clic revient à la fenêtre entière (et n'agrandit surtout pas,
/// contrairement à `DragToMoveArea`).
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

  @override
  void dispose() {
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

  /// Vrai si la pression en cours a déplacé la fenêtre : elle ne compte alors
  /// plus comme un clic. Le relâchement se perd d'ordinaire dans la boucle de
  /// déplacement du système, mais un petit glissement peut le rendre — sans
  /// cela, bouger la fenêtre de trois pixels arrêterait la lecture.
  bool _windowDragged = false;

  void _markWindowDragged() => _windowDragged = true;

  /// Clic : lecture/pause. Double-clic : retour à la fenêtre entière.
  ///
  /// Le glissement est confié à [WindowDragArea], posée sous le contenu : un
  /// détecteur de gestes ne convient pas pour lui (voir sa documentation), et
  /// l'arène suffit ici à laisser la priorité aux boutons — un clic sur une
  /// commande ne relance pas la lecture par-dessus le marché.
  Widget _windowGestures({required Widget child, required bool hasMedia}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_windowDragged) return;
        _focus.requestFocus();
        if (hasMedia) ref.dispatch(const TogglePlay());
      },
      onDoubleTap: () {
        if (_windowDragged) return;
        ref.dispatch(const ToggleMiniPlayer());
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(playbackStateProvider);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) => handleShortcut(event, ref),
      child: MouseRegion(
        onHover: (_) => _chrome.activity(),
        onExit: (_) => _chrome.pointerLeft(),
        child: Listener(
          onPointerDown: (_) {
            // Chaque pression repart d'un clic, jusqu'à preuve du contraire.
            _windowDragged = false;
            _chrome.activity();
          },
          onPointerMove: (_) => _chrome.activity(),
          onPointerSignal: _onPointerSignal,
          child: ColoredBox(
            color: colors.velvet,
            child: state.hasVideo ? _video(state) : _audioStrip(context, state),
          ),
        ),
      ),
    );
  }

  // --- Avec image : la vidéo occupe toute la fenêtre -----------------------

  Widget _video(PlaybackState state) {
    final surface = ref.watch(videoSurfaceProvider);
    final hasMedia = state.hasFile && state.mediaType.isAv;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Le menu contextuel enveloppe l'image : vitesse, sous-titres et le
        // reste restent atteignables au clic droit, même tout petit.
        StageContextMenu(
          child: _windowGestures(
            hasMedia: hasMedia,
            // L'image entière, sans barre de titre ni marge. La zone de
            // déplacement la couvre : rien d'atteignable là-dessous, et les
            // commandes sont au-dessus dans la pile, donc testées avant elle.
            child: WindowDragArea(
              onDragStart: _markWindowDragged,
              child: surface(context, fit: BoxFit.contain, aspectRatio: null),
            ),
          ),
        ),
        // Les commandes par-dessus : elles s'effacent avec le reste des
        // contrôles, et ne captent plus rien une fois masquées.
        _MiniOverlay(state: state),
      ],
    );
  }

  // --- Sans image : le bandeau --------------------------------------------

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
        // Le bandeau descend jusqu'à 300 × 96 : tout s'y resserre plutôt que
        // de déborder. Les marges cèdent en premier, puis la ligne d'artiste.
        final inset = constraints.maxHeight < 110 ? OmniaMetrics.space2 : OmniaMetrics.space3;
        final inner = math.max(0.0, constraints.maxHeight - 2 * inset);
        final compact = inner < 92;
        final coverSide = math.min(inner, 100.0);
        // Faisceau et boutons ont une hauteur fixe : on la borne à une part de
        // la place disponible, pour que le titre garde toujours la sienne.
        final beamHeight = math.min(inner * 0.3, compact ? 18.0 : 26.0);
        final rowHeight = math.min(inner * 0.45, compact ? 28.0 : 34.0);
        final columnWidth = math.max(
          0.0,
          constraints.maxWidth - 2 * inset - coverSide - OmniaMetrics.space3,
        );
        // Les boutons suivent la rangée, sans jamais devenir minuscules : la
        // rangée les rogne d'elle-même s'il le faut.
        final buttonSize = math.max(18.0, rowHeight - 4);
        final buttonIcon = math.max(10.0, buttonSize - 8);

        final strip = Padding(
          padding: EdgeInsets.all(inset),
          child: Row(
            children: [
              // Décor : rien à y cliquer. Hors d'atteinte du pointeur, la
              // pochette laisse passer la pression jusqu'à la zone de
              // déplacement posée dessous — on saisit la fenêtre par elle.
              IgnorePointer(
                child: ClipRRect(
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
              ),
              const SizedBox(width: OmniaMetrics.space3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Titre et artiste : du texte, pas des commandes. Sourds
                    // au pointeur, ils laissent saisir la fenêtre par eux.
                    Flexible(
                      child: IgnorePointer(
                        child: Text(
                          title,
                          style: type.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (!compact)
                      Flexible(
                        child: IgnorePointer(
                          child: Text(
                            subtitle,
                            style: type.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
        );

        return _windowGestures(
          hasMedia: false,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // La zone de déplacement d'abord : la pile teste ses enfants du
              // dernier au premier, donc le faisceau et les boutons passent
              // avant elle. Partout ailleurs — pochette, titre, marges — la
              // pression lui arrive et déplace la fenêtre.
              Positioned.fill(child: WindowDragArea(onDragStart: _markWindowDragged)),
              strip,
            ],
          ),
        );
      },
    );
  }
}

/// Les commandes posées sur l'image du mini-lecteur.
///
/// Elles suivent exactement la barre de contrôles de l'écran principal :
/// fondu avec le reste des contrôles, et hors d'atteinte du pointeur une fois
/// effacées. Ce qui ne tient plus disparaît, du moins utile au plus utile.
class _MiniOverlay extends ConsumerWidget {
  const _MiniOverlay({required this.state});

  final PlaybackState state;

  /// Hauteur du dégradé qui détache les commandes d'une image claire.
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
                // Deux voiles dégradés : les icônes restent lisibles sur une
                // image claire, sans masquer le film pour autant.
                _shade(colors, top: true),
                _shade(colors, top: false),
                Positioned(
                  top: OmniaMetrics.space1,
                  right: OmniaMetrics.space1,
                  child: _plate(
                    colors,
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
                          // Molette sur le faisceau : on cherche un passage,
                          // pas le volume — comme sur la barre de contrôles.
                          onScrollSeek: (direction) =>
                              ref.dispatch(SeekRelative(seekStep * direction.toDouble())),
                        ),
                      ),
                      if (showTime) ...[
                        const SizedBox(width: OmniaMetrics.space2),
                        // Le temps se lit, ne se clique pas : sourd au
                        // pointeur, il laisse saisir la fenêtre par lui.
                        IgnorePointer(
                          child: Text(
                            formatTimecode(state.position, reference: state.duration),
                            style: type.timecode.copyWith(color: colors.screen),
                          ),
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

  /// Voile dégradé sous les commandes.
  ///
  /// Un [DecoratedBox] sans enfant ne prend aucune pression (il n'a rien à
  /// tester, et ne se teste pas lui-même) : c'est essentiel, c'est là que se
  /// trouve le pointeur quand les commandes sont affichées, et la pression
  /// doit traverser jusqu'à la zone de déplacement posée sous l'image. Y
  /// mettre un `ColoredBox` ou un enfant condamnerait le déplacement.
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

  /// Plaque discrète sous un groupe de commandes, pour les détacher de l'image.
  Widget _plate(OmniaColors colors, Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: colors.velvet.withValues(alpha: 0.45),
          borderRadius: OmniaMetrics.controlRadius,
        ),
        child: child,
      );
}
