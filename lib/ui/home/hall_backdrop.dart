import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/app_preferences.dart';
import '../recent_files.dart';
import '../theme/omnia_theme.dart';
import 'hall_artwork.dart';

/// La couleur d'ambiance du hall, tirée de la teinte d'un média et réglée
/// pour le thème : profonde en sombre, claire et douce en clair.
///
/// Une image sans couleur franche — une page blanche, un film en noir et
/// blanc — prend celle du projecteur : un fond gris ne dirait rien.
Color hallAmbient(Color? tint, OmniaColors colors, {required bool dark}) {
  final source = HSLColor.fromColor(tint ?? colors.projector);
  final base = source.saturation < 0.12 ? HSLColor.fromColor(colors.projector) : source;
  return dark
      ? base.withSaturation(base.saturation.clamp(0.35, 0.8)).withLightness(0.3).toColor()
      : base.withSaturation(base.saturation.clamp(0.3, 0.7)).withLightness(0.83).toColor();
}

/// Le fond du hall.
///
/// - **Aperçu** : l'image nette du média sélectionné occupe le côté droit,
///   fondue vers la gauche dans un dégradé de ses propres couleurs — le texte
///   vit sur le dégradé, l'image reste lisible.
/// - **Affiche** : la même image, floutée, sur toute la fenêtre.
/// - **Image** : une image choisie par l'utilisateur, sur toute la fenêtre.
/// - **Uni** : le fond du thème seul.
///
/// Sans média sélectionné, Aperçu et Affiche montrent un dégradé de la
/// couleur du projecteur : le hall n'est jamais un aplat terne.
class HallBackdrop extends ConsumerWidget {
  const HallBackdrop({
    super.key,
    required this.mode,
    required this.wallpaper,
    required this.selected,
  });

  final HallBackground mode;
  final String wallpaper;
  final RecentFile? selected;

  /// Les couches qui se remplacent remplissent toute la fenêtre. La mise en
  /// page par défaut de l'animation les laissait à leur taille naturelle :
  /// une image de 480 pixels restait au milieu de l'écran, et le fond ne
  /// changeait qu'à peine.
  static Widget _fill(Widget? current, List<Widget> previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final recent = selected;
    final path = recent != null && recent.exists ? recent.path : null;
    final tinted = mode == HallBackground.preview || mode == HallBackground.artwork;
    final tint = tinted && path != null ? ref.watch(hallTintProvider(path)).valueOrNull : null;
    final ambient = hallAmbient(tint, colors, dark: dark);

    final Widget? image = switch (mode) {
      HallBackground.plain => null,
      HallBackground.wallpaper => wallpaper.isEmpty
          ? null
          : Image.file(
              File(wallpaper),
              key: ValueKey('fond:$wallpaper'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
      HallBackground.artwork => path == null
          ? null
          : Opacity(
              key: ValueKey('affiche:$path'),
              opacity: dark ? 0.85 : 0.7,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.decal),
                child: Transform.scale(
                  scale: 1.08,
                  child: HallArtwork(path: path, exists: true),
                ),
              ),
            ),
      HallBackground.preview => path == null
          ? null
          : _PreviewImage(key: ValueKey('aperçu:$path'), path: path),
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.velvet),
        if (tinted)
          // La couleur glisse d'un média à l'autre au lieu de sauter.
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: ambient),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, color, _) => _AmbientGradient(
              color: color ?? ambient,
              velvet: colors.velvet,
              dark: dark,
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: OmniaMotion.stageCurve,
          switchOutCurve: OmniaMotion.concealCurve,
          layoutBuilder: _fill,
          child: image ?? const SizedBox.shrink(key: ValueKey('sans-image')),
        ),
        ..._legibility(colors.velvet, dark: dark),
      ],
    );
  }

  /// Les voiles qui gardent le texte lisible, quel que soit le fond : sous
  /// la barre de titre en haut, sous la bande d'affiches en bas, et à gauche
  /// là où se lit la séance. En clair, ils sont plus légers : un voile de
  /// papier épais effaçait l'image.
  List<Widget> _legibility(Color velvet, {required bool dark}) {
    final covering = mode == HallBackground.artwork || mode == HallBackground.wallpaper;
    final strong = dark ? 1.0 : 0.85;
    return [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              velvet.withValues(alpha: 0.95 * strong),
              velvet.withValues(alpha: (covering ? 0.55 : 0.25) * strong),
              velvet.withValues(alpha: 0),
            ],
            stops: const [0, 0.42, 0.75],
          ),
        ),
      ),
      if (covering)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [velvet.withValues(alpha: 0.72 * strong), velvet.withValues(alpha: 0)],
              stops: const [0, 0.62],
            ),
          ),
        ),
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: 140,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [velvet.withValues(alpha: 0.6 * strong), velvet.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    ];
  }
}

/// Le dégradé d'ambiance : la couleur du média, forte en haut à droite où
/// se tient l'image, qui s'éteint vers le fond du thème.
class _AmbientGradient extends StatelessWidget {
  const _AmbientGradient({required this.color, required this.velvet, required this.dark});

  final Color color;
  final Color velvet;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.6, -0.45),
              radius: 1.35,
              colors: [
                color.withValues(alpha: dark ? 0.95 : 0.9),
                color.withValues(alpha: dark ? 0.38 : 0.45),
                velvet.withValues(alpha: 0),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
        // Un second foyer, plus discret, en bas à gauche : le dégradé a de
        // la profondeur au lieu d'être une simple tache.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.9, 1.0),
              radius: 1.1,
              colors: [
                color.withValues(alpha: dark ? 0.35 : 0.3),
                velvet.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// L'aperçu net du média, posé à droite et fondu dans le dégradé : vers la
/// gauche, où se lit la séance, et vers le bas, où passe la bande.
class _PreviewImage extends StatelessWidget {
  const _PreviewImage({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: FractionallySizedBox(
        widthFactor: 0.66,
        heightFactor: 0.82,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.transparent, Colors.black],
            stops: [0, 0.5],
          ).createShader(bounds),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.transparent, Colors.black],
              stops: [0, 0.4],
            ).createShader(bounds),
            child: HallArtwork(path: path, exists: true),
          ),
        ),
      ),
    );
  }
}
