import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/media_type.dart';
import '../utils/media_sniffer.dart';
import 'media_controller.dart';

/// Associe une extension de fichier à un [MediaType], et un type à son
/// [MediaController].
///
/// Les listes d'extensions sont la source de vérité pour tout OMNIA : dialogue
/// d'ouverture, scan de dossier, associations MIME du fichier `.desktop`.
/// Un contrôleur créé seulement quand un média de son type s'ouvre.
///
/// Le moteur audio/vidéo est le plus lourd : mpv, ses fils, sa surface de
/// rendu et, sous Linux, son contexte graphique. Une fenêtre qui n'affiche
/// que des documents n'en a pas besoin — et trois fenêtres ouvertes en
/// créaient trois (CHANTIERS S.2).
class LazyMediaController {
  LazyMediaController(this.supportedTypes, this._create);

  final Set<MediaType> supportedTypes;
  final MediaController Function() _create;
  MediaController? _instance;

  /// Le contrôleur, créé au premier appel.
  MediaController get instance => _instance ??= _create();

  /// Vrai une fois le contrôleur créé.
  bool get isCreated => _instance != null;
}

class MediaRouter {
  MediaRouter(Iterable<MediaController> controllers, {Iterable<LazyMediaController> lazy = const []})
      : _controllers = List.unmodifiable(controllers),
        _lazy = List.unmodifiable(lazy);

  final List<MediaController> _controllers;
  final List<LazyMediaController> _lazy;

  /// Vrai si le contrôleur de [type] existe déjà : pour l'arrêter sans le
  /// créer à seule fin de l'arrêter.
  bool isStarted(MediaType type) {
    for (final c in _controllers) {
      if (c.supportedTypes.contains(type)) return true;
    }
    for (final entry in _lazy) {
      if (entry.supportedTypes.contains(type)) return entry.isCreated;
    }
    return false;
  }

  // Vidéo et audio passent par mpv (FFmpeg), qui lit bien plus de formats
  // que le seul MP4 : la liste couvre ce que l'on croise réellement, du
  // fichier de téléphone au disque Blu-ray. Pas de guillemets dans ces
  // commentaires : tool/make_installer_assoc.py lit les chaînes de la liste.
  static const Set<String> videoExtensions = {
    // Conteneurs courants.
    'mp4', 'm4v', 'mkv', 'mk3d', 'webm', 'avi', 'mov', 'qt', 'wmv', 'asf',
    'flv', 'f4v', 'ogv', 'ogm', '3gp', '3g2', 'divx', 'xvid',
    // MPEG : DVD, caméscopes, enregistrements et diffusion TV.
    'mpg', 'mpeg', 'mpe', 'mpv', 'm1v', 'm2v', 'm2p', 'vob', 'evo',
    'ts', 'm2ts', 'mts', 'm2t', 'tp', 'trp', 'tod', 'wtv',
    // Flux bruts et formats professionnels.
    'h264', 'h265', 'hevc', '264', '265', 'ivf', 'y4m', 'dv', 'mxf', 'nut',
    'gxf',
    // Anciens formats.
    'rm', 'rmvb', 'amv', 'bik',
  };

  static const Set<String> audioExtensions = {
    // Formats courants.
    'mp3', 'aac', 'm4a', 'm4b', 'm4r', 'flac', 'wav', 'wave', 'ogg', 'oga',
    'opus', 'wma', 'weba',
    // Sans perte et haute résolution, DSD compris.
    'aiff', 'aif', 'aifc', 'ape', 'wv', 'tta', 'tak', 'w64', 'dsf', 'dff',
    'caf', 'shn', 'ofr',
    // Cinéma, Blu-ray et diffusion.
    'ac3', 'eac3', 'ec3', 'dts', 'dtshd', 'mlp', 'thd', 'truehd', 'mka',
    'mp2', 'mp1', 'mpa', 'adts',
    // Voix et anciens formats.
    'amr', 'awb', 'spx', 'gsm', 'au', 'snd', 'voc', 'ra', 'mpc', 'oma',
  };

  static const Set<String> pdfExtensions = {'pdf'};

  static const Set<String> docExtensions = {
    'docx', 'doc', 'odt', 'rtf', 'dotx', 'docm', 'dotm', 'fodt', 'ott',
    'pptx', 'ppt', 'ppsx', 'odp', 'fodp', 'otp',
  };

  static const Set<String> textExtensions = {
    'txt', 'md', 'markdown', 'log', 'json', 'yaml', 'yml', 'xml', 'csv',
    'tsv', 'ini', 'conf', 'cfg', 'properties', 'toml', 'srt', 'vtt', 'sub',
    'ass', 'lrc', 'sql', 'sh', 'bash', 'bat', 'cmd', 'ps1', 'html', 'htm',
    'css', 'js', 'dart', 'py', 'c', 'cpp', 'h', 'hpp', 'java', 'rs', 'go',
    'aux', 'tex', 'latex', 'bib', 'cls', 'sty', 'toc', 'lof', 'lot', 'bbl',
    'blg', 'idx', 'ilg', 'ind', 'out', 'diff', 'patch', 'env', 'reg', 'inf',
    'lock',
  };

  static const Set<String> imageExtensions = {
    'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'ico', 'svg', 'avif',
    'tif', 'tiff', 'heic', 'heif', 'jfif',
  };

  /// Toutes les extensions lisibles, sans le point.
  static Set<String> get allExtensions => {
        ...videoExtensions,
        ...audioExtensions,
        ...pdfExtensions,
        ...docExtensions,
        ...textExtensions,
        ...imageExtensions,
      };

  /// Type déduit de l'extension (insensible à la casse), ou du flux réseau (OMNIA Connect).
  static MediaType typeForPath(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final uri = Uri.tryParse(path);
      final subPath = uri?.queryParameters['path'] ?? uri?.path ?? '';
      final ext = p.extension(subPath).toLowerCase().replaceFirst('.', '');
      // Un média projeté par OMNIA Connect porte son vrai nom dans le
      // paramètre `path` : s'y fier permet de reconnaître un document ou une
      // image. Tout tenir pour une vidéo les confiait au moteur vidéo, qui les
      // déclarait illisibles.
      if (audioExtensions.contains(ext)) return MediaType.audio;
      if (pdfExtensions.contains(ext)) return MediaType.pdf;
      if (docExtensions.contains(ext)) return MediaType.doc;
      if (imageExtensions.contains(ext)) return MediaType.image;
      if (textExtensions.contains(ext)) return MediaType.text;
      // Une adresse dont on ne sait rien reste une vidéo : c'est le cas d'un
      // flux de diffusion ordinaire, qui n'a pas d'extension.
      return MediaType.video;
    }

    // « film.mp4.part » se lit comme « film.mp4 » : un téléchargement
    // inachevé reste une vidéo.
    final ext = p.extension(withoutPartialSuffix(path)).toLowerCase().replaceFirst('.', '');
    if (ext.isEmpty) return MediaType.unknown;
    if (videoExtensions.contains(ext)) return MediaType.video;
    if (audioExtensions.contains(ext)) return MediaType.audio;
    if (pdfExtensions.contains(ext)) return MediaType.pdf;
    if (docExtensions.contains(ext)) return MediaType.doc;
    if (imageExtensions.contains(ext)) return MediaType.image;
    if (textExtensions.contains(ext)) return MediaType.text;
    return MediaType.unknown;
  }

  static bool isSupported(String path) => typeForPath(path).isSupported;

  /// Le type de [path], en lisant ses premiers octets quand le nom ne dit
  /// rien. Plus lent que [typeForPath] : réservé à l'ouverture d'un fichier,
  /// jamais au parcours d'un dossier.
  static MediaType typeForFile(String path) {
    final byName = typeForPath(path);
    if (byName != MediaType.unknown || path.startsWith('http://') || path.startsWith('https://')) {
      return byName;
    }
    try {
      final file = File(path).openSync();
      try {
        return sniffMediaType(file.readSync(256)) ?? MediaType.unknown;
      } finally {
        file.closeSync();
      }
    } on FileSystemException {
      return MediaType.unknown;
    }
  }

  /// Contrôleur capable d'ouvrir [type], ou `null`.
  MediaController? controllerFor(MediaType type) {
    for (final c in _controllers) {
      if (c.supportedTypes.contains(type)) return c;
    }
    for (final entry in _lazy) {
      if (entry.supportedTypes.contains(type)) return entry.instance;
    }
    return null;
  }

  /// Vrai si un contrôleur sait ouvrir [type], sans le créer.
  bool canOpen(MediaType type) =>
      _controllers.any((c) => c.supportedTypes.contains(type)) ||
      _lazy.any((entry) => entry.supportedTypes.contains(type));

  /// Contrôleur pour un chemin donné, ou `null` si non pris en charge.
  MediaController? controllerForPath(String path) =>
      controllerFor(typeForPath(path));

  /// Les contrôleurs existants ; ceux qui attendent leur premier média n'y
  /// sont pas.
  Iterable<MediaController> get controllers => [
        ..._controllers,
        for (final entry in _lazy)
          if (entry.isCreated) entry.instance,
      ];
}
