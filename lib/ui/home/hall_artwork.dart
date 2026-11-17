import 'dart:async';
import 'dart:io';

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

final _videoFrameProvider = FutureProvider.family<Uint8List?, String>(
  (ref, path) => ref.read(videoFrameGrabberProvider).frameOf(path),
);

final _audioCoverProvider = FutureProvider.family<Uint8List?, String>((ref, path) async {
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
  });

  final String path;

  /// Faux pour un fichier déplacé ou supprimé : rien à lire.
  final bool exists;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = MediaRouter.typeForPath(path);
    final blank = HallBlankPoster(type: type, extension: p.extension(path));
    if (!exists || !ref.watch(hallArtworkEnabledProvider)) return blank;

    Widget fromBytes(AsyncValue<Uint8List?> value) => switch (value) {
          AsyncData(value: final bytes?) => Image.memory(
              bytes,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => blank,
            ),
          _ => blank,
        };

    return switch (type) {
      MediaType.image => Image(
          image: ResizeImage(FileImage(File(path)), width: 720),
          fit: fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => blank,
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
