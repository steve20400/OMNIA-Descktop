import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Ce que le pare-feu du système fait des connexions qui arrivent vers OMNIA.
enum FirewallState {
  /// Rien ne s'y oppose — ou ce système n'a pas de pare-feu qu'OMNIA sache
  /// interroger.
  open,

  /// Les connexions entrantes seront refusées : aucune règle ne les autorise
  /// sur le réseau en cours, ou une règle les interdit.
  blocked,

  /// Impossible de le savoir. On n'affirme alors rien.
  unknown,
}

/// Accès d'OMNIA Connect à travers le pare-feu du système.
///
/// OMNIA Connect ouvre un serveur local que l'appareil d'en face vient
/// joindre. Quand le pare-feu refuse cette connexion, elle n'arrive jamais
/// jusqu'à l'application : il n'y a rien à accepter, rien à afficher, et
/// l'appairage échoue sans que rien ne dise pourquoi. Le seul remède connu
/// était de couper le pare-feu tout entier — c'est-à-dire d'exposer toute la
/// machine pour laisser passer une application.
///
/// D'où ce service : savoir, avant l'appairage, si la porte est fermée, et
/// l'ouvrir pour OMNIA seul.
abstract interface class FirewallAccess {
  /// Interroge le pare-feu. Ne modifie rien et ne demande aucun droit.
  Future<FirewallState> check();

  /// Autorise OMNIA, puis rend l'état constaté après coup.
  ///
  /// Le système demande sa confirmation à l'utilisateur : rien n'est changé
  /// sans elle, et un refus laisse tout en l'état.
  Future<FirewallState> allow();
}

/// Aucun pare-feu à interroger : hors de Windows, OMNIA ne sait pas le faire,
/// et n'invente pas de diagnostic.
class NoFirewallAccess implements FirewallAccess {
  const NoFirewallAccess();

  @override
  Future<FirewallState> check() async => FirewallState.open;

  @override
  Future<FirewallState> allow() async => FirewallState.open;
}

/// Lance un programme et rend son résultat. Injectable : les tests n'ont pas
/// de PowerShell, et ne doivent surtout pas toucher au pare-feu de la machine
/// qui les exécute.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Le pare-feu de Windows, interrogé par PowerShell.
///
/// Par les commandes du module de sécurité réseau plutôt que par `netsh` :
/// `netsh` répond dans la langue du système, et un diagnostic qui dépend de
/// la traduction de « Nom de la règle » ne tient pas. Les scripts rendent une
/// ligne de jetons, la même partout.
class WindowsFirewallAccess implements FirewallAccess {
  WindowsFirewallAccess({String? program, ProcessRunner? runner})
      : program = program ?? Platform.resolvedExecutable,
        _run = runner ?? Process.run;

  /// Le programme à autoriser : celui qui tourne, et non un chemin supposé.
  /// Une règle de pare-feu vaut pour un fichier précis — celle que pose
  /// l'installateur ne couvre pas une copie portable lancée d'ailleurs.
  final String program;

  final ProcessRunner _run;

  /// Nom de la règle. Le même que celui de l'installateur, pour que la
  /// désinstallation l'emporte aussi.
  static const String ruleName = 'OMNIA Connect';

  /// Au-delà, PowerShell est tenu pour muet. Son démarrage et le chargement
  /// du module prennent quelques secondes sur une machine modeste ; la
  /// confirmation d'administrateur, elle, attend l'utilisateur.
  static const Duration checkBudget = Duration(seconds: 25);
  static const Duration allowBudget = Duration(minutes: 2);

  /// Le chemin entre apostrophes PowerShell, où seule l'apostrophe se double.
  String get _quoted => "'${program.replaceAll("'", "''")}'";

  /// Script d'interrogation.
  ///
  /// Trois questions : le pare-feu est-il actif ; une règle interdit-elle
  /// OMNIA ; une règle l'autorise-t-elle **sur le réseau en cours**. Cette
  /// dernière précision compte : Windows classe « public » un réseau qu'il
  /// ne connaît pas — le point d'accès d'un téléphone, typiquement — et une
  /// autorisation limitée aux réseaux privés n'y vaut rien.
  String get checkScript => '''
\$ErrorActionPreference = 'SilentlyContinue'
\$p = $_quoted
\$on = @(Get-NetFirewallProfile | Where-Object { \$_.Enabled.ToString() -eq 'True' }).Count
\$cats = @(Get-NetConnectionProfile | ForEach-Object { \$_.NetworkCategory.ToString() })
\$rules = @(Get-NetFirewallApplicationFilter -Program \$p | Get-NetFirewallRule | Where-Object { \$_.Enabled.ToString() -eq 'True' -and \$_.Direction.ToString() -eq 'Inbound' })
\$block = @(\$rules | Where-Object { \$_.Action.ToString() -eq 'Block' }).Count
\$allow = 0
foreach (\$r in @(\$rules | Where-Object { \$_.Action.ToString() -eq 'Allow' })) {
  \$prof = \$r.Profile.ToString()
  if (\$prof -eq 'Any') { \$allow++; continue }
  \$covers = \$true
  foreach (\$c in \$cats) {
    \$name = if (\$c -eq 'DomainAuthenticated') { 'Domain' } else { \$c }
    if (\$prof -notmatch \$name) { \$covers = \$false }
  }
  if (\$covers) { \$allow++ }
}
Write-Output "OMNIA-FW on=\$on allow=\$allow block=\$block"
''';

  /// Script d'autorisation, exécuté avec les droits d'administrateur.
  ///
  /// Les règles d'interdiction visant OMNIA sont retirées d'abord : Windows
  /// en crée quand on ferme sans répondre sa boîte « le pare-feu a bloqué
  /// certaines fonctionnalités », et une interdiction l'emporte toujours sur
  /// une autorisation — celle de l'installateur comprise. Seules celles de ce
  /// programme sont touchées.
  ///
  /// La règle posée vaut pour tous les réseaux, mais pour le seul TCP et le
  /// seul programme OMNIA : c'est tout ce dont OMNIA Connect a besoin.
  String get allowScript => '''
\$ErrorActionPreference = 'SilentlyContinue'
\$p = $_quoted
Get-NetFirewallApplicationFilter -Program \$p | Get-NetFirewallRule | Where-Object { \$_.Direction.ToString() -eq 'Inbound' -and \$_.Action.ToString() -eq 'Block' } | Remove-NetFirewallRule
Remove-NetFirewallRule -DisplayName '$ruleName'
New-NetFirewallRule -DisplayName '$ruleName' -Direction Inbound -Action Allow -Program \$p -Protocol TCP -Profile Any | Out-Null
''';

  /// Ce que dit la ligne de jetons rendue par [checkScript].
  ///
  /// Sans cette ligne — PowerShell absent, module manquant, sortie tronquée —
  /// on ne sait rien, et on le dit : annoncer « bloqué » à tort enverrait
  /// l'utilisateur ouvrir une porte déjà ouverte.
  static FirewallState parseCheck(String output) {
    final match = RegExp(r'OMNIA-FW on=(\d+) allow=(\d+) block=(\d+)')
        .firstMatch(output);
    if (match == null) return FirewallState.unknown;
    final on = int.parse(match.group(1)!);
    final allow = int.parse(match.group(2)!);
    final block = int.parse(match.group(3)!);
    // Pare-feu éteint : rien n'est filtré, quelles que soient les règles.
    if (on == 0) return FirewallState.open;
    // Une interdiction l'emporte sur toute autorisation.
    if (block > 0) return FirewallState.blocked;
    return allow > 0 ? FirewallState.open : FirewallState.blocked;
  }

  /// Un script tel que PowerShell l'attend derrière `-EncodedCommand` :
  /// UTF-16 petit-boutiste, en base64. Aucun guillemet ne traverse ainsi la
  /// ligne de commande — un chemin qui en contient ne peut rien casser, ni
  /// rien injecter.
  static String encode(String script) {
    final units = script.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      bytes[i * 2] = units[i] & 0xFF;
      bytes[i * 2 + 1] = units[i] >> 8;
    }
    return base64.encode(bytes);
  }

  static const List<String> _quiet = ['-NoProfile', '-NonInteractive'];

  @override
  Future<FirewallState> check() async {
    try {
      final result = await _run(
        'powershell.exe',
        [..._quiet, '-EncodedCommand', encode(checkScript)],
      ).timeout(checkBudget);
      return parseCheck(result.stdout.toString());
    } on Object {
      // PowerShell introuvable, ou muet : on ne sait pas.
      return FirewallState.unknown;
    }
  }

  @override
  Future<FirewallState> allow() async {
    // Un second PowerShell, lancé « en tant qu'administrateur » : c'est ce
    // qui fait apparaître la confirmation de Windows. Refusée, elle fait
    // échouer ce lancement et rien n'est modifié.
    final inner = encode(allowScript);
    final outer = "Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait "
        '-WindowStyle Hidden -ArgumentList '
        "'-NoProfile','-NonInteractive','-EncodedCommand','$inner'";
    try {
      await _run(
        'powershell.exe',
        [..._quiet, '-EncodedCommand', encode(outer)],
      ).timeout(allowBudget);
    } on Object {
      // Refus, délai dépassé, PowerShell absent : le constat qui suit dira
      // ce qu'il en est vraiment.
    }
    // On ne croit pas le code de retour : on regarde.
    return check();
  }
}

/// Le pare-feu de Linux : ufw (Ubuntu, Debian) ou firewalld (Fedora).
///
/// L'interroger en détail demande les droits d'administrateur — `ufw status`
/// refuse de répondre sinon. On se contente donc de savoir s'il est actif,
/// par sa configuration (lisible par tous) ou par systemd. Actif, il refuse
/// par défaut toute connexion entrante : sans trace d'une autorisation
/// accordée à OMNIA, il est tenu pour bloquant.
///
/// L'autorisation passe par `pkexec`, qui affiche la demande de mot de passe
/// du bureau : rien ne change sans elle. Elle ouvre le seul port d'OMNIA
/// Connect, en TCP — pas toute la machine.
class LinuxFirewallAccess implements FirewallAccess {
  LinuxFirewallAccess({
    this.port = 41530,
    ProcessRunner? runner,
    this.ufwConfig = '/etc/ufw/ufw.conf',
    required this.markerDirectory,
  }) : _run = runner ?? Process.run;

  /// Port d'écoute d'OMNIA Connect.
  final int port;

  final ProcessRunner _run;

  /// Configuration d'ufw, où `ENABLED=yes` dit qu'il filtre.
  final String ufwConfig;

  /// Dossier où OMNIA note l'autorisation obtenue : sans droits, il ne peut
  /// pas relire les règles d'ufw pour la retrouver.
  final Future<Directory?> Function() markerDirectory;

  static const Duration checkBudget = Duration(seconds: 10);
  static const Duration allowBudget = Duration(minutes: 2);

  bool _ufwEnabled() {
    try {
      return File(ufwConfig)
          .readAsLinesSync()
          .any((line) => line.trim().toLowerCase() == 'enabled=yes');
    } on Object {
      return false;
    }
  }

  Future<bool> _firewalldActive() async {
    try {
      final result = await _run('systemctl', ['is-active', 'firewalld']).timeout(checkBudget);
      return result.stdout.toString().trim() == 'active';
    } on Object {
      return false;
    }
  }

  Future<File?> _marker() async {
    final directory = await markerDirectory();
    if (directory == null) return null;
    return File('${directory.path}${Platform.pathSeparator}pare-feu-$port.autorise');
  }

  @override
  Future<FirewallState> check() async {
    final ufw = _ufwEnabled();
    if (!ufw && !await _firewalldActive()) return FirewallState.open;
    final marker = await _marker();
    if (marker != null && marker.existsSync()) return FirewallState.open;
    return FirewallState.blocked;
  }

  /// La commande lancée avec les droits d'administrateur, selon le pare-feu.
  Future<List<String>?> allowCommand() async {
    if (_ufwEnabled()) return ['ufw', 'allow', '$port/tcp', 'comment', 'OMNIA Connect'];
    if (await _firewalldActive()) {
      return [
        'sh',
        '-c',
        'firewall-cmd --permanent --add-port=$port/tcp && firewall-cmd --reload',
      ];
    }
    return null;
  }

  @override
  Future<FirewallState> allow() async {
    final command = await allowCommand();
    if (command == null) return FirewallState.open;
    try {
      final result = await _run('pkexec', command).timeout(allowBudget);
      // 126 : demande refusée ; 127 : pkexec absent ou non autorisé.
      if (result.exitCode == 0) {
        final marker = await _marker();
        if (marker != null) {
          await marker.parent.create(recursive: true);
          await marker.writeAsString('OMNIA Connect autorisé sur le port $port/tcp\n');
        }
        return FirewallState.open;
      }
    } on Object {
      // Refus, délai dépassé : rien n'a changé.
    }
    return check();
  }
}
