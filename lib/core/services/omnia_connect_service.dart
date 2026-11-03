import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../commands/player_command.dart';
import '../models/media_file.dart';
import '../models/media_type.dart';
import '../models/playback_state.dart';
import '../models/playback_status.dart';
import '../utils/connect_mode.dart';

/// Message échangé sur le canal WebSocket d'OMNIA Connect.
class ConnectMessage {
  const ConnectMessage({
    required this.type,
    this.payload = const {},
  });

  factory ConnectMessage.fromJson(Map<String, Object?> json) {
    return ConnectMessage(
      type: json['type'] as String? ?? 'unknown',
      payload: json['payload'] as Map<String, Object?>? ?? const {},
    );
  }

  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
        'type': type,
        'payload': payload,
      };

  String serialize() => jsonEncode(toJson());
}

/// Service de communication locale Zero-Internet OMNIA Connect (Version Desktop).
///
/// Permet la projection d'écran, la télécommande tactile et le streaming
/// direct de médias volumineux sur réseau local (Wi-Fi ou Hotspot) sans Internet.
class OmniaConnectService {
  OmniaConnectService({this.port = 41530});

  final int port;

  HttpServer? _server;
  String? _sessionToken;

  /// Dernier état de lecture local, tenu à jour par [followStates].
  PlaybackState _localState = const PlaybackState();
  StreamSubscription<PlaybackState>? _localStates;

  /// Vrai quand cet appareil reçoit une lecture en miroir et doit s'y caler.
  bool _mirroring = false;

  /// Vrai quand cet appareil projette en miroir et doit annoncer son état.
  bool _mirrorSending = false;
  int _lastMirrorTick = -1;
  final Set<WebSocket> _clients = {};

  final StreamController<PlayerCommand> _remoteCommands =
      StreamController<PlayerCommand>.broadcast();

  final StreamController<bool> _connectionState =
      StreamController<bool>.broadcast();

  Stream<PlayerCommand> get remoteCommands => _remoteCommands.stream;
  Stream<bool> get isConnectedStream => _connectionState.stream;

  bool get isRunning => _server != null;
  bool get hasConnectedClients => _clients.isNotEmpty;
  String? get sessionToken => _sessionToken;

  /// Démarre le serveur local et génère le jeton d'appairage éphémère.
  Future<int> start({InternetAddress? address}) async {
    if (_server != null) return _server!.port;

    _sessionToken = _generateToken();
    final bindAddress = address ?? InternetAddress.anyIPv4;
    try {
      _server = await HttpServer.bind(bindAddress, port);
    } catch (_) {
      // Si le port 41530 est occupé, on alloue un port dynamique
      _server = await HttpServer.bind(bindAddress, 0);
    }
    _server?.idleTimeout = null;

    _server!.listen(_handleRequest);
    return _server!.port;
  }

  /// Arrête le serveur et clôture toutes les connexions actives.
  Future<void> stop() async {
    final activeClients = _clients.toList();
    _clients.clear();
    for (final client in activeClients) {
      try {
        await client.close();
      } catch (_) {}
    }
    await _server?.close(force: true);
    _server = null;
    _sessionToken = null;
    if (!_connectionState.isClosed) {
      _connectionState.add(false);
    }
  }

  /// Récupère l'adresse IP locale du périphérique (Wi-Fi / Ethernet).
  Future<String> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      return pickAdvertisedAddress(interfaces);
    } catch (_) {
      return '127.0.0.1';
    }
  }

  /// Adresse à annoncer pour l'appairage, choisie parmi les cartes réseau.
  ///
  /// Retenir la première adresse non bouclée — ce que faisait cette méthode —
  /// annonçait souvent une carte que le téléphone ne peut joindre : l'hôte des
  /// machines virtuelles (192.168.56.1), les ponts de conteneurs (172.17.0.1),
  /// Hyper-V ou un lien VPN. L'appairage échouait alors sans rien dire, le
  /// téléphone n'atteignant jamais l'adresse inscrite dans le QR code.
  ///
  /// Séparée de l'appel système pour être vérifiable avec de fausses cartes.
  static String pickAdvertisedAddress(List<NetworkInterface> interfaces) {
    String? repli;

    for (final iface in interfaces) {
      final virtuelle = _isVirtualInterface(iface.name);
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback || ip.startsWith('127.')) continue;
        // Le seul cas qui intéresse l'appairage : une adresse de réseau local
        // sur une carte qui joint vraiment le poste de l'utilisateur.
        if (!virtuelle && _isPrivateAddress(ip)) return ip;
        repli ??= ip;
      }
    }
    // Aucun réseau local hors cartes virtuelles : on annonce ce qu'on a
    // trouvé, à défaut la boucle locale (PC et téléphone sur le même poste).
    return repli ?? '127.0.0.1';
  }

  /// Cartes qui ne joignent pas le réseau de l'utilisateur : hôte des machines
  /// virtuelles, ponts de conteneurs, liens VPN.
  static bool _isVirtualInterface(String name) {
    final n = name.toLowerCase();
    const marques = [
      'vboxnet', 'virtualbox', 'vmware', 'vmnet', 'docker', 'br-', 'virbr',
      'veth', 'lxc', 'lxd', 'tun', 'tap', 'wsl', 'vethernet', 'hyper-v',
      'hamachi', 'zerotier', 'tailscale', 'wg', 'cni', 'flannel', 'kube',
      'podman', 'rndis', 'nordlynx', 'proton', 'ppp', 'utun',
    ];
    for (final marque in marques) {
      if (n.contains(marque)) return true;
    }
    return false;
  }

  /// Adresse d'un réseau local au sens RFC 1918 : c'est de là que le téléphone
  /// joindra le poste.
  static bool _isPrivateAddress(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    // 172.16.0.0 – 172.31.255.255 seulement : le reste de 172.x est public,
    // et une adresse publique n'est pas joignable depuis le téléphone.
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]);
      return second != null && second >= 16 && second <= 31;
    }
    return false;
  }

  /// Vérifie les prérequis réels du mode de liaison choisi.
  ///
  /// Les boutons de mode n'enregistraient qu'une préférence : rien ne
  /// contrôlait que le Wi-Fi était actif, qu'un point d'accès tournait ou
  /// qu'un lien PAN Bluetooth existait, et l'appairage échouait plus tard sans
  /// rien dire. Le rapport rendu ici porte soit l'adresse à annoncer, soit ce
  /// qui manque et la marche à suivre.
  Future<ConnectModeReport> inspectMode(ConnectMode mode) async {
    try {
      // Borné dans le temps : un pilote en faute peut ne jamais répondre, et
      // l'interface resterait alors en « vérification » indéfiniment.
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      ).timeout(ConnectModeInspector.probeTimeout);
      return ConnectModeInspector.inspect(mode: mode, interfaces: interfaces);
    } catch (_) {
      return ConnectModeInspector.unavailable(mode);
    }
  }

  /// Adresse à annoncer pour [mode], ou `null` quand il n'y en a aucune.
  ///
  /// En Bluetooth sans lien PAN il n'y a rien à annoncer : publier l'adresse
  /// Wi-Fi ferait croire à un appairage possible et le téléphone n'atteindrait
  /// jamais le poste.
  Future<String?> addressForMode(ConnectMode mode) async {
    final announced = (await inspectMode(mode)).announcedAddress;
    if (announced != null) return announced;
    // Le Wi-Fi garde son repli historique : la boucle locale permet encore
    // d'appairer deux instances sur la même machine.
    return mode == ConnectMode.wifi ? await getLocalIpAddress() : null;
  }

  /// Génère le payload d'appairage QR Code.
  ///
  /// L'hôte publié suit le [mode] : annoncer l'adresse Wi-Fi alors que c'est
  /// le point d'accès qui porte la liaison rend le code injoignable.
  Future<String> getPairingPayload(
    String deviceName, {
    ConnectMode mode = ConnectMode.wifi,
  }) async {
    final ip = await addressForMode(mode) ?? '';
    final p = _server?.port ?? port;
    final map = {
      'protocol': 'omnia-connect',
      'version': '1.0',
      'name': deviceName,
      'host': ip,
      'port': p,
      'token': _sessionToken ?? '',
    };
    return jsonEncode(map);
  }

  /// URL du flux HTTP par lequel ce poste sert [path] au réseau local.
  ///
  /// Le jeton transmis est celui du serveur local : c'est lui qui autorise la
  /// lecture du fichier, l'appareil distant n'ayant aucun accès au disque.
  static String buildStreamUrl({
    required String host,
    required int port,
    required String token,
    required String path,
  }) {
    return Uri.http(
      '$host:$port',
      '/api/stream',
      <String, String>{'path': path, 'token': token},
    ).toString();
  }

  /// Vrai si [host] est une adresse que l'appareil distant peut joindre.
  ///
  /// La boucle locale et l'adresse indéterminée ne joignent que l'appareil qui
  /// les annonce : les publier ferait échouer la projection sans rien dire.
  static bool isProjectableHost(String? host) {
    if (host == null || host.isEmpty) return false;
    return host != '127.0.0.1' && host != '0.0.0.0';
  }

  /// Demande à l'hôte appairé de lire [path], servi par ce poste.
  ///
  /// Renvoie l'URL projetée, ou `null` quand la projection est impossible —
  /// pas d'appairage actif, chemin vide ou adresse injoignable — pour que
  /// l'interface puisse l'expliquer au lieu d'échouer en silence.
  /// [mirror] demande la lecture en miroir : l'autre appareil ne se contente
  /// alors pas d'ouvrir le fichier, il suit aussi ce qu'on y fait.
  Future<String?> projectFile(
    String path, {
    ConnectMode mode = ConnectMode.wifi,
    bool mirror = false,
  }) async {
    if (path.isEmpty || !client.connected) return null;

    final serverPort = await start();
    final host = await addressForMode(mode);
    if (!isProjectableHost(host)) return null;

    final url = buildStreamUrl(
      host: host!,
      port: serverPort,
      token: _sessionToken ?? '',
      path: path,
    );
    _mirrorSending = mirror;
    _lastMirrorTick = -1;
    client.projectStream(url, mirror: mirror);
    return url;
  }

  /// Les spectateurs de l'écran partagé, et les paramètres de décodage.
  final List<HttpResponse> _screenViewers = [];
  List<int>? _screenHeader;

  /// Sert l'écran partagé : un flux H.264 qui ne se termine jamais.
  ///
  /// Les paramètres de décodage partent en tête pour chaque spectateur, même
  /// arrivé en cours de route : sans eux, un lecteur ne décode rien et reste
  /// sur un écran noir sans dire pourquoi.
  Future<void> _handleScreenStream(HttpRequest request) async {
    if (request.uri.queryParameters['token'] != _sessionToken) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('video', 'h264');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final header = _screenHeader;
    if (header != null) response.add(header);
    _screenViewers.add(response);
    try {
      await response.done;
    } on Object {
      // Le spectateur est parti : c'est la fin normale de ce flux.
    }
    _screenViewers.remove(response);
  }

  /// Pousse un morceau d'écran encodé vers les spectateurs.
  void feedScreenChunk(List<int> bytes, {required bool header}) {
    if (header) _screenHeader = List<int>.unmodifiable(bytes);
    for (final viewer in List<HttpResponse>.of(_screenViewers)) {
      try {
        viewer.add(bytes);
      } on Object {
        _screenViewers.remove(viewer);
      }
    }
  }

  /// Demande à l'hôte appairé d'afficher l'écran de cet appareil.
  ///
  /// Contrairement aux deux autres modes, rien n'est lu : c'est l'image de
  /// l'écran, encodée au vol, qui part sur le réseau.
  Future<String?> projectScreen({ConnectMode mode = ConnectMode.wifi}) async {
    if (!client.connected) return null;
    final serverPort = await start();
    final host = await addressForMode(mode);
    if (!isProjectableHost(host)) return null;
    final url = Uri.http(
      '$host:$serverPort',
      '/api/screen',
      <String, String>{'token': _sessionToken ?? ''},
    ).toString();
    _mirrorSending = false;
    client.projectStream(url);
    return url;
  }

  /// Diffuse l'état actuel de lecture aux clients appairés.
  /// Suit l'état de lecture local, hors de toute fenêtre.
  ///
  /// Sert des deux côtés de la liaison. L'appareil qui projette en miroir
  /// envoie cet état à l'autre ; celui qui reçoit s'en sert pour mesurer son
  /// écart avec ce qu'on lui annonce. Auparavant l'état ne partait que depuis
  /// la fenêtre OMNIA Connect, et s'arrêtait donc dès qu'on la fermait — ce
  /// qu'on fait précisément pour regarder.
  void followStates(Stream<PlaybackState> states) {
    unawaited(_localStates?.cancel());
    _localStates = states.listen(_onLocalState);
  }

  void _onLocalState(PlaybackState state) {
    _localState = state;
    if (hasConnectedClients) broadcastState(state);
    if (!_mirrorSending || !client.connected) return;
    // Une fois par demi-seconde : la position change à chaque image, et
    // inonder la liaison ne rendrait pas le miroir plus fidèle.
    final now = state.position.inMilliseconds ~/ 500;
    if (now == _lastMirrorTick) return;
    _lastMirrorTick = now;
    client.sendMirrorState(state);
  }

  /// Cale la lecture locale sur celle de l'appareil qui projette.
  ///
  /// On converge vers l'état reçu plutôt que de rejouer les gestes : un geste
  /// perdu ou reçu deux fois décalerait les deux lectures pour de bon, alors
  /// qu'un état en retard se rattrape de lui-même au message suivant.
  void _applyMirrorState(Map<String, Object?> payload) {
    if (!_mirroring || _remoteCommands.isClosed) return;

    final positionMs = (payload['positionMs'] as num?)?.toInt();
    if (positionMs != null) {
      final cible = Duration(milliseconds: positionMs);
      final ecart = (cible - _localState.position).abs();
      // Seul un écart visible mérite un saut : se recaler à chaque message
      // hacherait la lecture au lieu de la suivre.
      if (ecart > const Duration(milliseconds: 1500)) {
        _remoteCommands.add(SeekAbsolute(cible));
      }
    }

    final volume = (payload['volume'] as num?)?.toDouble();
    if (volume != null && (volume - _localState.volume).abs() > 0.5) {
      _remoteCommands.add(SetVolume(volume));
    }

    final page = (payload['page'] as num?)?.toInt();
    if (page != null && page > 0 && page != _localState.currentPage) {
      _remoteCommands.add(GoToPage(page));
    }

    final scroll = (payload['scrollFraction'] as num?)?.toDouble();
    if (scroll != null && (scroll - _localState.scrollFraction).abs() > 0.004) {
      _remoteCommands.add(ScrollTo(scroll));
    }

    final playing = payload['status'] == PlaybackStatus.playing.name;
    if (playing != (_localState.status == PlaybackStatus.playing)) {
      _remoteCommands.add(const TogglePlay());
    }
  }

  void broadcastState(PlaybackState state) {
    if (_clients.isEmpty) return;

    final msg = ConnectMessage(
      type: 'state',
      payload: {
        'status': state.status.name,
        'title': state.file?.name ?? '',
        'positionMs': state.position.inMilliseconds,
        'durationMs': state.duration.inMilliseconds,
        'volume': state.volume,
        'page': state.currentPage,
        'pageCount': state.totalPages,
        'isDocument': state.isDocument,
      },
    );
    final serialized = msg.serialize();
    for (final client in _clients) {
      try {
        client.add(serialized);
      } catch (_) {}
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Authorization');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (path == '/api/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'online',
        'service': 'OMNIA Connect',
        'version': '1.0',
      }));
      await request.response.close();
      return;
    }

    if (path == '/api/ws') {
      final token = request.uri.queryParameters['token'];

      // Mêmes règles que l'hôte mobile. Sans cet alignement, l'appairage
      // changeait de comportement selon l'appareil qui sert d'hôte : un
      // client qui saisit l'adresse à la main — jeton vide, OMNIA Mobile
      // part de `String token = ''` — était accepté par le téléphone et
      // refusé ici en 401. Le jeton reste exigé de tout client qui n'est pas
      // sur la boucle locale ou le réseau local (RFC 1918).
      final address = request.connectionInfo?.remoteAddress;
      final isLocalClient = address?.isLoopback == true ||
          (address?.address.startsWith('192.168.') ?? false) ||
          (address?.address.startsWith('10.') ?? false) ||
          (address?.address.startsWith('172.') ?? false);
      final tokenMatches = token == _sessionToken;
      final allowedManual =
          isLocalClient && (token == null || token.isEmpty || token == 'omnia');

      if (!tokenMatches && !allowedManual) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleClientSocket(socket);
        return;
      }
    }

    if (path == '/api/screen') {
      await _handleScreenStream(request);
      return;
    }

    if (path == '/api/stream') {
      await _handleStreaming(request);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  void _handleClientSocket(WebSocket socket) {
    _clients.add(socket);
    if (!_connectionState.isClosed) {
      _connectionState.add(true);
    }

    socket.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String) as Map<String, Object?>;
          final msg = ConnectMessage.fromJson(decoded);
          _processRemoteMessage(msg);
        } catch (_) {}
      },
      onDone: () {
        _clients.remove(socket);
        if (!_connectionState.isClosed) {
          _connectionState.add(_clients.isNotEmpty);
        }
      },
      onError: (_) {
        _clients.remove(socket);
        if (!_connectionState.isClosed) {
          _connectionState.add(_clients.isNotEmpty);
        }
      },
    );
  }

  void _processRemoteMessage(ConnectMessage msg) {
    if (_remoteCommands.isClosed) return;
    switch (msg.type) {
      case 'togglePlay':
        _remoteCommands.add(const TogglePlay());
        break;
      case 'seekRelative':
        final seconds = (msg.payload['seconds'] as num?)?.toDouble() ?? 0.0;
        _remoteCommands.add(SeekRelative(seconds));
        break;
      case 'seekAbsolute':
        final ms = (msg.payload['positionMs'] as num?)?.toInt() ?? 0;
        _remoteCommands.add(SeekAbsolute(Duration(milliseconds: ms)));
        break;
      case 'volumeRelative':
        final delta = (msg.payload['delta'] as num?)?.toDouble() ?? 0.0;
        _remoteCommands.add(VolumeRelative(delta));
        break;
      case 'next':
        _remoteCommands.add(const NextFile());
        break;
      case 'previous':
        _remoteCommands.add(const PreviousFile());
        break;
      case 'nextPage':
        _remoteCommands.add(const NextPage());
        break;
      case 'previousPage':
        _remoteCommands.add(const PreviousPage());
        break;
      case 'openRemoteStream':
        final url = msg.payload['url'] as String?;
        if (url != null) {
          // Le mode se déclare à l'ouverture : l'appareil qui projette en
          // décide, celui qui reçoit s'y conforme.
          _mirroring = msg.payload['mirror'] == true;
          _remoteCommands.add(OpenFile(url));
        }
        break;
      case 'mirrorState':
        _applyMirrorState(msg.payload);
        break;
    }
  }

  /// Diffusion multimédia avec support RFC 7233 (HTTP Range Requests).
  Future<void> _handleStreaming(HttpRequest request) async {
    final filePath = request.uri.queryParameters['path'];
    final token = request.uri.queryParameters['token'];

    if (token != _sessionToken || filePath == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final totalSize = await file.length();
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeParts = rangeHeader.substring(6).split('-');
      final start = int.parse(rangeParts[0]);
      final end = rangeParts.length > 1 && rangeParts[1].isNotEmpty
          ? int.parse(rangeParts[1])
          : totalSize - 1;

      final chunkLength = end - start + 1;
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.add(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalSize');
      request.response.headers.contentLength = chunkLength;

      final stream = file.openRead(start, end + 1);
      await request.response.addStream(stream);
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentLength = totalSize;
      await request.response.addStream(file.openRead());
      await request.response.close();
    }
  }

  OmniaConnectClient? _client;

  /// Client permettant de se connecter à une autre instance OMNIA distante.
  OmniaConnectClient get client => _client ??= OmniaConnectClient();

  String _generateToken() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  void dispose() {
    stop();
    _client?.dispose();
    if (!_remoteCommands.isClosed) _remoteCommands.close();
    if (!_connectionState.isClosed) _connectionState.close();
  }
}

/// Client OMNIA Connect pour se connecter à une instance distante (Desktop ou Mobile)
/// et faire office de télécommande interactive ou de passerelle de projection.
class OmniaConnectClient {
  WebSocket? _socket;
  final StreamController<PlaybackState> _remoteStateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<PlaybackState> get remoteState => _remoteStateController.stream;
  Stream<bool> get isConnected => _connectionController.stream;
  bool get connected => _socket != null;

  String? host;
  int? port;
  String? token;
  String? deviceName;

  /// Établit la connexion avec l'hôte distant via WebSocket.
  Future<bool> connect({
    required String host,
    required int port,
    required String token,
    String? name,
  }) async {
    await disconnect();
    this.host = host;
    this.port = port;
    this.token = token;
    deviceName = name;

    try {
      final uri = Uri.parse('ws://$host:$port/api/ws?token=$token');
      _socket = await WebSocket.connect(uri.toString()).timeout(
        const Duration(seconds: 4),
      );
      if (!_connectionController.isClosed) {
        _connectionController.add(true);
      }

      _socket!.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, Object?>;
            if (decoded['type'] == 'state') {
              final payload = decoded['payload'] as Map<String, Object?>? ?? {};
              final state = PlaybackState(
                status: PlaybackStatus.values.byName(payload['status'] as String? ?? 'idle'),
                position: Duration(milliseconds: (payload['positionMs'] as num?)?.toInt() ?? 0),
                duration: Duration(milliseconds: (payload['durationMs'] as num?)?.toInt() ?? 0),
                volume: (payload['volume'] as num?)?.toDouble() ?? 100.0,
                currentPage: (payload['page'] as num?)?.toInt() ?? 0,
                totalPages: (payload['pageCount'] as num?)?.toInt() ?? 0,
                file: payload['title'] != null && (payload['title'] as String).isNotEmpty
                    ? MediaFile(
                        path: payload['title'] as String,
                        type: (payload['isDocument'] as bool? ?? false)
                            ? MediaType.doc
                            : MediaType.video,
                      )
                    : null,
              );
              if (!_remoteStateController.isClosed) {
                _remoteStateController.add(state);
              }
            }
          } catch (_) {}
        },
        onDone: () {
          _socket = null;
          if (!_connectionController.isClosed) {
            _connectionController.add(false);
          }
        },
        onError: (_) {
          _socket = null;
          if (!_connectionController.isClosed) {
            _connectionController.add(false);
          }
        },
      );
      return true;
    } catch (_) {
      _socket = null;
      if (!_connectionController.isClosed) {
        _connectionController.add(false);
      }
      return false;
    }
  }

  /// Envoie une commande de télécommande à l'hôte distant.
  void sendCommand(PlayerCommand command) {
    if (_socket == null) return;
    ConnectMessage? msg;
    if (command is TogglePlay) {
      msg = const ConnectMessage(type: 'togglePlay');
    } else if (command is SeekRelative) {
      msg = ConnectMessage(type: 'seekRelative', payload: {'seconds': command.seconds});
    } else if (command is SeekAbsolute) {
      msg = ConnectMessage(
          type: 'seekAbsolute', payload: {'positionMs': command.position.inMilliseconds});
    } else if (command is VolumeRelative) {
      msg = ConnectMessage(type: 'volumeRelative', payload: {'delta': command.delta});
    } else if (command is NextFile) {
      msg = const ConnectMessage(type: 'next');
    } else if (command is PreviousFile) {
      msg = const ConnectMessage(type: 'previous');
    } else if (command is NextPage) {
      msg = const ConnectMessage(type: 'nextPage');
    } else if (command is PreviousPage) {
      msg = const ConnectMessage(type: 'previousPage');
    }
    if (msg != null) {
      try {
        _socket!.add(msg.serialize());
      } catch (_) {}
    }
  }

  /// Ordonne à l'hôte distant de charger et projeter un flux HTTP.
  void projectStream(String streamUrl, {bool mirror = false}) {
    if (_socket == null) return;
    final msg = ConnectMessage(
      type: 'openRemoteStream',
      payload: {'url': streamUrl, 'mirror': mirror},
    );
    try {
      _socket!.add(msg.serialize());
    } catch (_) {}
  }

  /// Annonce l'état de lecture à l'appareil qui nous suit en miroir.
  void sendMirrorState(PlaybackState state) {
    if (_socket == null) return;
    final msg = ConnectMessage(
      type: 'mirrorState',
      payload: {
        'status': state.status.name,
        'positionMs': state.position.inMilliseconds,
        'volume': state.volume,
        'page': state.currentPage,
        'scrollFraction': state.scrollFraction,
      },
    );
    try {
      _socket!.add(msg.serialize());
    } catch (_) {}
  }

  /// Déconnecte le client du serveur distant.
  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  void dispose() {
    disconnect();
    if (!_remoteStateController.isClosed) _remoteStateController.close();
    if (!_connectionController.isClosed) _connectionController.close();
  }
}
