import 'package:path/path.dart' as p;

import '../models/media_type.dart';
import 'media_controller.dart';

/// Associe une extension de fichier à un [MediaType], et un type à son
/// [MediaController].
///
/// Les listes d'extensions sont la source de vérité pour tout OMNIA : dialogue
/// d'ouverture, scan de dossier, associations MIME du fichier `.desktop`.
class MediaRouter {
  MediaRouter(Iterable<MediaController> controllers)
      : _controllers = List.unmodifiable(controllers);

  final List<MediaController> _controllers;

  static const Set<String> videoExtensions = {
    'mp4', 'mkv', 'avi', 'webm', 'mov', 'flv', 'wmv', 'ts', 'm2ts', 'mts',
    'm4v', '3gp', 'mpg', 'mpeg', 'vob', 'ogv', 'divx', 'rm', 'rmvb', 'asf',
  };

  static const Set<String> audioExtensions = {
    'mp3', 'flac', 'wav', 'ogg', 'oga', 'aac', 'm4a', 'opus', 'wma', 'aiff',
    'aif', 'ape', 'ac3', 'dts', 'mka', 'wv', 'amr',
  };

  static const Set<String> pdfExtensions = {'pdf'};

  static const Set<String> textExtensions = {'txt', 'md', 'markdown', 'log'};

  /// Toutes les extensions lisibles, sans le point.
  static Set<String> get allExtensions => {
        ...videoExtensions,
        ...audioExtensions,
        ...pdfExtensions,
        ...textExtensions,
      };

  /// Type déduit de l'extension (insensible à la casse).
  static MediaType typeForPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (ext.isEmpty) return MediaType.unknown;
    if (videoExtensions.contains(ext)) return MediaType.video;
    if (audioExtensions.contains(ext)) return MediaType.audio;
    if (pdfExtensions.contains(ext)) return MediaType.pdf;
    if (textExtensions.contains(ext)) return MediaType.text;
    return MediaType.unknown;
  }

  static bool isSupported(String path) => typeForPath(path).isSupported;

  /// Contrôleur capable d'ouvrir [type], ou `null`.
  MediaController? controllerFor(MediaType type) {
    for (final c in _controllers) {
      if (c.supportedTypes.contains(type)) return c;
    }
    return null;
  }

  /// Contrôleur pour un chemin donné, ou `null` si non pris en charge.
  MediaController? controllerForPath(String path) =>
      controllerFor(typeForPath(path));

  Iterable<MediaController> get controllers => _controllers;
}
