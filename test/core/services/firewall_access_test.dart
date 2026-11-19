import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/services/firewall_access.dart';

/// Relit un script tel que PowerShell le recevrait derrière
/// `-EncodedCommand` : UTF-16 petit-boutiste, en base64.
String decode(String encoded) {
  final bytes = base64.decode(encoded);
  return String.fromCharCodes([
    for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
  ]);
}

/// Un faux lanceur de programmes : il note ce qu'on lui demande et répond ce
/// qu'on lui a dit. Aucun PowerShell ne tourne, aucun pare-feu n'est touché.
class _Lanceur {
  _Lanceur(this.reponses);

  final List<Object> reponses;
  final List<List<String>> appels = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    appels.add([executable, ...arguments]);
    final reponse = reponses[appels.length - 1];
    if (reponse is Exception) throw reponse;
    return ProcessResult(0, 0, reponse, '');
  }

  /// Le script du n-ième appel, décodé.
  String script(int n) => decode(appels[n].last);
}

void main() {
  group('Lecture du constat', () {
    test('pare-feu éteint : rien ne bloque, quelles que soient les règles', () {
      expect(
        WindowsFirewallAccess.parseCheck('OMNIA-FW on=0 allow=0 block=3'),
        FirewallState.open,
      );
    });

    test('une interdiction l’emporte sur une autorisation', () {
      // Le défaut que cela couvre : fermer sans répondre la boîte « le
      // pare-feu a bloqué certaines fonctionnalités » fait créer à Windows
      // des règles d'interdiction. Elles l'emportent sur toute autorisation,
      // celle de l'installateur comprise — qui semblait alors ne servir à
      // rien.
      expect(
        WindowsFirewallAccess.parseCheck('OMNIA-FW on=3 allow=1 block=2'),
        FirewallState.blocked,
      );
    });

    test('aucune autorisation sur le réseau en cours : bloqué', () {
      expect(
        WindowsFirewallAccess.parseCheck('OMNIA-FW on=3 allow=0 block=0'),
        FirewallState.blocked,
      );
    });

    test('une autorisation, aucune interdiction : ouvert', () {
      expect(
        WindowsFirewallAccess.parseCheck('bruit\r\nOMNIA-FW on=3 allow=1 block=0\r\n'),
        FirewallState.open,
      );
    });

    test('sans la ligne attendue, on ne sait pas — et on ne dit pas « bloqué »', () {
      // Annoncer un blocage à tort enverrait l'utilisateur ouvrir une porte
      // déjà ouverte, et douter d'une liaison qui marche.
      expect(WindowsFirewallAccess.parseCheck(''), FirewallState.unknown);
      expect(
        WindowsFirewallAccess.parseCheck("Le terme 'Get-NetFirewallProfile' n'est pas reconnu"),
        FirewallState.unknown,
      );
    });
  });

  group('Interrogation', () {
    test('le constat vient de PowerShell, sans droits ni modification', () async {
      final lanceur = _Lanceur(['OMNIA-FW on=3 allow=0 block=0']);
      final parefeu = WindowsFirewallAccess(
        program: r'C:\Program Files\OMNIA\omnia.exe',
        runner: lanceur.call,
      );

      expect(await parefeu.check(), FirewallState.blocked);
      expect(lanceur.appels, hasLength(1));
      expect(lanceur.appels.single.first, 'powershell.exe');
      final script = lanceur.script(0);
      expect(script, contains(r"'C:\Program Files\OMNIA\omnia.exe'"));
      // Interroger ne doit rien changer, ni rien demander.
      expect(script, isNot(contains('New-NetFirewallRule')));
      expect(script, isNot(contains('Remove-NetFirewallRule')));
      expect(script, isNot(contains('RunAs')));
    });

    test('PowerShell introuvable : on ne sait pas', () async {
      final lanceur = _Lanceur([const ProcessException('powershell.exe', [])]);
      final parefeu = WindowsFirewallAccess(program: 'omnia.exe', runner: lanceur.call);
      expect(await parefeu.check(), FirewallState.unknown);
    });

    test('une apostrophe dans le chemin ne casse rien et n’injecte rien', () async {
      final lanceur = _Lanceur(['OMNIA-FW on=3 allow=1 block=0']);
      final parefeu = WindowsFirewallAccess(
        program: r"C:\Users\O'Neil\omnia'; Remove-Item C:\ -Recurse; '.exe",
        runner: lanceur.call,
      );
      await parefeu.check();
      // L'apostrophe est doublée : le chemin reste une seule chaîne pour
      // PowerShell, quoi qu'il contienne.
      expect(
        lanceur.script(0),
        contains(r"'C:\Users\O''Neil\omnia''; Remove-Item C:\ -Recurse; ''.exe'"),
      );
    });
  });

  group('Autorisation', () {
    test('elle passe par la confirmation de Windows, puis se vérifie', () async {
      final lanceur = _Lanceur(['', 'OMNIA-FW on=3 allow=1 block=0']);
      final parefeu = WindowsFirewallAccess(
        program: r'C:\Program Files\OMNIA\omnia.exe',
        runner: lanceur.call,
      );

      expect(await parefeu.allow(), FirewallState.open);
      expect(lanceur.appels, hasLength(2));

      // Premier appel : un PowerShell lancé « en tant qu'administrateur ».
      final lancement = lanceur.script(0);
      expect(lancement, contains('-Verb RunAs'));
      final interieur = RegExp(r"'-EncodedCommand','([^']+)'").firstMatch(lancement);
      expect(interieur, isNotNull);
      final script = decode(interieur!.group(1)!);

      // La règle : OMNIA seul, TCP seul, sous le nom que l'installateur et
      // la désinstallation connaissent.
      expect(script, contains("New-NetFirewallRule -DisplayName 'OMNIA Connect'"));
      expect(script, contains('-Action Allow'));
      expect(script, contains('-Protocol TCP'));
      expect(script, contains(r"$p = 'C:\Program Files\OMNIA\omnia.exe'"));
      expect(script, contains(r'-Program $p'));
      // Les interdictions retirées sont celles de ce programme, pas d'un autre.
      expect(
        script,
        contains(r'Get-NetFirewallApplicationFilter -Program $p | Get-NetFirewallRule'),
      );
    });

    test('confirmation refusée : rien ne change, et on le constate', () async {
      final lanceur = _Lanceur([
        const ProcessException('powershell.exe', []),
        'OMNIA-FW on=3 allow=0 block=0',
      ]);
      final parefeu = WindowsFirewallAccess(program: 'omnia.exe', runner: lanceur.call);

      // On ne croit pas le code de retour du lancement : on regarde ce qu'il
      // en est après coup, et c'est toujours bloqué.
      expect(await parefeu.allow(), FirewallState.blocked);
      expect(lanceur.appels, hasLength(2));
    });
  });

  test('hors de Windows, OMNIA n’invente pas de diagnostic', () async {
    const parefeu = NoFirewallAccess();
    expect(await parefeu.check(), FirewallState.open);
    expect(await parefeu.allow(), FirewallState.open);
  });

  _linux();
}


/// Un lanceur pour le pare-feu de Linux : `systemctl` répond selon
/// [firewalld], `pkexec` selon [pkexecCode] ; chaque appel est noté.
class _LanceurLinux {
  _LanceurLinux({this.firewalld = false, this.pkexecCode = 0});

  final bool firewalld;
  final int pkexecCode;
  final List<List<String>> appels = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    appels.add([executable, ...arguments]);
    if (executable == 'systemctl') {
      return ProcessResult(0, firewalld ? 0 : 3, firewalld ? 'active\n' : 'inactive\n', '');
    }
    if (executable == 'pkexec') return ProcessResult(0, pkexecCode, '', '');
    return ProcessResult(0, 1, '', '');
  }
}

void _linux() {
  group('Pare-feu de Linux', () {
    late Directory dossier;
    late File ufw;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('omnia_parefeu_');
      ufw = File('${dossier.path}/ufw.conf');
    });
    tearDown(() => dossier.deleteSync(recursive: true));

    LinuxFirewallAccess parefeu(_LanceurLinux lanceur) => LinuxFirewallAccess(
          runner: lanceur.call,
          ufwConfig: ufw.path,
          markerDirectory: () async => dossier,
        );

    test('aucun pare-feu actif : rien ne bloque', () async {
      ufw.writeAsStringSync('ENABLED=no\n');
      expect(await parefeu(_LanceurLinux()).check(), FirewallState.open);
    });

    test('ufw actif, sans autorisation donnée : bloqué', () async {
      ufw.writeAsStringSync('# ufw.conf\nENABLED=yes\nLOGLEVEL=low\n');
      expect(await parefeu(_LanceurLinux()).check(), FirewallState.blocked);
    });

    test('autoriser passe par pkexec et ouvre le seul port d’OMNIA Connect', () async {
      ufw.writeAsStringSync('ENABLED=yes\n');
      final lanceur = _LanceurLinux();
      final acces = parefeu(lanceur);

      expect(await acces.allow(), FirewallState.open);
      expect(
        lanceur.appels.last,
        ['pkexec', 'ufw', 'allow', '41530/tcp', 'comment', 'OMNIA Connect'],
      );
      // L'autorisation est retenue : la vérification suivante la retrouve.
      expect(await acces.check(), FirewallState.open);
    });

    test('demande refusée : toujours bloqué, rien de retenu', () async {
      ufw.writeAsStringSync('ENABLED=yes\n');
      final acces = parefeu(_LanceurLinux(pkexecCode: 126));
      expect(await acces.allow(), FirewallState.blocked);
      expect(await acces.check(), FirewallState.blocked);
    });

    test('firewalld actif : le port est ouvert de façon permanente', () async {
      ufw.writeAsStringSync('ENABLED=no\n');
      final lanceur = _LanceurLinux(firewalld: true);
      final acces = parefeu(lanceur);

      expect(await acces.check(), FirewallState.blocked);
      expect(await acces.allow(), FirewallState.open);
      final commande = lanceur.appels.last;
      expect(commande.first, 'pkexec');
      expect(commande.last, contains('--add-port=41530/tcp'));
    });
  });
}
