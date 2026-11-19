import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/controllers/media_router.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../../core/services/local_storage.dart';
import '../../core/services/video_frame_grabber.dart';
import '../theme/omnia_theme.dart';

/// Vrai sous `flutter test` : ni libmpv ni pdfium n'y sont chargés, et
/// aucune affiche ne doit tenter de les ouvrir.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

/// Les affiches se dessinent-elles ? Faux sous les tests d'interface, qui
/// montrent alors l'affiche vierge de chaque type.
final hallArtworkEnabledProvider = Provider<bool>((_) => !_underTest);

/// L'extracteur d'images des vidéos, et son cache sur disque.
final videoFrameGrabberProvider = Provider<VideoFrameGrabber>(
  (ref) => VideoFrameGrabber(
    enabled: ref.watch(hallArtworkEnabledProvider),
    cacheDirectory: () async {
      try {
        return Directory(p.join((await localStorageDirectory()).path, 'affiches'));
      } on Object {
        return null;
      }
    },
  ),
);

/// L'image d'une vidéo, tant qu'une affiche la montre. Quand aucune ne la
/// montre plus — on a fait défiler un long dossier —, l'extraction qui
/// n'avait pas commencé est abandonnée.
final _videoFrameProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, path) {
  final grabber = ref.read(videoFrameGrabberProvider);
  ref.onDispose(() => grabber.cancel(path));
  return grabber.frameOf(path);
});

/// La pochette d'un son, tant qu'une affiche la montre : un dossier de
/// milliers de titres ne les garde pas toutes en mémoire.
final _audioCoverProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, path) async {
  try {
    final tags = await ref.read(audioMetadataServiceProvider).read(path);
    return tags?.cover;
  } on Object {
    return null;
  }
});

/// Le document ouvert pour en montrer la première page ; refermé dès
/// qu'aucune affiche ne le montre plus.
final _pdfDocumentProvider =
    FutureProvider.autoDispose.family<PdfDocument?, String>((ref, path) async {
  var disposed = false;
  PdfDocument? document;
  ref.onDispose(() {
    disposed = true;
    final open = document;
    if (open != null) unawaited(open.dispose());
  });
  final PdfDocument opened;
  try {
    opened = await PdfDocument.openFile(path);
  } on Object {
    return null;
  }
  document = opened;
  if (disposed) {
    // Plus personne ne le regarde : refermé aussitôt ouvert.
    unawaited(opened.dispose());
    return null;
  }
  return opened;
});

/// L'image d'un média : image de la vidéo, pochette du son, première page
/// du PDF, la photo elle-même. À défaut, l'affiche vierge de son type.
class HallArtwork extends ConsumerWidget {
  const HallArtwork({
    super.key,
    required this.path,
    required this.exists,
    this.fit = BoxFit.cover,
    this.showExtension = true,
  });

  final String path;

  /// Faux pour un fichier déplacé ou supprimé : rien à lire.
  final bool exists;
  final BoxFit fit;

  /// L'extension en coin de l'affiche vierge ; trop petite pour la porter,
  /// une vignette de liste s'en passe.
  final bool showExtension;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = MediaRouter.typeForPath(path);
    final blank = HallBlankPoster(type: type, extension: showExtension ? p.extension(path) : '');
    if (!exists || !ref.watch(hallArtworkEnabledProvider)) return blank;

    Widget fromBytes(AsyncValue<Uint8List?> value) => switch (value) {
          AsyncData(value: final bytes?) => Image.memory(
              bytes,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => blank,
            ),
          _ => blank,
        };

    return switch (type) {
      MediaType.image => Image(
          image: ResizeImage(FileImage(File(path)), width: 720),
          fit: fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => blank,
        ),
      MediaType.video => fromBytes(ref.watch(_videoFrameProvider(path))),
      MediaType.audio => fromBytes(ref.watch(_audioCoverProvider(path))),
      MediaType.pdf => switch (ref.watch(_pdfDocumentProvider(path))) {
          AsyncData(value: final document?) => _FirstPage(document: document, blank: blank),
          _ => blank,
        },
      _ => blank,
    };
  }
}

/// La première page d'un PDF, calée sur toute la largeur et coupée en bas :
/// c'est le haut de la page — titre, en-tête — qui le fait reconnaître.
class _FirstPage extends StatelessWidget {
  const _FirstPage({required this.document, required this.blank});

  final PdfDocument document;
  final Widget blank;

  @override
  Widget build(BuildContext context) {
    if (document.pages.isEmpty) return blank;
    final page = document.pages.first;
    final ratio = page.height > 0 ? page.height / page.width : 1.414;
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: SizedBox(
                width: width,
                height: width * ratio,
                child: PdfPageView(
                  document: document,
                  pageNumber: 1,
                  maximumDpi: 72,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// L'affiche d'un média qui n'a pas d'image : le signe de son type, en
/// grand et en retrait, et son extension en petites capitales.
class HallBlankPoster extends StatelessWidget {
  const HallBlankPoster({super.key, required this.type, this.extension = ''});

  final MediaType type;
  final String extension;

  static IconData iconFor(MediaType type) => switch (type) {
        MediaType.video => Icons.movie_outlined,
        MediaType.audio => Icons.album_outlined,
        MediaType.pdf => Icons.picture_as_pdf_outlined,
        MediaType.text || MediaType.doc => Icons.description_outlined,
        MediaType.image => Icons.image_outlined,
        MediaType.unknown => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.type;
    final label = extension.replaceFirst('.', '').toUpperCase();
    return ColoredBox(
      color: colors.curtain,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: FractionallySizedBox(
              heightFactor: 0.42,
              child: FittedBox(
                child: Icon(iconFor(type), color: colors.dust.withValues(alpha: 0.45)),
              ),
            ),
          ),
          if (label.isNotEmpty)
            Positioned(
              right: OmniaMetrics.space2,
              top: OmniaMetrics.space2,
              child: Text(
                label,
                style: typography.timecode.copyWith(color: colors.dust, fontSize: 10, letterSpacing: 1.2),
              ),
            ),
        ],
      ),
    );
  }
}

/// La couleur d'un média, tirée de son image : le fond du hall prend sa
/// teinte, comme l'accueil d'une console prend celle du jeu sélectionné.
///
/// `null` quand il n'y a pas d'image, ou sous les tests d'interface.
final hallTintProvider = FutureProvider.autoDispose.family<Color?, String>((ref, path) async {
  if (!ref.watch(hallArtworkEnabledProvider)) return null;
  try {
    switch (MediaRouter.typeForPath(path)) {
      case MediaType.video:
        final bytes = await ref.watch(_videoFrameProvider(path).future);
        return bytes == null ? null : tintFromEncoded(bytes);
      case MediaType.audio:
        final bytes = await ref.watch(_audioCoverProvider(path).future);
        return bytes == null ? null : tintFromEncoded(bytes);
      case MediaType.image:
        return tintFromEncoded(await File(path).readAsBytes());
      case MediaType.pdf:
        final document = await ref.watch(_pdfDocumentProvider(path).future);
        if (document == null || document.pages.isEmpty) return null;
        final image = await document.pages.first.render(
          fullWidth: 24,
          fullHeight: 34,
          width: 24,
          height: 34,
          backgroundColor: 0xFFFFFFFF,
        );
        if (image == null) return null;
        try {
          return tintFromPixels(image.pixels, bgra: true);
        } finally {
          image.dispose();
        }
      case MediaType.text || MediaType.doc || MediaType.unknown:
        return null;
    }
  } on Object {
    return null;
  }
});

/// La teinte d'une image encodée (JPEG, PNG…), décodée en tout petit.
Future<Color?> tintFromEncoded(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    return tintFromPixels(data.buffer.asUint8List(), bgra: false);
  } on Object {
    return null;
  }
}

/// La couleur dominante de [pixels] — RGBA, ou BGRA si [bgra] — où les
/// teintes vives pèsent plus que les gris : un ciel bleu l'emporte sur le
/// bitume, une pochette rouge sur son fond noir.
Color? tintFromPixels(Uint8List pixels, {required bool bgra}) {
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var weight = 0.0;
  for (var i = 0; i + 3 < pixels.length; i += 4) {
    final r = bgra ? pixels[i + 2] : pixels[i];
    final g = pixels[i + 1];
    final b = bgra ? pixels[i] : pixels[i + 2];
    final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
    final w = 0.05 + hsv.saturation * hsv.value;
    red += r * w;
    green += g * w;
    blue += b * w;
    weight += w;
  }
  if (weight == 0) return null;
  return Color.fromARGB(
    255,
    (red / weight).round().clamp(0, 255),
    (green / weight).round().clamp(0, 255),
    (blue / weight).round().clamp(0, 255),
  );
}
