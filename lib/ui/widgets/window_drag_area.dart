import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Démarre le déplacement de la fenêtre par le système, injectable.
///
/// Exception documentée à la règle d'or : déplacer une fenêtre n'est pas une
/// commande de lecture, et le système garde la main du geste tant que le
/// bouton reste enfoncé — un aller-retour par le bus ne ferait que retarder
/// sa prise en main. Le fournisseur donne quand même la couture qui manquait :
/// les tests relèvent l'appel sans fenêtre native, et la télécommande passera
/// par là le jour où elle déplacera la fenêtre.
final startWindowDragProvider = Provider<VoidCallback>(
  (ref) => windowManager.startDragging,
);

/// Zone qui déplace la fenêtre : on appuie, on bouge, le système prend la main.
///
/// Un simple [Listener], et non un détecteur de « pan » comme
/// `DragToMoveArea`. Un détecteur doit d'abord gagner l'arène des gestes, et
/// surtout son `DragGestureRecognizer` reste bloqué en état « accepté » quand
/// le relâchement se perd — ce qui arrive à chaque déplacement sous Windows,
/// où la boucle de déplacement du système avale le bouton relâché. Le
/// glissement suivant n'appelle alors plus rien (`_checkDrag` sort tout de
/// suite quand l'état est déjà « accepté »), et la fenêtre ne se déplace plus
/// jamais alors que clic et double-clic continuent de marcher. Ici, chaque
/// pression repart de zéro : rien ne peut rester coincé.
///
/// Elle se place SOUS les commandes : dans une pile, ce qui est au-dessus est
/// testé d'abord, donc une pression sur un bouton ne lui parvient pas et ne
/// déplace pas la fenêtre.
class WindowDragArea extends ConsumerStatefulWidget {
  const WindowDragArea({super.key, this.child, this.onDragStart});

  final Widget? child;

  /// Prévenu au départ du glissement : ce qui entoure la zone peut alors
  /// oublier le clic en cours, un déplacement n'en étant pas un.
  final VoidCallback? onDragStart;

  /// Distance à parcourir, bouton enfoncé, avant de confier le geste au
  /// système : assez pour ne pas confondre un clic un peu tremblant avec un
  /// glissement, assez peu pour que la fenêtre parte tout de suite.
  static const double threshold = 3;

  @override
  ConsumerState<WindowDragArea> createState() => _WindowDragAreaState();
}

class _WindowDragAreaState extends ConsumerState<WindowDragArea> {
  /// Point de la pression en cours ; `null` s'il n'y en a pas, ou si le
  /// glissement est déjà parti.
  Offset? _origin;

  void _onPointerDown(PointerDownEvent event) {
    // Réarmé sans condition : si le relâchement précédent s'est perdu (le
    // système garde la souris pendant qu'il déplace la fenêtre), la pression
    // suivante repart quand même.
    _origin = event.buttons == kPrimaryButton ? event.position : null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final origin = _origin;
    if (origin == null) return;
    // Bouton relâché entre-temps : plus rien à déplacer.
    if ((event.buttons & kPrimaryButton) == 0) {
      _origin = null;
      return;
    }
    if ((event.position - origin).distance < WindowDragArea.threshold) return;
    // Un seul départ par pression : le système mène la suite du geste.
    _origin = null;
    widget.onDragStart?.call();
    ref.read(startWindowDragProvider)();
  }

  void _onPointerFinished(PointerEvent event) => _origin = null;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Translucide : la zone reçoit la pression même là où rien n'est dessiné
      // sous elle, sans rien retirer à ce qui l'entoure.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerFinished,
      onPointerCancel: _onPointerFinished,
      child: widget.child,
    );
  }
}
