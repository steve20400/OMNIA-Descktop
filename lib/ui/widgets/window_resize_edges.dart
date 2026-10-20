import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/utils/platform_session.dart';

/// Demande au système de redimensionner la fenêtre par un de ses bords,
/// injectable.
///
/// Même exception documentée à la règle d'or que [startWindowDragProvider] :
/// redimensionner une fenêtre n'est pas une commande de lecture, et le système
/// garde la main du geste tant que le bouton reste enfoncé. Le fournisseur
/// donne la couture qui permet de relever l'appel sans fenêtre native.
final startWindowResizeProvider = Provider<void Function(ResizeEdge)>(
  (ref) => windowManager.startResizing,
);

/// Bords de redimensionnement dessinés par OMNIA.
///
/// Sous Linux, masquer la barre de titre retire toutes les décorations GTK, y
/// compris les bords de redimensionnement : sans ces bandes, la fenêtre ne
/// peut plus être redimensionnée à la souris.
///
/// Et non `DragToResizeArea` de window_manager, dont les bandes sont posées
/// par-dessus toute l'application avec un [MouseRegion] **opaque** : tout clic
/// à moins de huit pixels d'un bord de la fenêtre s'arrêtait là et n'arrivait
/// jamais à la commande qui se trouve dessous — la languette du panneau (14 px
/// de large collée au bord gauche, soit plus de la moitié perdue) et les
/// boutons de la barre de titre (34 px de haut dans une barre de 40, donc à
/// trois pixels du bord haut). D'où les clics qu'il fallait répéter. Ici les
/// bandes sont translucides au test de pointeur : le curseur change au bord,
/// mais le clic continue sa route.
///
/// Le geste est confié au système par un simple [Listener] après trois pixels
/// parcourus, et non par un détecteur de « pan » : celui-ci doit d'abord
/// gagner l'arène des gestes, et son `DragGestureRecognizer` reste bloqué en
/// état « accepté » quand le relâchement se perd — même raisonnement que pour
/// [WindowDragArea], qui déplace la fenêtre.
class WindowResizeEdges extends StatelessWidget {
  const WindowResizeEdges({
    super.key,
    required this.child,
    this.enabled = true,
    this.force,
  });

  final Widget child;

  /// Bords actifs. En plein écran il n'y a rien à redimensionner, mais le
  /// widget reste en place : en changer démonterait tout l'écran.
  final bool enabled;

  /// Force la présence des bandes quelle que soit la plateforme. Réservé aux
  /// tests : en vrai, seul Linux en a besoin.
  final bool? force;

  /// Épaisseur des bandes, en pixels logiques.
  static const double thickness = 8;

  /// Distance à parcourir, bouton enfoncé, avant de confier le geste au
  /// système : assez pour ne pas confondre un clic un peu tremblant avec un
  /// redimensionnement, assez peu pour que la fenêtre suive tout de suite.
  static const double threshold = 3;

  @override
  Widget build(BuildContext context) {
    if (!(force ?? needsCustomResizeEdges)) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (enabled)
          const Positioned.fill(
            child: Column(
              children: [
                Row(
                  children: [
                    _Edge(ResizeEdge.topLeft, SystemMouseCursors.resizeUpLeft,
                        width: thickness, height: thickness),
                    Expanded(
                      child: _Edge(ResizeEdge.top, SystemMouseCursors.resizeUp,
                          height: thickness),
                    ),
                    _Edge(ResizeEdge.topRight, SystemMouseCursors.resizeUpRight,
                        width: thickness, height: thickness),
                  ],
                ),
                Expanded(
                  child: Row(
                    children: [
                      _Edge(ResizeEdge.left, SystemMouseCursors.resizeLeft, width: thickness),
                      // Le centre ne doit rien intercepter : une boîte sans
                      // enfant ne répond pas au test de pointeur.
                      Expanded(child: SizedBox.expand()),
                      _Edge(ResizeEdge.right, SystemMouseCursors.resizeRight, width: thickness),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _Edge(ResizeEdge.bottomLeft, SystemMouseCursors.resizeDownLeft,
                        width: thickness, height: thickness),
                    Expanded(
                      child: _Edge(ResizeEdge.bottom, SystemMouseCursors.resizeDown,
                          height: thickness),
                    ),
                    _Edge(ResizeEdge.bottomRight, SystemMouseCursors.resizeDownRight,
                        width: thickness, height: thickness),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Une bande : elle montre le curseur du bord et confie le geste au système,
/// sans jamais retenir un clic.
class _Edge extends ConsumerStatefulWidget {
  const _Edge(this.edge, this.cursor, {this.width, this.height});

  final ResizeEdge edge;
  final MouseCursor cursor;
  final double? width;
  final double? height;

  @override
  ConsumerState<_Edge> createState() => _EdgeState();
}

class _EdgeState extends ConsumerState<_Edge> {
  /// Point de la pression en cours ; `null` s'il n'y en a pas, ou si le
  /// redimensionnement est déjà parti.
  Offset? _origin;

  void _onPointerDown(PointerDownEvent event) {
    // Réarmé sans condition : si le relâchement précédent s'est perdu (le
    // système garde la souris pendant qu'il redimensionne), la pression
    // suivante repart quand même.
    _origin = event.buttons == kPrimaryButton ? event.position : null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _origin;
    if (origin == null) return;
    // Bouton relâché entre-temps : plus rien à redimensionner.
    if ((event.buttons & kPrimaryButton) == 0) {
      _origin = null;
      return;
    }
    if ((event.position - origin).distance < WindowResizeEdges.threshold) return;
    // Un seul départ par pression : le système mène la suite du geste.
    _origin = null;
    ref.read(startWindowResizeProvider)(widget.edge);
  }

  void _onPointerFinished(PointerEvent event) => _origin = null;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: MouseRegion(
        cursor: widget.cursor,
        // Translucide, et non exclusive : au bord de la fenêtre le curseur
        // devient celui du redimensionnement, mais le clic ET le survol
        // continuent vers la commande qui se trouve dessous — elle s'allume
        // encore sous le pointeur.
        hitTestBehavior: HitTestBehavior.translucent,
        opaque: false,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerFinished,
          onPointerCancel: _onPointerFinished,
        ),
      ),
    );
  }
}
