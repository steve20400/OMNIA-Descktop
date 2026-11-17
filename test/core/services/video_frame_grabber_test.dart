/// L'affiche d'une vidéo, tirée par le vrai libmpv.
///
/// L'accueil montre pour chaque film une image tirée du film lui-même. Elle
/// vient d'un lecteur libmpv sans fenêtre (`vo=null`) : rien ne prouve, hors
/// du moteur réel, que mpv sait en rendre une ainsi. Ce test le lui demande
/// sur une vidéo d'essai fabriquée sur place, et exige un JPEG en retour.
///
/// Joué seulement quand `OMNIA_LIBMPV_TEST=1`, comme le test des extraits :
/// ailleurs il est passé, jamais silencieusement réussi.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:omnia/core/services/video_frame_grabber.dart';
import 'package:path/path.dart' as p;

final bool _enabled = Platform.environment['OMNIA_LIBMPV_TEST'] == '1';
const String _skipReason = 'OMNIA_LIBMPV_TEST absent : test du moteur réel passé.';

/// Une vidéo d'essai sans dépendance : trois secondes de YUV4MPEG2, le
/// format brut que FFmpeg lit tel quel. Chaque image a sa propre teinte.
Uint8List _y4m({int width = 160, int height = 120, int frames = 30}) {
  final out = BytesBuilder(copy: false)
    ..add('YUV4MPEG2 W$width H$height F10:1 Ip A1:1 C420jpeg\n'.codeUnits);
  final luma = width * height;
  final chroma = (width ~/ 2) * (height ~/ 2);
  for (var f = 0; f < frames; f++) {
    out.add('FRAME\n'.codeUnits);
    final y = Uint8List(luma);
    for (var i = 0; i < luma; i++) {
      y[i] = (40 + (i % width) + f * 4) & 0xFF;
    }
    out
      ..add(y)
      ..add(Uint8List(chroma)..fillRange(0, chroma, (90 + f * 3) & 0xFF))
      ..add(Uint8List(chroma)..fillRange(0, chroma, (160 - f * 2) & 0xFF));
  }
  return out.takeBytes();
}

bool _isJpeg(Uint8List? bytes) =>
    bytes != null && bytes.length > 100 && bytes[0] == 0xFF && bytes[1] == 0xD8;

void main() {
  late Directory work;

  setUpAll(() {
    if (_enabled) MediaKit.ensureInitialized();
  });

  setUp(() {
    work = Directory.systemTemp.createTempSync('omnia_affiche_');
  });

  tearDown(() {
    try {
      work.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  test('une vidéo donne son affiche, en JPEG', () async {
    final video = File(p.join(work.path, 'essai.y4m'))..writeAsBytesSync(_y4m());

    final bytes = await VideoFrameGrabber.grab(video.path);

    expect(
      _isJpeg(bytes),
      isTrue,
      reason: bytes == null
          ? 'aucune image : mpv n’a rien rendu par screenshot-raw sans sortie vidéo'
          : '${bytes.length} octets, en-tête ${bytes.take(4).toList()}',
    );
  }, skip: _enabled ? false : _skipReason);

  test('l’affiche est gardée sur disque, et resservie', () async {
    final video = File(p.join(work.path, 'film.y4m'))..writeAsBytesSync(_y4m());
    final cache = Directory(p.join(work.path, 'affiches'));
    final grabber = VideoFrameGrabber(cacheDirectory: () async => cache);

    final first = await grabber.frameOf(video.path);
    expect(_isJpeg(first), isTrue);
    final cached = cache.listSync().whereType<File>().toList();
    expect(cached, hasLength(1));
    expect(p.extension(cached.single.path), '.jpg');

    // Un autre extracteur, même cache : l'image est relue, pas recalculée.
    final again = await VideoFrameGrabber(cacheDirectory: () async => cache).frameOf(video.path);
    expect(again, first);
  }, skip: _enabled ? false : _skipReason);

  test('un fichier qui n’est pas une vidéo ne donne rien, sans planter', () async {
    final faux = File(p.join(work.path, 'faux.mkv'))..writeAsStringSync('pas une vidéo');
    final bytes = await VideoFrameGrabber.grab(faux.path, timeout: const Duration(seconds: 4));
    expect(bytes, isNull);
  }, skip: _enabled ? false : _skipReason);

  group('Sans le moteur', () {
    test('désactivé, l’extracteur ne rend rien et n’ouvre rien', () async {
      final grabber = VideoFrameGrabber(enabled: false);
      expect(await grabber.frameOf('/films/inexistant.mkv'), isNull);
    });

    test('un fichier absent ne donne rien', () async {
      final grabber = VideoFrameGrabber(cacheDirectory: () async => null);
      expect(await grabber.frameOf(p.join(work.path, 'absent.mkv')), isNull);
    });

    test('l’empreinte du cache est stable et distingue les fichiers', () {
      final a = VideoFrameGrabber.cacheKey('/films/a.mkv|10|1');
      expect(a, hasLength(16));
      expect(VideoFrameGrabber.cacheKey('/films/a.mkv|10|1'), a);
      expect(VideoFrameGrabber.cacheKey('/films/a.mkv|10|2'), isNot(a));
      expect(VideoFrameGrabber.cacheKey('/films/b.mkv|10|1'), isNot(a));
    });
  });
}
