import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/omnia_colors.dart';

/// Peint le logo officiel d'OMNIA en pur dessin vectoriel (CustomPainter).
///
/// Même géométrie que linux/dev.omnia.omnia.svg et tool/make_icon.py :
/// Le moniteur au contour blanc chaud avec son faisceau de projection ambre,
/// et devant lui le smartphone ambre avec son bouton lecture.
class OmniaLogoWidget extends StatelessWidget {
  const OmniaLogoWidget({
    super.key,
    this.size = 96.0,
    this.showGlow = true,
  });

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<OmniaColors>() ?? OmniaColors.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: colors.projector.withValues(alpha: 0.35),
                  blurRadius: size * 0.35,
                  spreadRadius: size * 0.04,
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: OmniaLogoPainter(colors: colors),
      ),
    );
  }
}

class OmniaLogoPainter extends CustomPainter {
  const OmniaLogoPainter({required this.colors});
  final OmniaColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 256.0; // Échelle relative au canevas 256x256

    // Fond arrondi de l'icône (Velours)
    final bgRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(56 * s),
    );
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF211A26),
          colors.velvet,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRRect(bgRRect, bgPaint);

    // 1. Moniteur (Écran et contour)
    final monRect = Rect.fromLTWH(28 * s, 50 * s, 172 * s, 118 * s);
    final monRRect = RRect.fromRectAndRadius(monRect, Radius.circular(16 * s));
    canvas.drawRRect(monRRect, Paint()..color = colors.curtain);

    final monStroke = Paint()
      ..color = colors.screen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * s;
    canvas.drawRRect(monRRect, monStroke);

    // Pied du moniteur
    final neckPath = Path()
      ..moveTo(100 * s, 168 * s)
      ..lineTo(128 * s, 168 * s)
      ..lineTo(134 * s, 196 * s)
      ..lineTo(94 * s, 196 * s)
      ..close();
    canvas.drawPath(neckPath, Paint()..color = colors.screen);

    // Socle du moniteur
    final baseRect = Rect.fromLTWH(76 * s, 194 * s, 76 * s, 9 * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, Radius.circular(4.5 * s)),
      Paint()..color = colors.screen,
    );

    // 2. Faisceau du projecteur sur l'écran
    final beamPath = Path()
      ..moveTo(62 * s, 110 * s)
      ..lineTo(158 * s, 76 * s)
      ..lineTo(158 * s, 144 * s)
      ..close();
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          colors.projector.withValues(alpha: 0.95),
          colors.projector.withValues(alpha: 0.08),
        ],
      ).createShader(Rect.fromLTWH(62 * s, 76 * s, 96 * s, 68 * s));
    canvas.drawPath(beamPath, beamPaint);

    // Lampe du faisceau
    canvas.drawCircle(Offset(62 * s, 110 * s), 10 * s, Paint()..color = colors.screen);

    // 3. Téléphone smartphone au premier plan
    final phoneRect = Rect.fromLTWH(160 * s, 100 * s, 66 * s, 116 * s);
    final phoneRRect = RRect.fromRectAndRadius(phoneRect, Radius.circular(16 * s));
    canvas.drawRRect(phoneRRect, Paint()..color = colors.projector);

    // Contour velours pour détacher le téléphone
    canvas.drawRRect(
      phoneRRect,
      Paint()
        ..color = colors.velvet
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9 * s,
    );

    // Écran du téléphone
    final pScreenRect = Rect.fromLTWH(171 * s, 116 * s, 44 * s, 70 * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pScreenRect, Radius.circular(6 * s)),
      Paint()..color = colors.velvet,
    );

    // Bouton de lecture (Triangle Play ambre)
    final playPath = Path()
      ..moveTo(186 * s, 137 * s)
      ..lineTo(204 * s, 151 * s)
      ..lineTo(186 * s, 165 * s)
      ..close();
    canvas.drawPath(playPath, Paint()..color = colors.projector);

    // Barre d'accueil du téléphone
    final barRect = Rect.fromLTWH(186 * s, 195 * s, 14 * s, 5 * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(2.5 * s)),
      Paint()..color = colors.velvet,
    );

    // 4. Ondes sans fil (OMNIA Connect)
    final wave1 = Paint()
      ..color = colors.projector
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7 * s;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(180 * s, 76 * s), radius: 24 * s),
      -math.pi / 4,
      math.pi / 2,
      false,
      wave1,
    );

    final wave2 = Paint()
      ..color = colors.projector.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7 * s;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(180 * s, 70 * s), radius: 38 * s),
      -math.pi / 4,
      math.pi / 2,
      false,
      wave2,
    );
  }

  @override
  bool shouldRepaint(covariant OmniaLogoPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
