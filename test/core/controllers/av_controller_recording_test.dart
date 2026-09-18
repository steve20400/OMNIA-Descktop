/// Test d'intégration : le vrai libmpv écrit-il vraiment un extrait ?
///
/// Les tests du service travaillent avec un faux enregistreur : ils vérifient
/// la logique, jamais que mpv sait écrire un fichier. Celui-ci ouvre un son
/// d'essai avec le moteur réel et exige un fichier non vide à l'arrivée. Il
/// tombe bruyamment si l'enregistrement cesse de fonctionner.
///
/// Il n'est joué que quand `OMNIA_LIBMPV_TEST=1` : ailleurs (poste de
/// développement, machine de CI sans libmpv), il est explicitement passé, et
/// jamais silencieusement réussi. La CI le lance sous Linux (paquet
/// `libmpv-dev`) et sous Windows (la bibliothèque déposée par la compilation).
///
/// Aucune sortie vidéo n'est créée : elle exige le moteur Flutter et ses
/// canaux de plateforme, absents du banc de test.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:omnia/core/controllers/av_controller.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:path/path.dart' as p;

/// Variable d'environnement qui autorise le test à parler au moteur réel.
const _enabledVariable = 'OMNIA_LIBMPV_TEST';

final bool _enabled = Platform.environment[_enabledVariable] == '1';

/// Puits d'état minimal : les contrôleurs ne possèdent pas l'état.
class _MemorySink implements PlaybackStateSink {
  PlaybackState _state = const PlaybackState();

  @override
  PlaybackState get state => _state;

  @override
  void update(PlaybackState Function(PlaybackState) reducer) {
    _state = reducer(_state);
  }
}

/// Un son d'essai sans dépendance : 15 s de 440 Hz, PCM 16 bits mono. Le
/// conteneur Matroska de l'extrait accepte le PCM tel quel, sans réencodage.
Uint8List _sineWav({int seconds = 15, int rate = 22050, double frequency = 440}) {
  const headerBytes = 44;
  final samples = seconds * rate;
  final dataBytes = samples * 2;
  final bytes = ByteData(headerBytes + dataBytes);

  void tag(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // taille du bloc de format
  bytes.setUint16(20, 1, Endian.little); // PCM entier
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little); // octets par seconde
  bytes.setUint16(32, 2, Endian.little); // octets par échantillon
  bytes.setUint16(34, 16, Endian.little); // bits par échantillon
  tag(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);

  for (var i = 0; i < samples; i++) {
    final value = (12000 * sin(2 * pi * frequency * i / rate)).round();
    bytes.setInt16(headerBytes + i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Attend que [condition] soit vraie, ou échoue sur le message de [reason].
/// Le message est construit au moment de l'échec : il décrit l'état atteint,
/// et non celui du départ.
Future<void> waitFor(bool Function() condition, String Function() reason,
    {int seconds = 20}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(reason());
}

void main() {
  group('Extrait écrit par le vrai libmpv', () {
    late Directory work;
    late Player player;
    late AvController controller;
    late _MemorySink sink;

    setUp(() async {
      MediaKit.ensureInitialized();
      work = Directory.systemTemp.createTempSync('omnia_libmpv_');
      player = Player(configuration: const PlayerConfiguration(libass: true));
      // Les machines de la CI n'ont pas de sortie audio : sans pilote nul,
      // mpv abandonnerait le fichier au lieu de le lire. Le pilote nul suit le
      // temps réel, donc la lecture avance comme chez l'utilisateur.
      await (player.platform! as NativePlayer).setProperty('ao', 'null');
      controller = AvController(player: player, withVideoOutput: false);
      sink = _MemorySink();
    });

    tearDown(() async {
      await controller.dispose();
      try {
        work.deleteSync(recursive: true);
      } on FileSystemException {
        // Nettoyé par le système.
      }
    });

    test('un extrait de son est écrit, non vide, par le moteur réel', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'extrait.mka');

      await controller.open(MediaFile(path: source.path, type: MediaType.audio), sink);
      await waitFor(
        () => sink.state.status == PlaybackStatus.playing && sink.state.duration > Duration.zero,
        () => 'libmpv n’a pas ouvert le son d’essai : ${sink.state.status.name}'
            ' (${sink.state.error ?? 'sans erreur'}).',
      );

      expect(
        await controller.startRecording(clip),
        isTrue,
        reason: 'mpv n’a pas accepté la propriété d’enregistrement.',
      );

      // Deux secondes de lecture réelle : c'est la matière de l'extrait.
      await waitFor(
        () => sink.state.position >= const Duration(seconds: 2),
        () => 'la lecture n’a pas avancé (position ${sink.state.position}) :'
            ' l’extrait n’aurait aucun contenu.',
      );

      await controller.stopRecording();
      // Même vérification que le service : ce que mpv a écrit au fil de l'eau,
      // puis le repli par son cache. Un fichier local est lu d'avance et tient
      // entier dans le cache : le repli est ici le chemin normal.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      var written = File(clip).existsSync() ? File(clip).lengthSync() : 0;
      if (written == 0) {
        expect(
          await controller.dumpRecording(clip),
          isTrue,
          reason: 'mpv a refusé d’écrire son cache (dump-cache).',
        );
        for (var attempt = 0; attempt < 20; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          written = File(clip).existsSync() ? File(clip).lengthSync() : 0;
          if (written > 32 * 1024) break;
        }
      }

      // Deux secondes de PCM 16 bits à 22 050 Hz font 88 ko : un fichier plus
      // petit que 32 ko ne contient qu'un en-tête de conteneur, donc aucun son.
      expect(
        written,
        greaterThan(32 * 1024),
        reason: 'l’extrait écrit par libmpv est vide ou réduit à son en-tête.',
      );
    });
  }, skip: _enabled ? null : 'Test d’intégration libmpv : $_enabledVariable=1 pour le jouer.');
}
