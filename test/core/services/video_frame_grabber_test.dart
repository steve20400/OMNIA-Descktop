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
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:omnia/core/services/video_frame_grabber.dart';
import 'package:path/path.dart' as p;

final bool _enabled = Platform.environment['OMNIA_LIBMPV_TEST'] == '1';
const String _skipReason = 'OMNIA_LIBMPV_TEST absent : test du moteur réel passé.';

/// Une vidéo d'essai sans dépendance : trois secondes d'AVI en Motion-JPEG,
/// 10 images par seconde, chacune de sa teinte avec un carré qui se déplace.
///
/// AVI et Motion-JPEG plutôt que YUV4MPEG : le libmpv livré sous Windows ne
/// reconnaît pas ce dernier (« Failed to recognize file format »), alors
/// que ces deux-là sont lus partout.
Uint8List _mjpegAvi({int width = 160, int height = 120, int frames = 30}) {
  Uint8List jpegFrame(int f) {
    final frame = img.Image(width: width, height: height);
    img.fill(frame, color: img.ColorRgb8((40 + f * 6) % 256, 90, (200 - f * 4) % 256));
    img.fillRect(
      frame,
      x1: f * 4,
      y1: 30,
      x2: f * 4 + 30,
      y2: 70,
      color: img.ColorRgb8(240, 220, 120),
    );
    return img.encodeJpg(frame, quality: 80);
  }

  final jpegs = [for (var f = 0; f < frames; f++) jpegFrame(f)];
  final largest = jpegs.map((j) => j.length).reduce((a, b) => a > b ? a : b);

  Uint8List le32(List<int> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setUint32(i * 4, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Uint8List le16(List<int> values) {
    final data = ByteData(values.length * 2);
    for (var i = 0; i < values.length; i++) {
      data.setUint16(i * 2, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  List<int> chunk(String id, List<int> body) {
    final out = BytesBuilder(copy: false)
      ..add(id.codeUnits)
      ..add(le32([body.length]))
      ..add(body);
    if (body.length.isOdd) out.addByte(0);
    return out.takeBytes();
  }

  List<int> list(String type, List<int> body) =>
      chunk('LIST', [...type.codeUnits, ...body]);

  final avih = chunk('avih', le32([
    // 10 images par seconde, index présent, une piste.
    100000, 0, 0, 0x10, frames, 0, 1, largest, width, height, 0, 0, 0, 0,
  ]));
  final strh = chunk('strh', [
    ...'vids'.codeUnits,
    ...'MJPG'.codeUnits,
    ...le32([0]),
    ...le16([0, 0]),
    ...le32([0, 1, 10, 0, frames, largest, 0xFFFFFFFF, 0]),
    ...le16([0, 0, width, height]),
  ]);
  final strf = chunk('strf', [
    ...le32([40, width, height]),
    ...le16([1, 24]),
    ...'MJPG'.codeUnits,
    ...le32([width * height * 3, 0, 0, 0, 0]),
  ]);
  final hdrl = list('hdrl', [...avih, ...list('strl', [...strh, ...strf])]);

  final movi = BytesBuilder(copy: false);
  final index = BytesBuilder(copy: false);
  var offset = 4; // Après le mot « movi », comme le veut l'index.
  for (final jpeg in jpegs) {
    final frame = chunk('00dc', jpeg);
    index
      ..add('00dc'.codeUnits)
      ..add(le32([0x10, offset, jpeg.length]));
    movi.add(frame);
    offset += frame.length;
  }
  final body = [
    ...'AVI '.codeUnits,
    ...hdrl,
    ...list('movi', movi.takeBytes()),
    ...chunk('idx1', index.takeBytes()),
  ];
  return Uint8List.fromList(chunk('RIFF', body));
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
    final video = File(p.join(work.path, 'essai.avi'))..writeAsBytesSync(_mjpegAvi());

    // Le journal du moteur accompagne tout échec : c'est lui qui dit si le
    // fichier n'est pas lu, si un filtre manque, ou si la capture échoue.
    final journal = <String>[];
    final bytes = await VideoFrameGrabber.grab(video.path, log: journal);

    expect(
      _isJpeg(bytes),
      isTrue,
      reason: [
        if (bytes == null)
          'aucune image : mpv n’a rien rendu par screenshot-raw sans sortie vidéo'
        else
          '${bytes.length} octets, en-tête ${bytes.take(4).toList()}',
        'journal de mpv :',
        ...journal,
      ].join('\n'),
    );
  }, skip: _enabled ? false : _skipReason);

  test('l’affiche est gardée sur disque, et resservie', () async {
    final video = File(p.join(work.path, 'film.avi'))..writeAsBytesSync(_mjpegAvi());
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

    test('le cache garde les affiches les plus récemment vues, pas plus', () async {
      final cache = Directory(p.join(work.path, 'affiches'))..createSync();
      final base = DateTime(2026, 11, 1);
      for (var i = 0; i < 5; i++) {
        File(p.join(cache.path, 'affiche$i.jpg'))
          ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF])
          ..setLastModifiedSync(base.add(Duration(days: i)));
      }
      File(p.join(cache.path, 'autre.txt')).writeAsStringSync('pas une affiche');

      await VideoFrameGrabber(cacheDirectory: () async => cache).trimCache(keep: 3);

      final restent = cache.listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(restent, ['affiche2.jpg', 'affiche3.jpg', 'affiche4.jpg', 'autre.txt']);
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
