import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../core/utils/time_format.dart';
import '../theme/omnia_theme.dart';

/// La signature visuelle d'OMNIA : la barre de progression comme faisceau de
/// projecteur (DESIGN.md §5).
///
/// - Le temps écoulé est un trait ambre qui porte un halo.
/// - La tête de lecture est une lampe qui s'allume au survol.
/// - Au survol, la piste s'épaissit et affiche le timecode pointé.
class BeamProgressBar extends StatefulWidget {
  const BeamProgressBar({
    super.key,
    required this.progress,
    required this.duration,
    required this.onSeek,
    this.enabled = true,
  });

  /// Progression 0–1.
  final double progress;

  /// Durée totale, pour le timecode survolé.
  final Duration duration;

  /// Appelé au clic ou pendant un glissement, avec la position visée.
  final ValueChanged<Duration> onSeek;

  final bool enabled;

  @override
  State<BeamProgressBar> createState() => _BeamProgressBarState();
}

class _BeamProgressBarState extends State<BeamProgressBar> {
  bool _hovering = false;
  bool _dragging = false;
  double? _hoverX;

  static const double _labelWidth = 64;

  void _seekAt(double dx, double width) {
    if (!widget.enabled || width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    widget.onSeek(widget.duration * fraction);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final lit = (_hovering || _dragging) && widget.enabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final hoverX = _hoverX?.clamp(0.0, width);
        final hoverDuration =
            hoverX == null || width <= 0 ? null : widget.duration * (hoverX / width);

        return MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (e) => setState(() {
            _hovering = true;
            _hoverX = e.localPosition.dx;
          }),
          onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
          onExit: (_) => setState(() {
            _hovering = false;
            if (!_dragging) _hoverX = null;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seekAt(d.localPosition.dx, width),
            onHorizontalDragStart: (d) {
              setState(() {
                _dragging = true;
                _hoverX = d.localPosition.dx;
              });
              _seekAt(d.localPosition.dx, width);
            },
            onHorizontalDragUpdate: (d) {
              setState(() => _hoverX = d.localPosition.dx);
              _seekAt(d.localPosition.dx, width);
            },
            onHorizontalDragEnd: (_) => setState(() {
              _dragging = false;
              if (!_hovering) _hoverX = null;
            }),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: SizedBox(
              height: OmniaMetrics.beamHitHeight + OmniaMetrics.beamTooltipHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: OmniaMetrics.beamHitHeight,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: lit ? 1 : 0),
                      duration: OmniaMotion.hover,
                      curve: OmniaMotion.hoverCurve,
                      builder: (context, t, _) => CustomPaint(
                        painter: _BeamPainter(
                          progress: widget.enabled ? widget.progress : 0,
                          lit: t,
                          hoverFraction: lit && hoverX != null && width > 0
                              ? hoverX / width
                              : null,
                          colors: colors,
                        ),
                      ),
                    ),
                  ),
                  if (lit && hoverX != null && hoverDuration != null)
                    Positioned(
                      top: 0,
                      left: (hoverX - _labelWidth / 2).clamp(0.0, (width - _labelWidth).clamp(0.0, double.infinity)),
                      width: _labelWidth,
                      height: OmniaMetrics.beamTooltipHeight - 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.curtain,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(OmniaMetrics.radiusSmall),
                          ),
                          border: Border.all(color: colors.seam),
                        ),
                        child: Center(
                          child: Text(
                            formatTimecode(hoverDuration, reference: widget.duration),
                            style: type.timecode.copyWith(fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({
    required this.progress,
    required this.lit,
    required this.hoverFraction,
    required this.colors,
  });

  final double progress;

  /// 0 au repos, 1 survolé (animé).
  final double lit;
  final double? hoverFraction;
  final OmniaColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final thickness = lerpDouble(
      OmniaMetrics.beamRestThickness,
      OmniaMetrics.beamHoverThickness,
      lit,
    )!;
    final cy = size.height / 2;
    final radius = Radius.circular(thickness / 2);

    // Piste : le temps restant, dans l'ombre.
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, cy - thickness / 2, size.width, thickness),
      radius,
    );
    canvas.drawRRect(track, Paint()..color = colors.seam);

    // Aperçu du point survolé : de la lampe jusqu'au curseur, très discret.
    final hx = hoverFraction == null ? null : hoverFraction! * size.width;
    final elapsedW = size.width * progress.clamp(0.0, 1.0);
    if (hx != null && hx > elapsedW) {
      final preview = RRect.fromRectAndRadius(
        Rect.fromLTWH(elapsedW, cy - thickness / 2, hx - elapsedW, thickness),
        radius,
      );
      canvas.drawRRect(preview, Paint()..color = colors.screen.withValues(alpha: 0.18));
    }

    // Faisceau : le temps écoulé, éclairé.
    if (elapsedW > 0) {
      final elapsed = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - thickness / 2, elapsedW, thickness),
        radius,
      );
      final sigma = lerpDouble(
        OmniaMetrics.beamGlowSigmaRest,
        OmniaMetrics.beamGlowSigmaHover,
        lit,
      )!;
      canvas.drawRRect(
        elapsed,
        Paint()
          ..color = colors.projector.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      );
      canvas.drawRRect(elapsed, Paint()..color = colors.projector);
    }

    // Lampe : la tête de lecture.
    final lampR = lerpDouble(
      OmniaMetrics.beamLampRadiusRest,
      OmniaMetrics.beamLampRadiusHover,
      lit,
    )!;
    final lampX = elapsedW.clamp(lampR, (size.width - lampR).clamp(lampR, double.infinity));
    final lamp = Offset(lampX, cy);
    canvas.drawCircle(
      lamp,
      lampR * 2,
      Paint()
        ..color = colors.projector.withValues(alpha: 0.30 + 0.25 * lit)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lampR),
    );
    canvas.drawCircle(lamp, lampR, Paint()..color = colors.screen);

    // Repère du curseur.
    if (hx != null) {
      canvas.drawLine(
        Offset(hx, cy - thickness - 2),
        Offset(hx, cy + thickness + 2),
        Paint()
          ..color = colors.screen.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.progress != progress ||
      old.lit != lit ||
      old.hoverFraction != hoverFraction ||
      old.colors != colors;
}
