import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

/// Tire de chaque vidéo une image, sans fenêtre ni son : l'affiche que montre
/// l'accueil.
///
/// Un lecteur libmpv à part, sans sortie vidéo (`vo=null`) : il décode
/// jusqu'à 10 % du film, réduit l'image à 960 pixels de large, et la rend en
/// JPEG par la commande `screenshot-raw` de mpv. Une vidéo à la fois — chaque
/// lecteur ouvre ses propres décodeurs — et chaque image est gardée sur
/// disque : une affiche ne se calcule qu'une fois par fichier.
class VideoFrameGrabber {
  VideoFrameGrabber({
    this.cacheDirectory,
    this.enabled = true,
    this.timeout = const Duration(seconds: 15),
  });

  /// Faux sous les tests d'interface : libmpv n'y est pas chargé, et rien ne
  /// doit tenter de l'ouvrir.
  final bool enabled;

  /// Au-delà, la vidéo est réputée sans image (fichier abîmé, piste vidéo
  /// absente, réseau qui ne répond pas).
  final Duration timeout;

  /// Dossier où les affiches sont gardées ; `null`, aucun cache.
  final Future<Directory?> Function()? cacheDirectory;

  /// Extractions demandées et pas encore commencées. La plus récente passe
  /// en premier : c'est celle qui est à l'écran, quand on fait défiler un
  /// long dossier.
  final List<_Request> _waiting = [];
  bool _working = false;

  /// Affiches déjà rendues, ou en cours : chaque fichier ne se calcule
  /// qu'une fois par session.
  final Map<String, Future<Uint8List?>> _results = {};

  /// L'affiche de [path], ou `null` quand il n'y en a pas.
  Future<Uint8List?> frameOf(String path) {
    if (!enabled) return Future<Uint8List?>.value();
    return _results[path] ??= _load(path);
  }

  /// Renonce à l'affiche de [path] si son extraction n'a pas commencé : la
  /// vignette qui la demandait a quitté l'écran. Elle sera redemandée si
  /// elle y revient.
  void cancel(String path) {
    final index = _waiting.indexWhere((r) => r.path == path);
    if (index < 0) return;
    final request = _waiting.removeAt(index)..cancelled = true;
    request.done.complete(null);
  }

  Future<Uint8List?> _load(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final cached = await _cacheFileFor(file);
    if (cached != null && cached.existsSync()) {
      try {
        final bytes = await cached.readAsBytes();
        // Vue à l'instant : elle passe en tête de celles qu'on garde.
        try {
          cached.setLastModifiedSync(DateTime.now());
        } on FileSystemException {
          // Date inchangée : elle partira un peu plus tôt, voilà tout.
        }
        return bytes;
      } on FileSystemException {
        // Illisible : on la refait.
      }
    }

    final request = _Request(path);
    _waiting.add(request);
    unawaited(_work());
    final bytes = await request.done.future;
    if (request.cancelled) {
      // Pas de résultat à garder : la prochaine demande recommencera.
      _results.remove(path);
      return null;
    }
    if (bytes != null && cached != null) {
      try {
        await cached.parent.create(recursive: true);
        await cached.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // Pas de cache : l'image sera refaite la prochaine fois.
      }
    }
    return bytes;
  }

  /// Une extraction à la fois : chaque lecteur ouvre ses propres décodeurs.
  Future<void> _work() async {
    if (_working) return;
    _working = true;
    try {
      while (_waiting.isNotEmpty) {
        final request = _waiting.removeLast();
        Uint8List? bytes;
        try {
          bytes = await grab(request.path, timeout: timeout);
        } on Object {
          bytes = null;
        }
        request.done.complete(bytes);
      }
    } finally {
      _working = false;
    }
  }

  /// Affiches gardées sur le disque, au plus : environ 60 Mo. Au-delà, les
  /// moins récemment vues partent. Une bibliothèque de milliers de films ne
  /// remplit pas le disque d'images qu'on ne regarde plus.
  static const int maxCachedPosters = 600;

  /// Ramène le cache à [keep] affiches, les plus récemment vues.
  Future<void> trimCache({int keep = maxCachedPosters}) async {
    final directory = await cacheDirectory?.call();
    if (directory == null || !directory.existsSync()) return;
    try {
      final posters = [
        for (final entry in directory.listSync())
          if (entry is File && entry.path.endsWith('.jpg')) (entry, entry.statSync().modified),
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      for (final (file, _) in posters.skip(keep)) {
        try {
          file.deleteSync();
        } on FileSystemException {
          // Lue en ce moment : elle partira la prochaine fois.
        }
      }
    } on FileSystemException {
      // Dossier illisible : rien à faire.
    }
  }

  /// Fichier de cache de [file] : son nom dépend du chemin, de la taille et
  /// de la date de modification, si bien qu'une vidéo remplacée reçoit une
  /// nouvelle affiche.
  Future<File?> _cacheFileFor(File file) async {
    final directory = await cacheDirectory?.call();
    if (directory == null) return null;
    final FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      return null;
    }
    // « 960 » : la largeur de l'image fait partie de la clé ; l'agrandir
    // refait les affiches gardées à l'ancienne taille.
    final key = '${file.absolute.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}|960';
    return File(p.join(directory.path, '${cacheKey(key)}.jpg'));
  }

  /// Empreinte courte et stable de [text] : deux FNV-1a de 32 bits, sur le
  /// texte puis sur le texte retourné.
  static String cacheKey(String text) {
    int fnv(Iterable<int> units) {
      var hash = 0x811C9DC5;
      for (final unit in units) {
        hash ^= unit;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      return hash;
    }

    final forward = fnv(text.codeUnits);
    final backward = fnv(text.codeUnits.reversed);
    return forward.toRadixString(16).padLeft(8, '0') +
        backward.toRadixString(16).padLeft(8, '0');
  }

  /// Réglages du lecteur d'affiches, posés avant l'ouverture du fichier.
  static const Map<String, String> grabberProperties = {
    // media_kit coupe le décodage vidéo tant qu'aucune surface n'est
    // attachée : l'affiche, c'est justement la vidéo.
    'vid': 'auto',
    'aid': 'no',
    'sid': 'no',
    'ao': 'null',
    // Décodage logiciel : l'image reste en mémoire, prête pour la capture.
    'hwdec': 'no',
    // À 10 % : le générique de début est passé, le film a commencé.
    'start': '10%',
    'hr-seek': 'yes',
    'pause': 'yes',
    // Une affiche n'a pas besoin de la 4K : réduite par mpv lui-même,
    // l'image arrive légère et l'encodage JPEG reste bref.
    'vf': 'lavfi=[scale=960:-2]',
  };

  /// Une image de [path], tirée par un lecteur libmpv éphémère.
  ///
  /// Public pour les tests contre le vrai moteur ; l'application passe par
  /// [frameOf], qui met en file et en cache. [log], s'il est fourni, reçoit
  /// le journal du moteur : c'est ce qui dit pourquoi aucune image n'est
  /// venue, sans machine sous la main pour rejouer la scène.
  static Future<Uint8List?> grab(
    String path, {
    Duration timeout = const Duration(seconds: 15),
    List<String>? log,
  }) async {
    final scaled = await _grabWith(path, grabberProperties, timeout, log);
    if (scaled != null) return scaled;
    // Sans la réduction par mpv : un libmpv allégé peut ne pas avoir le
    // filtre de mise à l'échelle, et refuser alors toute la vidéo. L'image
    // arrive plus grande, mais elle arrive.
    log?.add('— nouvel essai sans réduction (vf) —');
    final plain = Map.of(grabberProperties)..remove('vf');
    return _grabWith(path, plain, timeout, log);
  }

  static Future<Uint8List?> _grabWith(
    String path,
    Map<String, String> properties,
    Duration timeout,
    List<String>? log,
  ) async {
    final player = Player(
      configuration: PlayerConfiguration(
        vo: 'null',
        muted: true,
        title: 'OMNIA — affiche',
        logLevel: log == null ? MPVLogLevel.error : MPVLogLevel.warn,
      ),
    );
    final logs = log == null
        ? null
        : player.stream.log.listen((entry) {
            if (log.length < 80) log.add('[${entry.level}] ${entry.prefix} : ${entry.text.trim()}');
          });
    try {
      final platform = player.platform;
      if (platform is! NativePlayer) return null;
      for (final entry in properties.entries) {
        await platform.setProperty(entry.key, entry.value);
      }
      await player.open(Media(path), play: false);

      // L'image arrive quand le décodeur a atteint le point de départ : on
      // la demande à intervalles réguliers, jusqu'au délai.
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final Uint8List? shot;
        try {
          shot = await player.screenshot(format: 'image/jpeg');
        } on Object catch (error) {
          log?.add('capture refusée : $error');
          continue;
        }
        if (shot != null && shot.isNotEmpty) return shot;
      }
      log?.add(
        'aucune image en ${timeout.inSeconds} s ; vidéo ${player.state.width ?? '?'}'
        ' × ${player.state.height ?? '?'}, durée ${player.state.duration}',
      );
      return null;
    } on Object catch (error) {
      log?.add('échec : $error');
      return null;
    } finally {
      await logs?.cancel();
      await player.dispose();
    }
  }
}

class _Request {
  _Request(this.path);

  final String path;
  final Completer<Uint8List?> done = Completer<Uint8List?>();
  bool cancelled = false;
}
