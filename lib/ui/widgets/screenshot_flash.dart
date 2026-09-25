import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../theme/omnia_theme.dart';

/// Éclair de capture : la scène blanchit un instant quand une image vient
/// d'être enregistrée, comme l'obturateur d'un appareil photo.
///
/// Le message à l'écran dit où le fichier est allé ; l'éclair, lui, se voit
/// sans être lu. Il part du chemin de la dernière capture : chaque fichier
/// écrit porte un nom différent, donc chaque capture déclenche le sien.
class ScreenshotFlash extends ConsumerStatefulWidget {
  const ScreenshotFlash({super.key});

  /// Montée franche, retour doux : on retient le déclic, pas le voile.
  static const Duration duration = Duration(milliseconds: 280);

  @override
  ConsumerState<ScreenshotFlash> createState() => _ScreenshotFlashState();
}

class _ScreenshotFlashState extends ConsumerState<ScreenshotFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ScreenshotFlash.duration,
  );

  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 0, end: 0.7).chain(CurveTween(curve: Curves.easeOut)),
      weight: 22,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.7, end: 0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 78,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Une capture de plus : le chemin change à chaque fichier écrit. On écoute
    // plutôt que d'observer, pour ne rien reconstruire entre deux captures.
    ref.listen<String?>(
      playbackStateProvider.select((state) => state.lastScreenshot),
      (previous, next) {
        if (next == null || next == previous) return;
        _controller.forward(from: 0);
      },
    );

    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: ColoredBox(color: context.colors.screen),
      ),
    );
  }
}
