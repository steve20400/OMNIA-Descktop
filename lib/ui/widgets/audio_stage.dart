import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/media_file.dart';
import '../../l10n/app_localizations.dart';
import '../audio_tags_provider.dart';
import '../theme/omnia_theme.dart';

/// Vue de lecture audio : pochette en grand, fond dérivé de la pochette
/// (flou profond sous un voile de velours), titre, artiste, album.
///
/// Sans pochette : un vinyle stylisé aux couleurs de la salle. La transition
/// d'une pochette à l'autre est un fondu, jamais un saut.
class AudioStage extends ConsumerWidget {
  const AudioStage({super.key, required this.file});

  final MediaFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final type = context.type;
    final l10n = AppLocalizations.of(context);
    final tags = ref.watch(audioTagsProvider);

    final cover = tags?.hasCover == true ? tags!.cover : null;
    final title = tags?.title ?? file.baseName;
    final artist = tags?.artist;
    final album = tags?.album;
    final subtitle = [artist ?? l10n.unknownArtist, ?album].join('  ·  ');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fond : la pochette, très floutée, sous un voile qui garde la salle
        // sombre et le texte lisible. Rogné : un flou déborde d'environ trois
        // sigma autour de l'image, et passerait sinon sur la barre de titre.
        ClipRect(
          child: AnimatedSwitcher(
            duration: OmniaMotion.stage,
            switchInCurve: OmniaMotion.stageCurve,
            // Pile étirée : par défaut, AnimatedSwitcher centre son enfant sans
            // l'agrandir, et la pochette garderait sa taille naturelle au lieu
            // de couvrir toute la scène.
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, ?current],
            ),
            child: cover == null
                ? ColoredBox(key: const ValueKey('bg-none'), color: colors.velvet)
                : ImageFiltered(
                    key: ValueKey('bg:${file.path}'),
                    imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48, tileMode: TileMode.mirror),
                    child: Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
          ),
        ),
        ColoredBox(color: colors.velvet.withValues(alpha: cover == null ? 0 : 0.72)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(OmniaMetrics.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Cover(cover: cover, keyPath: file.path),
                const SizedBox(height: OmniaMetrics.space5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(
                    title,
                    style: type.viewTitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: OmniaMetrics.space2),
                Text(subtitle, style: type.secondary, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.cover, required this.keyPath});

  final Uint8List? cover;
  final String keyPath;

  static const double size = 260;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedSwitcher(
      duration: OmniaMotion.stage,
      switchInCurve: OmniaMotion.stageCurve,
      switchOutCurve: OmniaMotion.concealCurve,
      child: Container(
        key: ValueKey(cover == null ? 'cover-none' : 'cover:$keyPath'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: OmniaMetrics.overlayRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: cover == null
            ? CustomPaint(painter: _VinylPainter(colors: colors))
            : Image.memory(cover!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// Visuel de repli : un disque, quelques sillons, un reflet ambre.
class _VinylPainter extends CustomPainter {
  const _VinylPainter({required this.colors});

  final OmniaColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.curtain);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.42;
    canvas.drawCircle(center, radius, Paint()..color = colors.velvet);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.seam;
    for (var r = radius * 0.35; r < radius; r += 6) {
      canvas.drawCircle(center, r, groove);
    }
    canvas.drawCircle(center, radius * 0.3, Paint()..color = colors.projector.withValues(alpha: 0.85));
    canvas.drawCircle(center, radius * 0.05, Paint()..color = colors.velvet);
    // Reflet : un arc discret, comme une lampe au-dessus du disque.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.92),
      -2.4,
      1.1,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = colors.screen.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_VinylPainter old) => old.colors != colors;
}
