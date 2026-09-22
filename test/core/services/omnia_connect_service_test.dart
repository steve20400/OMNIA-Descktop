import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/services/omnia_connect_service.dart';

void main() {
  group('OmniaConnectService Desktop', () {
    late OmniaConnectService service;

    setUp(() {
      service = OmniaConnectService(port: 0); // Port dynamique pour les tests
    });

    tearDown(() async {
      await service.stop();
      service.dispose();
    });

    test('démarre le serveur et génère un jeton', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      expect(port, greaterThan(0));
      expect(service.isRunning, isTrue);
      expect(service.sessionToken, isNotNull);
      expect(service.sessionToken!.length, greaterThanOrEqualTo(16));
    });

    test('génère un payload de couplage valide', () async {
      await service.start(address: InternetAddress.loopbackIPv4);
      final payload = await service.getPairingPayload('OMNIA Desktop Test');
      final decoded = jsonDecode(payload) as Map<String, dynamic>;

      expect(decoded['protocol'], 'omnia-connect');
      expect(decoded['version'], '1.0');
      expect(decoded['name'], 'OMNIA Desktop Test');
      expect(decoded['token'], service.sessionToken);
      expect(decoded['port'], greaterThan(0));
    });

    test('répond aux requêtes HTTP GET /api/status', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final client = HttpClient();
      final req = await client.get('127.0.0.1', port, '/api/status');
      final res = await req.close();

      expect(res.statusCode, HttpStatus.ok);
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['service'], 'OMNIA Connect');
      expect(json['status'], 'online');
      client.close();
    });

    test('refuse une connexion WebSocket avec un jeton invalide', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final client = HttpClient();
      expect(
        () => WebSocket.connect('ws://127.0.0.1:$port/api/ws?token=invalid_token'),
        throwsA(anything),
      );
      client.close();
    });

    test('accepte WebSocket valide et relaie les commandes distantes', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final connectedFuture = service.isConnectedStream.firstWhere((c) => c);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:$port/api/ws?token=${service.sessionToken}',
      );
      await connectedFuture;

      expect(service.hasConnectedClients, isTrue);

      final cmdFuture = service.remoteCommands.first;
      ws.add(jsonEncode({'type': 'togglePlay', 'payload': {}}));

      final received = await cmdFuture;
      expect(received, isA<TogglePlay>());

      await ws.close();
    });

    test('diffuse l\'état de lecture aux clients WebSocket', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final connectedFuture = service.isConnectedStream.firstWhere((c) => c);
      final ws = await WebSocket.connect(
        'ws://127.0.0.1:$port/api/ws?token=${service.sessionToken}',
      );
      await connectedFuture;

      final nextMsgFuture = ws.first;
      service.broadcastState(
        const PlaybackState(
          status: PlaybackStatus.playing,
          position: Duration(seconds: 42),
          duration: Duration(seconds: 120),
        ),
      );

      final raw = await nextMsgFuture;
      final parsed = jsonDecode(raw as String) as Map<String, dynamic>;
      expect(parsed['type'], 'state');
      final payload = parsed['payload'] as Map<String, dynamic>;
      expect(payload['status'], 'playing');
      expect(payload['positionMs'], 42000);

      await ws.close();
    });
  });
}
