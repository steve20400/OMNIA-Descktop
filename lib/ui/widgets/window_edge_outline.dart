import 'package:flutter/widgets.dart';

import '../theme/omnia_theme.dart';

/// Un trait fin tout autour de la fenêtre.
///
/// OMNIA masque la barre de titre du système : celui-ci ne dessine donc plus
/// aucun bord, et rien ne l'avait remplacé. Deux fenêtres d'OMNIA superposées
/// devenaient indistinctes, et sur un bureau sombre il fallait passer
/// l'application au thème clair pour trouver où l'attraper.
///
/// Le trait est posé **par-dessus** le contenu, et non autour : un cadre qui
/// prend de la place décalerait tout ce qu'il entoure d'un pixel, ce qui se
/// verrait sur une vidéo rendue à sa taille exacte. Il ne capte aucun
/// pointeur : les bandes de redimensionnement passent dessous sans être
/// gênées.
///
/// Rien en plein écran ni dans une fenêtre agrandie : il n'y a plus de bord
/// à montrer, et un trait y mangerait une ligne de l'image.
class WindowEdgeOutline extends StatelessWidget {
  const WindowEdgeOutline({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// Faux en plein écran, où la fenêtre n'a plus de bord.
  final bool enabled;

  /// Épaisseur du trait, en pixels logiques.
  static const double thickness = 1;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: context.colors.windowEdge,
                  width: thickness,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
