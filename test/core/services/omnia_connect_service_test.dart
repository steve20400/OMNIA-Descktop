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
        _Carte('VirtualBox Host-Only Network', ['192.168.56.1']),
        _Carte('Wi-Fi', ['192.168.1.42']),
      ]);
      expect(choisie, '192.168.1.42');
    });

    test('ignore le pont Docker et le lien VPN', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _Carte('docker0', ['172.17.0.1']),
        _Carte('tun0', ['10.8.0.6']),
        _Carte('en0', ['192.168.1.7']),
      ]);
      expect(choisie, '192.168.1.7');
    });

    test('ignore WSL et Hyper-V', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _Carte('vEthernet (WSL)', ['172.24.16.1']),
        _Carte('Ethernet', ['10.0.0.5']),
      ]);
      expect(choisie, '10.0.0.5');
    });

    test('sans carte virtuelle, prend le réseau local', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _Carte('eth0', ['192.168.0.10']),
        _Carte('eth1', ['10.1.2.3']),
      ]);
      expect(choisie, '192.168.0.10');
    });

    test('172.32.x est public et reste un simple repli', () {
      // 172.16–31 seulement est privé : au-delà, l’adresse n’est pas
      // joignable depuis le téléphone.
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _Carte('eth0', ['172.32.5.5']),
        _Carte('wlan0', ['192.168.1.9']),
      ]);
      expect(choisie, '192.168.1.9');
    });

    test('cartes virtuelles seules : on annonce ce qu’on a', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _Carte('docker0', ['172.17.0.1']),
      ]);
      expect(choisie, '172.17.0.1',
          reason: 'mieux vaut une adresse incertaine que la boucle locale');
    });

    test('aucune carte : la boucle locale', () {
      expect(OmniaConnectService.pickAdvertisedAddress([]), '127.0.0.1');
    });

    test('la boucle locale n’est jamais annoncée comme réseau', () {
      final choisie = OmniaConnectService.pickAdvertisedAddress([
        _Carte('lo', ['127.0.0.1']),
        _Carte('wlan0', ['192.168.1.20']),
      ]);
      expect(choisie, '192.168.1.20');
    });
  });

  group('Projection du PC vers le mobile', () {
    test('buildStreamUrl encode le chemin et le jeton', () {
      final url = OmniaConnectService.buildStreamUrl(
        host: '192.168.1.20',
        port: 41530,
        token: 'ab/c+=',
        path: 'C:\\Films\\ete 2024.mkv',
      );

      expect(url, startsWith('http://192.168.1.20:41530/api/stream?'));
      // Un chemin non encode casserait la requete des le premier espace :
      // c'est le decode qui doit redonner le chemin d'origine, tel quel.
      final uri = Uri.parse(url);
      expect(uri.queryParameters['path'], 'C:\\Films\\ete 2024.mkv');
      expect(uri.queryParameters['token'], 'ab/c+=');
      expect(url, isNot(contains(' ')));
      expect(url, contains('%5C'));
    });

    test('isProjectableHost ecarte les adresses injoignables', () {
      expect(OmniaConnectService.isProjectableHost('192.168.1.20'), isTrue);
      expect(OmniaConnectService.isProjectableHost('10.0.0.5'), isTrue);
      expect(OmniaConnectService.isProjectableHost('127.0.0.1'), isFalse);
      expect(OmniaConnectService.isProjectableHost('0.0.0.0'), isFalse);
      expect(OmniaConnectService.isProjectableHost(''), isFalse);
      expect(OmniaConnectService.isProjectableHost(null), isFalse);
    });

    test('projectFile fait ouvrir le flux par l appareil appaire', () async {
      final mobile = OmniaConnectService(port: 0);
      final pc = OmniaConnectService(port: 0);
      addTearDown(() async {
        await pc.stop();
        pc.dispose();
        await mobile.stop();
        mobile.dispose();
      });

      final mobilePort = await mobile.start(address: InternetAddress.loopbackIPv4);
      final ok = await pc.client.connect(
        host: '127.0.0.1',
        port: mobilePort,
        token: mobile.sessionToken!,
        name: 'OMNIA Desktop',
      );
      expect(ok, isTrue);
      await pc.start(address: InternetAddress.loopbackIPv4);

      final ouverture = mobile.remoteCommands.first;
      final url = await pc.projectFile('C:\\Films\\film.mkv');
      final commande = await ouverture.timeout(const Duration(seconds: 5));

      expect(url, isNotNull);
      expect(url, contains('/api/stream'));
      // Le jeton est encode dans l'URL : le comparer brut echouerait des
      // qu'il contient un caractere reserve (= du base64).
      expect(url, contains(Uri.encodeComponent(pc.sessionToken!)));
      expect(commande, isA<OpenFile>());
      expect((commande as OpenFile).path, url);
    });

    test('le flux projete est servi avec le bon jeton, refuse sinon', () async {
      final pc = OmniaConnectService(port: 0);
      final http = HttpClient();
      addTearDown(() async {
        http.close();
        await pc.stop();
        pc.dispose();
      });

      final port = await pc.start(address: InternetAddress.loopbackIPv4);
      final fichier = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}omnia_projection_pc.mkv',
      );
      await fichier.writeAsBytes(<int>[9, 8, 7, 6]);
      addTearDown(() => fichier.deleteSync());

      final url = OmniaConnectService.buildStreamUrl(
        host: '127.0.0.1',
        port: port,
        token: pc.sessionToken!,
        path: fichier.path,
      );

      final demande = await http.getUrl(Uri.parse(url));
      final reponse = await demande.close();
      expect(reponse.statusCode, 200);
      final octets = await reponse.expand((morceau) => morceau).toList();
      expect(octets.length, 4);

      // Sans le jeton du serveur, le fichier reste prive : le mobile
      // recevrait une erreur 401 au lieu de la video.
      final mauvaise = await http.getUrl(
        Uri.parse(OmniaConnectService.buildStreamUrl(
          host: '127.0.0.1',
          port: port,
          token: 'mauvais-jeton',
          path: fichier.path,
        )),
      );
      final refus = await mauvaise.close();
      expect(refus.statusCode, 401);
    });

    test('projectFile reste sans effet sans appairage actif', () async {
      final pc = OmniaConnectService(port: 0);
      addTearDown(() async {
        await pc.stop();
        pc.dispose();
      });

      expect(await pc.projectFile('C:\\Films\\film.mkv'), isNull);
      expect(await pc.projectFile(''), isNull);
    });
  });
}

/// Fausse carte réseau : `NetworkInterface` est une interface, et l’on veut
/// rejouer des postes réels (VirtualBox, Docker, VPN) sans matériel.
class _Carte implements NetworkInterface {
  _Carte(this.name, List<String> ips)
      : addresses = [for (final ip in ips) InternetAddress(ip)];

  @override
  final String name;

  @override
  final List<InternetAddress> addresses;

  @override
  int get index => 0;
}
