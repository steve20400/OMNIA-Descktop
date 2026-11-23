import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.releaseNotes,
    this.downloadUrl,
    this.assetName,
    this.sizeBytes = 0,
    this.checksumsUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseNotes;
  final String? downloadUrl;
  final String? assetName;
  final int sizeBytes;

  /// Le fichier des empreintes SHA-256 publié avec la version : le paquet
  /// n'est exécuté que s'il y correspond.
  final String? checksumsUrl;
}

enum UpdateStatus {
  idle,
  checking,
  available,
  upToDate,
  downloading,
  readyToInstall,
  error,
}

class UpdateService {
  UpdateService({
    this.repo = 'steve20400/OMNIA-Descktop',
    // Version compilée dans l'application : la CI la transmet en --dart-define
    // (voir .github/workflows/ci.yml), si bien que la version installée et le
    // tag de la version publiée concordent — une mise à jour déjà installée
    // n'est donc pas reproposée en boucle. Hors CI, c'est la version du dépôt.
    this.currentVersion = const String.fromEnvironment(
      'OMNIA_VERSION',
      defaultValue: '0.1.0',
    ),
  });

  final String repo;
  final String currentVersion;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  UpdateInfo? _info;
  UpdateInfo? get info => _info;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  int _downloadedBytes = 0;
  int get downloadedBytes => _downloadedBytes;

  String? _downloadedFilePath;
  String? get downloadedFilePath => _downloadedFilePath;

  /// Vrai quand c'est à l'appelant de relancer l'application : sous Windows,
  /// l'installateur Inno la relance lui-même (`/RESTARTAPPLICATIONS`), sous
  /// Linux le script d'installation ne touche pas au processus en cours.
  bool _requiresRestart = false;
  bool get requiresRestart => _requiresRestart;

  /// Lanceur posé par la dernière installation réussie (Linux) : `null` tant
  /// qu'aucune installation n'a abouti.
  String? _installedLauncher;
  String? get installedLauncher => _installedLauncher;

  /// Une installation a déjà abouti : y revenir ne doit ni réinstaller ni
  /// relancer une seconde instance, seulement retenter la fermeture de
  /// l'ancienne si l'utilisateur l'avait annulée.
  bool _applied = false;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final StreamController<UpdateStatus> _statusController =
      StreamController<UpdateStatus>.broadcast();
  Stream<UpdateStatus> get statusStream => _statusController.stream;

  Future<UpdateInfo> checkForUpdates({String channel = 'stable'}) async {
    _status = UpdateStatus.checking;
    _errorMessage = null;
    _statusController.add(_status);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      client.userAgent = 'OMNIA-Updater/$currentVersion';

      final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close().timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final tagName = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
        final bodyText = json['body'] as String? ?? 'Améliorations et corrections de stabilité.';
        final assets = (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        String? targetUrl;
        String? assetName;
        String? checksumsUrl;
        int size = 0;
        final system = Platform.isWindows ? 'windows' : 'linux';

        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          final link = asset['browser_download_url'] as String?;
          if (name.startsWith('SHA256SUMS') && name.toLowerCase().contains(system)) {
            checksumsUrl ??= link;
            continue;
          }
          if (targetUrl != null) continue;
          if (Platform.isWindows && (name.endsWith('.exe') || name.contains('installateur'))) {
            targetUrl = link;
            assetName = name;
            size = (asset['size'] as num?)?.toInt() ?? 0;
          } else if (Platform.isLinux && (name.endsWith('.tar.gz') || name.contains('Linux'))) {
            targetUrl = link;
            assetName = name;
            size = (asset['size'] as num?)?.toInt() ?? 0;
          }
        }

        final isNewer = _compareVersions(tagName, currentVersion) > 0;
        _info = UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: tagName.isNotEmpty ? tagName : currentVersion,
          hasUpdate: isNewer,
          releaseNotes: bodyText,
          downloadUrl: targetUrl,
          assetName: assetName,
          sizeBytes: size,
          checksumsUrl: checksumsUrl,
        );

        _status = isNewer ? UpdateStatus.available : UpdateStatus.upToDate;
      } else {
        _info = UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          hasUpdate: false,
          releaseNotes: 'Votre application OMNIA est à jour.',
        );
        _status = UpdateStatus.upToDate;
      }
      client.close();
    } catch (_) {
      // Si hors-ligne ou requêtes limitées par l'API GitHub
      _info = UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        hasUpdate: false,
        releaseNotes: 'Vérification hors-ligne : version actuelle v$currentVersion conservée.',
      );
      _status = UpdateStatus.upToDate;
    }

    _statusController.add(_status);
    return _info!;
  }

  Future<bool> downloadUpdate({
    void Function(double progress, int downloaded, int total)? onProgress,
  }) async {
    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _downloadedBytes = 0;
    _statusController.add(_status);

    final url = _info?.downloadUrl;
    if (url == null || url.isEmpty) {
      // Plus de faux téléchargement qui « réussissait » sans rien installer :
      // on dit qu'il n'y a rien pour ce système.
      _fail('La dernière version ne contient pas de paquet pour ce système.');
      return false;
    }
    final source = Uri.tryParse(url);
    if (source == null || source.scheme != 'https') {
      _fail('Adresse de téléchargement refusée : elle doit être en https.');
      return false;
    }

    // Un dossier neuf, au nom tiré au hasard et lisible par ce compte seul :
    // dans le dossier temporaire commun, sous un nom prévisible, un autre
    // compte de la machine pouvait poser à l'avance le fichier qu'OMNIA
    // allait exécuter.
    Directory? folder;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      folder = await Directory.systemTemp.createTemp('omnia-update-');
      final fileName = _safeAssetName(
        _info?.assetName ?? (Platform.isWindows ? 'omnia_setup.exe' : 'omnia.tar.gz'),
      );
      final file = File('${folder.path}${Platform.pathSeparator}$fileName');

      final request = await client.getUrl(source);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('réponse ${response.statusCode}');
      }
      final announced = response.contentLength;
      final total = announced > 0 ? announced : (_info?.sizeBytes ?? 1);

      final digests = _DigestSink();
      final hashing = sha256.startChunkedConversion(digests);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          hashing.add(chunk);
          received += chunk.length;
          _downloadedBytes = received;
          _downloadProgress = (received / total).clamp(0.0, 1.0);
          onProgress?.call(_downloadProgress, received, total);
        }
      } finally {
        await sink.close();
        hashing.close();
      }

      final expectedSize = announced > 0 ? announced : (_info?.sizeBytes ?? 0);
      if (expectedSize > 0 && received != expectedSize) {
        throw StateError('paquet incomplet : $received octets sur $expectedSize');
      }

      // L'empreinte publiée avec la version, ou rien ne s'exécute.
      final expected = await _expectedDigest(client, fileName);
      if (expected == null) {
        throw StateError("l'empreinte de contrôle de la version est introuvable");
      }
      if (digests.value.toString() != expected) {
        throw StateError('le paquet ne correspond pas à son empreinte publiée');
      }

      _downloadedFilePath = file.path;
      _status = UpdateStatus.readyToInstall;
      _statusController.add(_status);
      return true;
    } catch (e) {
      try {
        if (folder != null && folder.existsSync()) await folder.delete(recursive: true);
      } on FileSystemException {
        // Le dossier restera dans le dossier temporaire : rien ne l'exécutera.
      }
      _fail('Mise à jour refusée : $e. Rien n’a été installé.');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// L'empreinte SHA-256 attendue pour [fileName], lue dans le fichier
  /// d'empreintes de la version (« empreinte  nom », une ligne par fichier).
  Future<String?> _expectedDigest(HttpClient client, String fileName) async {
    final url = _info?.checksumsUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final text = await response.transform(utf8.decoder).join();
      return checksumFor(text, fileName);
    } on Object {
      return null;
    }
  }

  /// L'empreinte de [fileName] dans [sums], au format de `sha256sum`
  /// (« empreinte  nom » ou « empreinte *nom »), en minuscules ; `null` si
  /// le fichier n'y figure pas.
  static String? checksumFor(String sums, String fileName) {
    for (final line in const LineSplitter().convert(sums)) {
      final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line.trim());
      if (match == null) continue;
      final name = match.group(2)!.split(RegExp(r'[\\/]')).last;
      if (name == fileName) return match.group(1)!.toLowerCase();
    }
    return null;
  }

  /// Le nom du paquet sans dossier : il vient du réseau.
  static String _safeAssetName(String name) {
    final base = name.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'[^A-Za-z0-9._+-]'), '_');
    return base.isEmpty || base.startsWith('.') ? 'omnia-update' : base;
  }

  /// Applique la mise à jour téléchargée. Retourne `true` une fois installée ;
  /// sinon [errorMessage] dit pourquoi.
  Future<bool> applyUpdate() async {
    if (_applied) return true;
    _errorMessage = null;

    final path = _downloadedFilePath;
    if (path == null || !File(path).existsSync()) {
      _fail('Paquet téléchargé introuvable : relancez le téléchargement.');
      return false;
    }

    if (Platform.isWindows) {
      // Inno Setup : installation en place sans désinstallation préalable, puis
      // relance de l'application une fois terminée.
      await Process.start(
        path,
        ['/SILENT', '/SP-', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      _requiresRestart = false;
      _applied = true;
      return true;
    }

    if (Platform.isLinux) return _applyLinuxArchive(path);

    _fail('Installation automatique indisponible sur cette plateforme.');
    return false;
  }

  /// Linux : l'actif publié est une archive tar.gz, pas un exécutable. Rendre
  /// le fichier exécutable puis le lancer — ce que faisait cette méthode — ne
  /// produisait donc rien : la mise à jour se téléchargeait sans jamais
  /// s'installer. On décompresse, puis on lance l'installateur sans droits
  /// d'administrateur que l'archive contient (déposé là par la CI), qui copie
  /// l'application, pose le lanceur et l'icône, et met à jour les associations.
  Future<bool> _applyLinuxArchive(String archivePath) async {
    try {
      final target = await Directory.systemTemp.createTemp('omnia-update-');
      final extracted =
          await Process.run('tar', ['-xzf', archivePath, '-C', target.path]);
      if (extracted.exitCode != 0) {
        _fail('Extraction impossible : ${_stderr(extracted)}');
        return false;
      }

      // L'archive contient un unique dossier, nommé d'après la version.
      final folders = target.listSync().whereType<Directory>().toList();
      final root = folders.isEmpty ? target.path : folders.first.path;

      File? installer;
      for (final name in const ['installer-omnia.sh', 'install.sh']) {
        final candidate = File('$root/$name');
        if (candidate.existsSync()) {
          installer = candidate;
          break;
        }
      }
      if (installer == null) {
        _fail("Aucun installateur dans l'archive téléchargée.");
        return false;
      }

      await Process.run('chmod', ['+x', installer.path]);
      final installed = await Process.run(
        installer.path,
        const <String>[],
        workingDirectory: root,
      );
      if (installed.exitCode != 0) {
        // Le script dit pourquoi : libmpv absent, binaire manquant à côté de
        // lui… autant le montrer plutôt que laisser croire à un succès.
        _fail('Installation refusée : ${_stderr(installed)}');
        return false;
      }

      // Le script pose un lanceur dans ~/.local/bin ; à défaut, le binaire
      // extrait reste utilisable pour redémarrer sur la nouvelle version.
      final home = Platform.environment['HOME'];
      final userLauncher = home == null ? null : File('$home/.local/bin/omnia');
      final extractedLauncher = File('$root/omnia');
      if (userLauncher != null && userLauncher.existsSync()) {
        _installedLauncher = userLauncher.path;
      } else if (extractedLauncher.existsSync()) {
        _installedLauncher = extractedLauncher.path;
      }
      _applied = true;

      final launcher = _installedLauncher;
      if (launcher == null) {
        // Installé, mais rien à démarrer : à l'utilisateur de relancer.
        _errorMessage =
            'Installé. Relancez OMNIA depuis le menu des applications.';
        _requiresRestart = false;
        return true;
      }

      // La nouvelle version démarre tout de suite ; l'ancienne se ferme ensuite
      // (c'est le rôle de requiresRestart, côté interface).
      await Process.start(launcher, const <String>[],
          mode: ProcessStartMode.detached);
      _requiresRestart = true;
      return true;
    } catch (e) {
      _fail("Échec de l'installation : $e");
      return false;
    }
  }

  static String _stderr(ProcessResult result) {
    final err = '${result.stderr}'.trim();
    return err.isEmpty ? '${result.stdout}'.trim() : err;
  }

  void _fail(String message) {
    _errorMessage = message;
    _status = UpdateStatus.error;
    _statusController.add(_status);
  }

  static int _compareVersions(String vA, String vB) {
    final partsA = vA.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partsB = vB.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final a = i < partsA.length ? partsA[i] : 0;
      final b = i < partsB.length ? partsB[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  void dispose() {
    _statusController.close();
  }
}

/// Recueille l'empreinte calculée au fil du téléchargement.
class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
