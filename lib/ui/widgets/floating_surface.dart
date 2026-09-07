import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/omnia_theme.dart';

/// Surface flottante d'OMNIA : rideau translucide, flou d'arrière-plan, coins
/// doux, ombre discrète. Utilisée par la barre de contrôles et les overlays.
class FloatingSurface extends StatelessWidget {
  const FloatingSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = OmniaMetrics.overlayRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: OmniaMetrics.overlayShadowAlpha),
            blurRadius: OmniaMetrics.overlayShadowBlur,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: OmniaMetrics.overlayBlur,
            sigmaY: OmniaMetrics.overlayBlur,
          ),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: colors.overlay,
              borderRadius: borderRadius,
              border: Border.all(color: colors.seam.withValues(alpha: 0.6)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
