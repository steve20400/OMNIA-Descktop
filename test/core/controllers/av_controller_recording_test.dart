/// Test d'intégration : le vrai libmpv écrit-il vraiment un extrait ?
///
/// Les tests du service travaillent avec un faux enregistreur : ils vérifient
/// la logique, jamais que mpv sait écrire un fichier. Celui-ci pilote le moteur
/// réel sur des médias d'essai et exige un fichier non vide à l'arrivée. Il
/// tombe bruyamment si l'enregistrement cesse de fonctionner.
///
/// Il vérifie aussi l'autre moitié de la promesse : quand mpv ne *peut* pas
/// écrire (conteneur qui refuse les pistes, dossier inaccessible, rien qui
/// défile), OMNIA doit le dire au lieu d'allumer un voyant. Un extrait annoncé
/// et absent est le pire des deux.
///
/// Chaque échec est accompagné de ce que mpv rapporte : état du cache,
/// position, taille du fichier au fil du temps et journal du moteur. Une CI
/// rouge doit dire POURQUOI, sans machine locale pour rejouer la scène.
///
/// Il n'est joué que quand `OMNIA_LIBMPV_TEST=1` : ailleurs (poste de
/// développement, machine de CI sans libmpv), il est explicitement passé, et
/// jamais silencieusement réussi. La CI le lance sous Linux (paquet
/// `libmpv-dev`) et sous Windows (la bibliothèque déposée par la compilation).
///
/// Aucune sortie vidéo n'est créée : elle exige le moteur Flutter et ses
/// canaux de plateforme, absents du banc de test.
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
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
import 'package:omnia/core/models/recording_failure.dart';
import 'package:path/path.dart' as p;

/// Variable d'environnement qui autorise le test à parler au moteur réel.
const _enabledVariable = 'OMNIA_LIBMPV_TEST';

final bool _enabled = Platform.environment[_enabledVariable] == '1';

/// En dessous, un fichier d'extrait ne contient qu'un en-tête de conteneur :
/// même seuil que le service de lecture.
const int _headerOnlyBytes = 4096;

/// Caractéristiques du son d'essai : elles servent à prévoir la taille de
/// l'extrait, donc à vérifier qu'il contient bien la séquence demandée — et
/// rien d'autre.
const int _wavSeconds = 15;
const int _wavRate = 22050;
const int _wavBytesPerSecond = _wavRate * 2;

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

/// Ce qu'un extrait a donné : la réponse du moteur, les octets obtenus, et de
/// combien la lecture a avancé pendant ce temps.
typedef ClipResult = ({RecordingFailure failure, int written, Duration advanced});

/// Un son d'essai sans dépendance : 15 s de 440 Hz, PCM 16 bits mono. Le
/// conteneur Matroska de l'extrait accepte le PCM tel quel, sans réencodage.
Uint8List _sineWav({
  int seconds = _wavSeconds,
  int rate = _wavRate,
  double frequency = 440,
}) {
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

/// Une vidéo d'essai sans dépendance : des images YUV brutes au format
/// YUV4MPEG2, que libavformat sait lire tel quel.
///
/// Elle sert au cas *refusé* : Matroska n'accepte pas la vidéo non compressée
/// sans code de format, et mpv recopie les paquets sans les réencoder. C'est
/// donc un média qui joue très bien et dont l'extrait est peut-être impossible
/// — exactement ce qu'OMNIA doit annoncer au lieu de laisser un fichier vide.
Uint8List _rawVideoY4m({
  int width = 160,
  int height = 120,
  int fps = 10,
  int seconds = 12,
}) {
  final luma = width * height;
  final chroma = (width ~/ 2) * (height ~/ 2);
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('YUV4MPEG2 W$width H$height F$fps:1 Ip A1:1 C420mpeg2\n'));
  for (var frame = 0; frame < fps * seconds; frame++) {
    out.add(ascii.encode('FRAME\n'));
    final y = Uint8List(luma);
    for (var i = 0; i < luma; i++) {
      // Un dégradé qui se déplace : de vraies différences d'une image à
      // l'autre, pour que rien ne puisse être « optimisé » en silence.
      y[i] = (i ~/ width + i % width + frame * 3) & 0xFF;
    }
    out
      ..add(y)
      ..add(Uint8List(chroma)..fillRange(0, chroma, 128))
      ..add(Uint8List(chroma)..fillRange(0, chroma, 128));
  }
  return out.takeBytes();
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

/// Taille de [path], ou 0 s'il n'existe pas.
int _sizeOf(String path) {
  final file = File(path);
  return file.existsSync() ? file.lengthSync() : 0;
}

void main() {
  group('Extrait écrit par le vrai libmpv', () {
    late Directory work;
    late Player player;
    late AvController controller;
    late _MemorySink sink;

    /// Déroulé de l'extrait, ligne à ligne : joint à tout échec.
    final trace = <String>[];

    setUp(() async {
      MediaKit.ensureInitialized();
      trace.clear();
      work = Directory.systemTemp.createTempSync('omnia_libmpv_');
      player = Player(
        // Journal du moteur jusqu'aux avertissements : c'est là que mpv dit
        // pourquoi il refuse d'écrire, et le test doit pouvoir le répéter.
        configuration: const PlayerConfiguration(libass: true, logLevel: MPVLogLevel.warn),
      );
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

    /// Tout ce qu'il faut pour comprendre un échec sans machine locale.
    Future<String> report(String title, String clip) async {
      final around = work
          .listSync()
          .map((e) => '${p.basename(e.path)} (${_sizeOf(e.path)} o)')
          .join(', ');
      return [
        title,
        'état : ${sink.state.status.name}'
            ' ; position ${sink.state.position}'
            ' ; durée ${sink.state.duration}'
            ' ; erreur ${sink.state.error ?? 'aucune'}',
        if (clip.isEmpty)
          'extrait attendu : aucun (ce test ne demande pas d’extrait)'
        else
          'extrait attendu : $clip (${_sizeOf(clip)} octets)',
        'contenu du dossier de travail : ${around.isEmpty ? '(vide)' : around}',
        if (trace.isNotEmpty) 'déroulé :',
        for (final line in trace) '  $line',
        await controller.recordingDiagnostics(),
      ].join('\n');
    }

    /// Ouvre [file] et n'en revient que lorsque le moteur décode vraiment : la
    /// position qui bouge est la seule preuve, et la durée n'en est pas une
    /// (des images brutes n'en annoncent pas toujours).
    Future<void> openAndPlay(MediaFile file) async {
      await controller.open(file, sink);
      await waitFor(
        () =>
            sink.state.status == PlaybackStatus.playing && sink.state.position > Duration.zero,
        () => 'libmpv n’a pas lu ${p.basename(file.path)} :'
            ' ${sink.state.status.name}, position ${sink.state.position}'
            ' (${sink.state.error ?? 'sans erreur'}).',
      );
      trace.add('lecture commencée : position ${sink.state.position},'
          ' durée ${sink.state.duration}');
    }

    /// Enchaîne exactement ce que fait le service de lecture : démarrage
    /// prouvé, lecture, arrêt, mesure, écriture depuis le cache, mesure, puis
    /// restitution des réglages du moteur.
    Future<ClipResult> recordClip(String clip, {required Duration play}) async {
      final asked = DateTime.now();
      final failure = await controller.startRecording(clip);
      trace.add('startRecording → ${failure.name}'
          ' en ${DateTime.now().difference(asked).inMilliseconds} ms');
      if (failure != RecordingFailure.none) {
        await controller.releaseRecording();
        return (failure: failure, written: 0, advanced: Duration.zero);
      }

      final from = sink.state.position;
      final until = DateTime.now().add(play);
      while (DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        trace.add('position ${sink.state.position} : ${_sizeOf(clip)} octets');
      }
      final advanced = sink.state.position - from;

      await controller.stopRecording();
      var written = _sizeOf(clip);
      trace.add('après stopRecording : $written octets'
          ' (aucune écriture au fil de l’eau n’est attendue pour un fichier local)');
      if (written <= _headerOnlyBytes) {
        final dumped = await controller.dumpRecording(clip);
        written = _sizeOf(clip);
        trace.add('après dumpRecording (rendu $dumped) : $written octets');
      }
      await controller.releaseRecording();
      return (failure: failure, written: written, advanced: advanced);
    }

    test('un extrait de son est écrit, non vide, par le moteur réel', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'extrait.mka');

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));
      final result = await recordClip(clip, play: const Duration(seconds: 2));

      expect(
        result.failure,
        RecordingFailure.none,
        reason: await report('Le moteur a refusé de commencer l’extrait.', clip),
      );
      // Un extrait suit la lecture : sans lecture, le reste n'a aucun sens.
      expect(
        result.advanced,
        greaterThan(const Duration(seconds: 1)),
        reason: await report(
          'La lecture n’a pas avancé pendant l’extrait : il n’aurait aucun contenu.',
          clip,
        ),
      );
      // Deux secondes de PCM 16 bits à 22 050 Hz font 88 ko : un fichier plus
      // petit que 32 ko ne contient qu'un en-tête de conteneur, donc aucun son.
      expect(
        result.written,
        greaterThan(32 * 1024),
        reason: await report('L’extrait écrit par libmpv est vide ou réduit à son en-tête.', clip),
      );
      // Et il ne doit pas non plus contenir tout le fichier : mpv lit d'avance
      // les quinze secondes entières, et un extrait qui les recopierait
      // prouverait que les bornes demandées n'ont pas été respectées.
      expect(
        result.written,
        lessThan(_wavSeconds * _wavBytesPerSecond ~/ 2),
        reason: await report(
          'L’extrait déborde largement la séquence demandée :'
          ' les bornes passées à dump-cache n’ont pas été respectées.',
          clip,
        ),
      );
    });

    test('un extrait de son reste lisible : signature Matroska en tête', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'extrait.mka');

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));
      final result = await recordClip(clip, play: const Duration(seconds: 2));
      expect(
        result.written,
        greaterThan(32 * 1024),
        reason: await report('Rien à relire : l’extrait n’a pas été écrit.', clip),
      );

      // 1A 45 DF A3 : en-tête EBML, début de tout fichier Matroska. Un extrait
      // qui ne commence pas par là ne s'ouvrira nulle part.
      final head = File(clip).readAsBytesSync().take(4).toList();
      expect(
        head,
        orderedEquals(const [0x1A, 0x45, 0xDF, 0xA3]),
        reason: await report('L’extrait n’est pas un fichier Matroska.', clip),
      );
    });

    test('un extrait réussi ne laisse aucun fichier de travail derrière lui', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'extrait.mka');

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));
      await recordClip(clip, play: const Duration(seconds: 1));

      // Le témoin d'accès au dossier et le fichier de la répétition générale
      // sont écrits dans le dossier de destination : ils doivent en repartir.
      final left = work.listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(
        left,
        orderedEquals(const ['essai.wav', 'extrait.mka']),
        reason: await report('Des fichiers de travail sont restés dans le dossier.', clip),
      );
    });

    test('des pistes que le conteneur refuse : OMNIA le dit, et n’allume rien', () async {
      // Vidéo non compressée : elle joue, mais Matroska peut la refuser faute
      // de code de format. mpv échoue alors à l'écriture de l'en-tête, et c'est
      // tout ce qu'OMNIA doit rapporter — surtout pas un extrait en cours.
      final source = File(p.join(work.path, 'essai.y4m'))..writeAsBytesSync(_rawVideoY4m());
      final clip = p.join(work.path, 'extrait.mkv');

      await openAndPlay(MediaFile(path: source.path, type: MediaType.video));
      final result = await recordClip(clip, play: const Duration(seconds: 2));

      if (result.failure == RecordingFailure.none) {
        // Ce moteur-là sait le faire : alors il doit avoir écrit un extrait.
        expect(
          result.written,
          greaterThan(_headerOnlyBytes),
          reason: await report(
            'Le moteur a accepté l’extrait de vidéo brute, mais n’a rien écrit.',
            clip,
          ),
        );
        return;
      }
      expect(
        result.failure,
        anyOf(RecordingFailure.containerRefused, RecordingFailure.engineRefused),
        reason: await report('Refus attendu, mais pas celui-là.', clip),
      );
      expect(
        File(clip).existsSync(),
        isFalse,
        reason: await report('Un extrait refusé ne doit laisser aucun fichier.', clip),
      );
    });

    test('en pause, le moteur ne prétend pas enregistrer', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'extrait.mka');

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));
      await player.pause();
      await waitFor(
        () => sink.state.status == PlaybackStatus.paused,
        () => 'libmpv n’a pas mis la lecture en pause : ${sink.state.status.name}.',
      );

      final failure = await controller.startRecording(clip);
      trace.add('startRecording en pause → ${failure.name}');
      await controller.releaseRecording();

      // Le cache, lui, est plein : c'est bien l'absence de défilement qui doit
      // faire refuser, et non un fichier impossible à écrire.
      expect(
        failure,
        RecordingFailure.notPlaying,
        reason: await report('Une pause doit refuser l’extrait, et le dire.', clip),
      );
      expect(
        File(clip).existsSync(),
        isFalse,
        reason: await report('Rien ne doit être créé pour un extrait refusé.', clip),
      );
    });

    test('dossier de destination absent : refus, sans fichier fantôme', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'nulle-part', 'extrait.mka');

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));
      final failure = await controller.startRecording(clip);
      trace.add('startRecording vers un dossier absent → ${failure.name}');
      await controller.releaseRecording();

      expect(
        failure,
        RecordingFailure.folderUnavailable,
        reason: await report('Un dossier inexistant doit faire refuser l’extrait.', clip),
      );
      expect(File(clip).existsSync(), isFalse);
    });

    test('après un extrait, le moteur retrouve son cache d’origine', () async {
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final clip = p.join(work.path, 'extrait.mka');
      final platform = player.platform! as NativePlayer;

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));
      final before = await platform.getProperty('demuxer-max-back-bytes');

      await recordClip(clip, play: const Duration(seconds: 1));
      final after = await platform.getProperty('demuxer-max-back-bytes');

      expect(
        after,
        before,
        reason: await report(
          'Le cache arrière agrandi pour l’extrait n’a pas été rendu :'
          ' chaque fichier suivant paierait cette mémoire.',
          clip,
        ),
      );
    });

    test('le cache du démultiplexeur est bien actif : sans lui, aucun extrait', () async {
      // Premier maillon de la chaîne, et le seul qu'OMNIA règle lui-même :
      // `dump-cache` ne recopie que ce que ce cache garde. Le vérifier ici
      // évite de chercher ailleurs quand tout le reste est rouge.
      final source = File(p.join(work.path, 'essai.wav'))..writeAsBytesSync(_sineWav());
      final platform = player.platform! as NativePlayer;

      await openAndPlay(MediaFile(path: source.path, type: MediaType.audio));

      expect(
        await platform.getProperty('cache'),
        'yes',
        reason: await report('Le cache du démultiplexeur est désactivé.', ''),
      );
      expect(
        await platform.getProperty('cache-on-disk'),
        'no',
        reason: await report(
          'Le cache est déporté dans un fichier temporaire (réglage de media_kit) :'
          ' chaque paquet recopié dans un extrait demande alors une relecture.',
          '',
        ),
      );

      // La lecture d'avance est presque instantanée sur un fichier local, mais
      // une machine de CI lente mérite quelques essais.
      var cached = 0.0;
      for (var attempt = 0; attempt < 50 && cached <= 1; attempt++) {
        cached = double.tryParse(await platform.getProperty('demuxer-cache-duration')) ?? 0;
        if (cached > 1) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      trace.add('demuxer-cache-duration = $cached s');
      expect(
        cached,
        greaterThan(1),
        reason: await report(
          'Le démultiplexeur ne garde rien en cache : il n’y aura rien à recopier.',
          '',
        ),
      );
    });
  }, skip: _enabled ? null : 'Test d’intégration libmpv : $_enabledVariable=1 pour le jouer.');
}
