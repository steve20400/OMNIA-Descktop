import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'foreground_permission.dart';

/// Nom du fichier marqueur : sa présence désactive l'instance unique.
///
/// Le réglage « instance unique » doit être connu avant l'ouverture de la base
/// de préférences — c'est justement elle qu'une seconde instance ne doit pas
/// ouvrir en même temps que la première. Un fichier vide dans le dossier de
/// données se lit sans aucune base.
const String multiInstanceMarkerName = 'multi-instance';

/// Vrai si l'instance unique est active (réglage par défaut).
bool singleInstanceEnabled(Directory dataDirectory) =>
    !File(p.join(dataDirectory.path, multiInstanceMarkerName)).existsSync();

/// Reflète le réglage dans le fichier marqueur.
Future<void> writeSingleInstancePreference(
  Directory dataDirectory, {
  required bool enabled,
}) async {
  final marker = File(p.join(dataDirectory.path, multiInstanceMarkerName));
  try {
    if (enabled) {
      if (await marker.exists()) await marker.delete();
    } else {
      await dataDirectory.create(recursive: true);
      await marker.writeAsString('');
    }
  } on FileSystemException {
    // Dossier en lecture seule : le réglage sera repris à la prochaine écriture.
  }
}

/// Message qu'une seconde instance envoie à la première : « ouvre ceci ».
class InstanceMessage {
  const InstanceMessage({required this.token, required this.args});

  /// Secret partagé via le fichier de verrou : seule une instance qui a pu le
  /// lire est autorisée à parler à la première.
  final String token;

  /// Arguments de la ligne de commande de la seconde instance.
  final List<String> args;

  /// Une ligne JSON, terminée par un saut de ligne.
  String encode() => '${jsonEncode({'token': token, 'args': args})}\n';

  /// Retourne `null` sur n'importe quelle ligne malformée : un client qui
  /// n'est pas OMNIA ne doit rien pouvoir déclencher.
  static InstanceMessage? decode(String line) {
    try {
      final json = jsonDecode(line.trim());
      if (json is! Map) return null;
      final token = json['token'];
      final args = json['args'];
      if (token is! String || args is! List) return null;
      if (args.any((a) => a is! String)) return null;
      return InstanceMessage(token: token, args: args.cast<String>());
    } on FormatException {
      return null;
    }
  }
}

/// Garantit qu'une seule fenêtre OMNIA tourne à la fois.
///
/// « Ouvrir avec → OMNIA » alors que l'application tourne déjà doit réutiliser
/// la fenêtre existante, pas en ouvrir une seconde. Le mécanisme est le même
/// sur Windows, Linux et macOS : la première instance écoute sur un port
/// local aléatoire et note ce port, avec un secret, dans un fichier de verrou.
/// Une seconde instance lit ce fichier, envoie ses arguments, attend un accusé
/// de réception et se termine.
///
/// Les sockets Unix ou D-Bus auraient été plus idiomatiques sous Linux, mais
/// ils n'existent pas sous Windows ; la boucle locale TCP, elle, existe
/// partout et ne s'expose pas au réseau.
class SingleInstanceService {
  SingleInstanceService({
    required this.directory,
    this.clock,
    this.grantForeground = allowForegroundWindow,
  });

  /// Dossier de données de l'application, où vit le fichier de verrou.
  final Directory directory;

  /// Surchargeable dans les tests.
  final DateTime Function()? clock;

  /// Cède le premier plan à la première instance, avant de lui confier des
  /// fichiers : elle doit pouvoir passer devant les autres fenêtres.
  /// Surchargeable dans les tests.
  final bool Function(int pid) grantForeground;

  static const lockFileName = 'instance.json';
  static const _acknowledgement = 'OK';

  File get lockFile => File(p.join(directory.path, lockFileName));

  ServerSocket? _server;
  String? _token;

  /// Tente de transmettre [args] à une instance déjà ouverte.
  ///
  /// Retourne `true` si une instance a accusé réception : l'appelant doit
  /// alors se terminer. Retourne `false` dans tous les autres cas — pas de
  /// verrou, verrou périmé (l'instance précédente a été tuée), pas de
  /// réponse — et l'appelant devient la première instance.
  ///
  /// Le délai ne pèse que si une instance tient le port sans répondre : sans
  /// instance, la connexion est refusée aussitôt. Il est large (2 s) parce
  /// qu'une première instance occupée — ou une machine chargée — peut mettre
  /// plus d'une demi-seconde à répondre, et qu'un délai trop court ouvrirait
  /// une seconde fenêtre.
  Future<bool> delegateToExisting(
    List<String> args, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final lock = _readLock();
    if (lock == null) return false;

    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lock.port,
        timeout: timeout,
      );
      // Une instance écoute bien sur ce port : c'est elle qui ouvrira le
      // fichier, c'est donc elle qui doit pouvoir passer au premier plan.
      final firstPid = lock.pid;
      if (firstPid != null) grantForeground(firstPid);
      socket.write(InstanceMessage(token: lock.token, args: args).encode());
      await socket.flush();

      final reply = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(timeout);
      return reply.trim() == _acknowledgement;
    } on Object {
      // Connexion refusée, délai dépassé, fichier corrompu : on démarre
      // normalement, et le verrou sera réécrit.
      return false;
    } finally {
      await socket?.close();
    }
  }

  /// Devient la première instance : écoute et écrit le fichier de verrou.
  ///
  /// [onArguments] est appelé à chaque instance secondaire qui se présente
  /// avec le bon secret.
  Future<void> serve(void Function(List<String> args) onArguments) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _token = _generateToken();

    await directory.create(recursive: true);
    await lockFile.writeAsString(
      jsonEncode({
        'port': server.port,
        'token': _token,
        'pid': pid,
        'since': (clock?.call() ?? DateTime.now()).toIso8601String(),
      }),
    );

    server.listen((client) => _handleClient(client, onArguments));
  }

  Future<void> _handleClient(
    Socket client,
    void Function(List<String> args) onArguments,
  ) async {
    try {
      final line = await client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));

      final message = InstanceMessage.decode(line);
      if (message == null || message.token != _token) {
        // Pas OMNIA, ou pas le bon secret : on ferme sans répondre.
        return;
      }
      client.write('$_acknowledgement\n');
      await client.flush();
      onArguments(message.args);
    } on Object {
      // Client parti trop tôt ou silencieux : rien à faire.
    } finally {
      await client.close();
    }
  }

  /// Port de la première instance, `null` si ce processus ne sert pas.
  int? get port => _server?.port;

  /// Libère le port et le verrou — seulement si ce processus les tient : une
  /// fenêtre secondaire (instance unique désactivée) ne doit pas effacer, en
  /// se fermant, le verrou de la première.
  Future<void> dispose() async {
    final serving = _server != null;
    await _server?.close();
    _server = null;
    if (!serving) return;
    try {
      if (await lockFile.exists()) await lockFile.delete();
    } on FileSystemException {
      // Le verrou sera considéré comme périmé par la prochaine instance.
    }
  }

  ({int port, String token, int? pid})? _readLock() {
    try {
      if (!lockFile.existsSync()) return null;
      final json = jsonDecode(lockFile.readAsStringSync());
      if (json is! Map) return null;
      final port = json['port'];
      final token = json['token'];
      final owner = json['pid'];
      if (port is! int || token is! String || port <= 0 || port > 65535) {
        return null;
      }
      return (port: port, token: token, pid: owner is int && owner > 0 ? owner : null);
    } on Object {
      return null;
    }
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
