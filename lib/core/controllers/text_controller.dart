import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../commands/player_command.dart';
import '../models/app_preferences.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_status.dart';
import '../utils/os_errors.dart';
import '../utils/text_encoding.dart';
import 'media_controller.dart';

/// Un fichier texte chargé, prêt à être affiché.
class TextDocument {
  const TextDocument({
    required this.path,
    required this.text,
    required this.isMarkdown,
    required this.encoding,
  });

  final String path;
  final String text;

  /// `.md` / `.markdown` : rendu Markdown ; sinon texte brut.
  final bool isMarkdown;

  /// Encodage détecté, pour information.
  final String encoding;

  int get lineCount => text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
}

/// Contrôleur des fichiers texte (`.txt`, `.md`, `.log`).
///
/// Lecture seule : il charge le fichier, devine son encodage et publie le
/// document pour la vue. Le zoom est ici une échelle de police ; le défilement
/// est mémorisé en fraction (0–1), la vue étant seule à connaître ses pixels.
class TextController implements MediaController {
  TextController({AppPreferences Function()? preferences})
      : _preferences = preferences ?? (() => AppPreferences.defaults);

  /// Taille de texte préférée, appliquée à chaque ouverture. Elle suit le
  /// dernier réglage de l'utilisateur (le service de lecture la met à jour).
  final AppPreferences Function() _preferences;

  /// Bornes de l'échelle de police.
  static const double minScale = 0.6;
  static const double maxScale = 3.0;

  /// Au-delà, le fichier est tronqué à l'affichage : un journal de plusieurs
  /// centaines de mégaoctets n'a pas à être rendu d'un bloc.
  static const int maxBytes = 32 * 1024 * 1024;

  final StreamController<TextDocument?> _documents =
      StreamController<TextDocument?>.broadcast();

  TextDocument? _document;
  PlaybackStateSink? _sink;

  /// Document courant, `null` si rien n'est ouvert.
  TextDocument? get document => _document;

  /// Émet à chaque ouverture / fermeture.
  Stream<TextDocument?> get documents => _documents.stream;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.text};

  void _publish(TextDocument? doc) {
    _document = doc;
    if (!_documents.isClosed) _documents.add(doc);
  }

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    sink.update(
      (st) => st.copyWith(
        file: file,
        status: PlaybackStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        hasVideo: false,
        currentPage: 0,
        totalPages: 0,
        scrollFraction: 0,
        zoom: _clampScale(_preferences().textScale),
        clearError: true,
      ),
    );

    try {
      final ioFile = File(file.path);
      final length = await ioFile.length();
      final Uint8List bytes = length > maxBytes
          ? await _readPrefix(ioFile, maxBytes)
          : await ioFile.readAsBytes();
      final decoded = decodeText(bytes);
      final ext = p.extension(file.path).toLowerCase();

      _publish(
        TextDocument(
          path: file.path,
          text: normaliseLineEndings(decoded.text),
          isMarkdown: ext == '.md' || ext == '.markdown',
          encoding: decoded.encoding,
        ),
      );
      sink.update((st) => st.copyWith(status: PlaybackStatus.playing));
    } on FileSystemException catch (e) {
      _publish(null);
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(classifyFileSystemError(e), detail: e.message),
        ),
      );
    } on Object catch (e) {
      _publish(null);
      sink.update(
        (st) => st.copyWith(
          status: PlaybackStatus.error,
          error: PlaybackError(PlaybackErrorCode.decodeFailed, detail: e.toString()),
        ),
      );
    }
  }

  static Future<Uint8List> _readPrefix(File file, int count) async {
    final raf = await file.open();
    try {
      return await raf.read(count);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<bool> handle(PlayerCommand command) async {
    final sink = _sink;
    if (sink == null || _document == null) return false;

    switch (command) {
      case ZoomRelative(:final factor):
        sink.update((st) => st.copyWith(zoom: _clampScale(st.zoom * factor)));
      case SetZoom(:final zoom):
        sink.update((st) => st.copyWith(zoom: _clampScale(zoom)));
      case FitZoom():
        // Pour un texte, « ajuster » revient à la taille de police normale.
        sink.update((st) => st.copyWith(zoom: 1.0));
      case ToggleReadingDarkMode():
        sink.update((st) => st.copyWith(readingDark: !st.readingDark));
      case ScrollTo(:final fraction):
        sink.update((st) => st.copyWith(scrollFraction: fraction.clamp(0.0, 1.0)));
      default:
        return false;
    }
    return true;
  }

  static double _clampScale(double value) => value.clamp(minScale, maxScale);

  @override
  Future<void> close() async {
    _publish(null);
    _sink?.update(
      (st) => st.copyWith(
        clearFile: true,
        status: PlaybackStatus.idle,
        scrollFraction: 0,
        clearError: true,
      ),
    );
    _sink = null;
  }

  @override
  Future<void> dispose() async {
    await _documents.close();
  }
}
