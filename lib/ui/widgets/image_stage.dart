import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';
import '../../core/models/media_file.dart';
import '../../core/providers.dart';

import '../shortcuts/shortcut_handler.dart';
import '../theme/omnia_theme.dart';

import 'stage_context_menu.dart';

/// La scène d'affichage d'une image fixe (`.png`, `.jpg`, `.webp`, `.svg`, etc.).
///
/// Prise en charge du zoom fluide (molette, raccourcis), du déplacement
/// (pan/drag) et de la rotation à 90°. Un double-clic fait passer de l'image
/// entière à l'image qui remplit tout l'écran, et inversement.
///
/// C'est l'image qui tourne, pas la zone d'affichage : tournée, la zone —
/// qui découpe ce qu'elle contient — devenait une colonne étroite au milieu
/// de l'écran, et même au zoom maximal l'image restait bordée de noir des
/// deux côtés (CHANTIERS R.4). L'image tournée s'ajuste maintenant à l'écran
/// avec ses nouvelles proportions : son grand côté peut en prendre toute la
/// largeur.
class ImageStage extends ConsumerStatefulWidget {
  const ImageStage({super.key, required this.file});

  final MediaFile file;

  @override
  ConsumerState<ImageStage> createState() => _ImageStageState();
}

class _ImageStageState extends ConsumerState<ImageStage> {
  final TransformationController _transform = TransformationController();
  final FocusNode _focus = FocusNode(debugLabel: 'omnia.image');

  /// Dimensions de l'image, connues une fois décodée : le double-clic en a
  /// besoin pour calculer le zoom qui remplit l'écran.
  Size? _imageSize;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
    info.dispose();
    if (mounted) setState(() => _imageSize = size);
  });

  /// Taille de la scène à la dernière mise en page.
  Size _stage = Size.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ImageStage old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      _imageSize = null;
      _resolve();
    }
  }

  void _resolve() {
    final stream = FileImage(File(widget.file.path)).resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _transform.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Le zoom qui fait remplir tout l'écran à l'image, tournée ou non : son
  /// grand côté épouse la largeur, l'excédent se déplace à la souris.
  double? _fillZoom(int quarterTurns) {
    final image = _imageSize;
    if (image == null || image.isEmpty || _stage.isEmpty) return null;
    return imageFillZoom(stage: _stage, image: image, quarterTurns: quarterTurns);
  }

  void _toggleFill(double zoom, int quarterTurns) {
    _transform.value = Matrix4.identity();
    final fill = _fillZoom(quarterTurns);
    if (fill == null || fill <= 1.01 || (zoom - 1).abs() > 0.01) {
      ref.dispatch(const FitZoom(FitMode.page));
    } else {
      ref.dispatch(SetZoom(fill));
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Zoom à la molette avec Ctrl enfoncé, ou zoom direct
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    final factor = dy < 0 ? 1.15 : 0.85;
    ref.dispatch(ZoomRelative(factor));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(playbackStateProvider);
    final quarterTurns = state.rotation;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, event) => handleShortcut(event, ref),
      child: StageContextMenu(
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => _toggleFill(state.zoom, quarterTurns),
            child: Container(
              color: colors.velvet,
              alignment: Alignment.center,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _stage = constraints.biggest;
                  return InteractiveViewer(
                  transformationController: _transform,
                  panEnabled: !state.miniPlayer,
                  minScale: 0.1,
                  maxScale: 10.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: Center(
                    child: Transform.scale(
                      scale: state.zoom,
                      // L'image tourne avant de s'ajuster : RotatedBox échange
                      // largeur et hauteur, et l'ajustement voit les vraies
                      // proportions de l'image tournée.
                      child: AnimatedSwitcher(
                        duration: OmniaMotion.stage,
                        child: RotatedBox(
                          key: ValueKey(quarterTurns),
                          quarterTurns: quarterTurns,
                          child: Image.file(
                        File(widget.file.path),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 64, color: colors.alert),
                            const SizedBox(height: OmniaMetrics.space3),
                            Text(
                              'Format d’image non supporté ou fichier illisible.',
                              style: context.type.body.copyWith(color: colors.dust),
                            ),
                          ],
                        ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le zoom qui fait remplir toute la scène [stage] à une image de taille
/// [image], tournée de [quarterTurns] quarts de tour : son grand côté épouse
/// la largeur ou la hauteur, l'excédent dépasse et se déplace.
double imageFillZoom({required Size stage, required Size image, required int quarterTurns}) {
  final shown = quarterTurns.isOdd ? Size(image.height, image.width) : image;
  // Une image plus petite que l'écran garde sa taille : elle n'est pas
  // agrandie par l'ajustement, seulement par le zoom.
  final contain = math.min(1.0, math.min(stage.width / shown.width, stage.height / shown.height));
  final width = shown.width * contain;
  final height = shown.height * contain;
  return math.max(stage.width / width, stage.height / height);
}
