import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/services/single_instance.dart';

void main() {
  group('InstanceMessage', () {
    test('aller-retour', () {
      const message = InstanceMessage(token: 'abc', args: ['/a.mkv', '--x']);
      final decoded = InstanceMessage.decode(message.encode());
      expect(decoded?.token, 'abc');
      expect(decoded?.args, ['/a.mkv', '--x']);
    });

    test('se termine par un saut de ligne, sur une seule ligne', () {
      const message = InstanceMessage(token: 't', args: ['x']);
      final encoded = message.encode();
      expect(encoded.endsWith('\n'), isTrue);
      expect('\n'.allMatches(encoded).length, 1);
    });

    test('rejette tout ce qui n’est pas un message OMNIA', () {
      expect(InstanceMessage.decode('GET / HTTP/1.1'), isNull);
      expect(InstanceMessage.decode(''), isNull);
      expect(InstanceMessage.decode('[]'), isNull);
      expect(InstanceMessage.decode('{"token": 1, "args": []}'), isNull);
      expect(InstanceMessage.decode('{"token": "t"}'), isNull);
      expect(InstanceMessage.decode('{"token": "t", "args": [1]}'), isNull);
    });
  });

  group('SingleInstanceService', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('omnia_instance_'));
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Nettoyé par le système.
      }
    });

    test('sans première instance, on ne délègue pas', () async {
      final service = SingleInstanceService(directory: dir);
      expect(await service.delegateToExisting(['/a.mkv']), isFalse);
    });

    test('la seconde instance transmet ses arguments à la première', () async {
      final first = SingleInstanceService(directory: dir);
      final received = Completer<List<String>>();
      await first.serve(received.complete);
      expect(first.lockFile.existsSync(), isTrue);

      final second = SingleInstanceService(directory: dir);
      final delegated = await second.delegateToExisting(['/films/a.mkv']);

      expect(delegated, isTrue);
      expect(await received.future, ['/films/a.mkv']);

      await first.dispose();
    });

    test('un verrou périmé (port fermé) ne bloque pas le démarrage', () async {
      final first = SingleInstanceService(directory: dir);
      await first.serve((_) {});
      await first.dispose(); // ferme le port, supprime le verrou
      // On simule une instance tuée : le verrou est resté.
      await first.lockFile.writeAsString('{"port": 1, "token": "x"}');

      final second = SingleInstanceService(directory: dir);
      expect(await second.delegateToExisting(['/a.mkv']), isFalse);
    });

    test('un verrou corrompu est ignoré', () async {
      await File('${dir.path}/${SingleInstanceService.lockFileName}')
          .writeAsString('pas du json');
      final service = SingleInstanceService(directory: dir);
      expect(await service.delegateToExisting(['/a.mkv']), isFalse);
    });

    test('un client sans le bon secret est ignoré sans réponse', () async {
      final first = SingleInstanceService(directory: dir);
      var calls = 0;
      await first.serve((_) => calls++);

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, first.port!);
      socket.write(const InstanceMessage(token: 'mauvais', args: ['/x.mkv']).encode());
      await socket.flush();
      final reply = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3), onTimeout: () => '');
      await socket.close();

      expect(reply, isEmpty);
      expect(calls, 0);
      await first.dispose();
    });

    test('un client qui envoie n’importe quoi est ignoré', () async {
      final first = SingleInstanceService(directory: dir);
      var calls = 0;
      await first.serve((_) => calls++);

      final socket = await Socket.connect(InternetAddress.loopbackIPv4, first.port!);
      socket.write('GET / HTTP/1.1\r\n\r\n');
      await socket.flush();
      await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3), onTimeout: () => '');
      await socket.close();

      expect(calls, 0);
      await first.dispose();
    });

    test('dispose supprime le verrou', () async {
      final service = SingleInstanceService(directory: dir);
      await service.serve((_) {});
      expect(service.lockFile.existsSync(), isTrue);
      await service.dispose();
      expect(service.lockFile.existsSync(), isFalse);
    });

    test('une instance qui ne sert pas ne supprime pas le verrou de la première', () async {
      final first = SingleInstanceService(directory: dir);
      await first.serve((_) {});

      final secondary = SingleInstanceService(directory: dir);
      await secondary.dispose();

      expect(first.lockFile.existsSync(), isTrue);
      await first.dispose();
    });
  });

  group('Réglage « instance unique »', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('omnia_marker_'));
    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Nettoyé par le système.
      }
    });

    test('actif par défaut', () {
      expect(singleInstanceEnabled(dir), isTrue);
    });

    test('désactiver pose un marqueur, réactiver le retire', () async {
      await writeSingleInstancePreference(dir, enabled: false);
      expect(singleInstanceEnabled(dir), isFalse);
      await writeSingleInstancePreference(dir, enabled: true);
      expect(singleInstanceEnabled(dir), isTrue);
    });

    test('réactiver sans marqueur ne fait rien', () async {
      await writeSingleInstancePreference(dir, enabled: true);
      expect(singleInstanceEnabled(dir), isTrue);
    });
  });
}
