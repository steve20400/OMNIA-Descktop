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

    test('accepte un appairage manuel sans jeton depuis la machine même',
        () async {
      // Cas du téléphone où l'on saisit l'adresse à la main au lieu de
      // scanner le QR code : OMNIA Mobile part alors d'un jeton vide
      // (`String token = ''`). L'hôte mobile l'acceptait, le bureau le
      // refusait en 401 : l'appairage échouait donc selon l'appareil qui
      // servait d'hôte. Le jeton reste exigé de tout client non local.
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final client = OmniaConnectClient();
      addTearDown(client.dispose);

      final ok = await client.connect(
        host: '127.0.0.1',
        port: port,
        token: '',
      );

      expect(ok, isTrue, reason: "l'appairage manuel doit être accepté");
      expect(client.connected, isTrue);

      final cmdFuture = service.remoteCommands.first;
      client.sendCommand(const TogglePlay());
      expect(await cmdFuture, isA<TogglePlay>(),
          reason: 'un client appairé à la main doit pouvoir télécommander');

      await client.disconnect();
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

    test('OmniaConnectClient se connecte, envoie des commandes et reçoit l\'état', () async {
      final port = await service.start(address: InternetAddress.loopbackIPv4);
      final client = OmniaConnectClient();

      final ok = await client.connect(
        host: '127.0.0.1',
        port: port,
        token: service.sessionToken!,
        name: 'Client Test',
      );
      expect(ok, isTrue);
      expect(client.connected, isTrue);

      final cmdFuture = service.remoteCommands.first;
      client.sendCommand(const NextFile());
      final cmd = await cmdFuture;
      expect(cmd, isA<NextFile>());

      final stateFuture = client.remoteState.first;
      service.broadcastState(
        const PlaybackState(
          status: PlaybackStatus.paused,
          position: Duration(seconds: 15),
          duration: Duration(minutes: 3),
        ),
      );
      final remoteState = await stateFuture;
      expect(remoteState.status, PlaybackStatus.paused);
      expect(remoteState.position, const Duration(seconds: 15));

      await client.disconnect();
      client.dispose();
    });
  });

  group('Choix de l’adresse annoncée', () {
    test('ignore la carte hôte de VirtualBox', () {
      // Cas courant sur un poste de développement : la carte hôte vient avant
      // le Wi-Fi dans la liste, et le téléphone ne peut pas la joindre.
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('VirtualBox Host-Only Network', ['192.168.56.1']),
        _carte('Wi-Fi', ['192.168.1.42']),
      ]);
      expect(choisie, '192.168.1.42');
    });

    test('ignore le pont Docker et le lien VPN', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('docker0', ['172.17.0.1']),
        _carte('tun0', ['10.8.0.6']),
        _carte('en0', ['192.168.1.7']),
      ]);
      expect(choisie, '192.168.1.7');
    });

    test('ignore WSL et Hyper-V', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('vEthernet (WSL)', ['172.24.16.1']),
        _carte('Ethernet', ['10.0.0.5']),
      ]);
      expect(choisie, '10.0.0.5');
    });

    test('sans carte virtuelle, prend le réseau local', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('eth0', ['192.168.0.10']),
        _carte('eth1', ['10.1.2.3']),
      ]);
      expect(choisie, '192.168.0.10');
    });

    test('172.32.x est public et reste un simple repli', () {
      // 172.16–31 seulement est privé : au-delà, l’adresse n’est pas
      // joignable depuis le téléphone.
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('eth0', ['172.32.5.5']),
        _carte('wlan0', ['192.168.1.9']),
      ]);
      expect(choisie, '192.168.1.9');
    });

    test('cartes virtuelles seules : on annonce ce qu’on a', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('docker0', ['172.17.0.1']),
      ]);
      expect(choisie, '172.17.0.1',
          reason: 'mieux vaut une adresse incertaine que la boucle locale');
    });

    test('aucune carte : la boucle locale', () {
      expect(OmniaConnectService.pickAdvertisedAddress([]), '127.0.0.1');
    });

    test('la boucle locale n’est jamais annoncée comme réseau', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _carte('lo', ['127.0.0.1']),
        _carte('wlan0', ['192.168.1.20']),
      ]);
      expect(choisie, '192.168.1.20');
    });
  });
}

/// Fausse carte réseau : `NetworkInterface` est une interface, et l’on veut
/// rejouer des postes réels (VirtualBox, Docker, VPN) sans matériel.
class _carte implements NetworkInterface {
  _carte(this.name, List<String> ips)
      : addresses = [for (final ip in ips) InternetAddress(ip)];

  @override
  final String name;

  @override
  final List<InternetAddress> addresses;

  @override
  int get index => 0;
}
