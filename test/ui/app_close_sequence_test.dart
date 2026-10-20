import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/ui/app_close.dart';

void main() {
  group('Séquence de fermeture', () {
    // Des délais minuscules : ces tests vérifient le bornage, pas sa durée.
    const court = Duration(milliseconds: 10);

    /// Des étapes qui notent leur passage dans [journal], et délèguent à
    /// l'action fournie quand il y en a une.
    ExitSteps etapes({
      required List<String> journal,
      Future<void> Function()? silence,
      Future<void> Function()? saveState,
      Future<void> Function()? closeWindow,
      Future<void> Function()? stopEngine,
    }) {
      Future<void> noter(String nom, Future<void> Function()? action) async {
        journal.add(nom);
        if (action != null) await action();
      }

      return ExitSteps(
        silence: () => noter('son', silence),
        saveState: () => noter('état', saveState),
        closeWindow: () => noter('fenêtre', closeWindow),
        stopEngine: () => noter('moteur', stopEngine),
      );
    }

    test("l'ordre est le son, l'état, la fenêtre, puis le moteur", () async {
      final journal = <String>[];
      await runExitSequence(etapes(journal: journal), silence: court, save: court);
      expect(journal, ['son', 'état', 'fenêtre', 'moteur']);
    });

    test('une mise en silence qui ne rend jamais ne retient pas la fenêtre', () async {
      final journal = <String>[];
      // Le symptôme rapporté : libmpv ne rendait pas la main, la fenêtre
      // restait à l'écran et Windows la déclarait « ne répond pas ».
      final jamais = Completer<void>();
      await runExitSequence(
        etapes(journal: journal, silence: () => jamais.future),
        silence: court,
        save: court,
      );
      expect(journal, containsAllInOrder(['son', 'état', 'fenêtre']));
    });

    test('un enregistrement qui ne rend jamais ne retient pas la fenêtre', () async {
      final journal = <String>[];
      final jamais = Completer<void>();
      await runExitSequence(
        etapes(journal: journal, saveState: () => jamais.future),
        silence: court,
        save: court,
      );
      expect(journal, containsAllInOrder(['état', 'fenêtre']));
    });

    test('une étape qui échoue ne retient pas la fenêtre', () async {
      final journal = <String>[];
      await runExitSequence(
        etapes(
          journal: journal,
          silence: () => Future<void>.error(StateError('moteur absent')),
          saveState: () => Future<void>.error(StateError('disque plein')),
        ),
        silence: court,
        save: court,
      );
      expect(journal, containsAllInOrder(['son', 'état', 'fenêtre']));
    });

    test("l'état est écrit avant que la fenêtre ne se ferme", () async {
      final journal = <String>[];
      var ferme = false;
      await runExitSequence(
        etapes(
          journal: journal,
          saveState: () async {
            // Ce qu'on ne veut jamais perdre doit l'être avant la fenêtre.
            expect(ferme, isFalse);
          },
          closeWindow: () async => ferme = true,
        ),
        silence: court,
        save: court,
      );
      expect(ferme, isTrue);
    });

    test('le moteur est arrêté après la fenêtre, sans la retenir', () async {
      final journal = <String>[];
      final moteurBloque = Completer<void>();
      var moteurArrete = false;
      await runExitSequence(
        etapes(
          journal: journal,
          stopEngine: () => moteurBloque.future.then((_) => moteurArrete = true),
        ),
        silence: court,
        save: court,
      );
      // La séquence a rendu la main, donc la fenêtre est partie...
      expect(journal, ['son', 'état', 'fenêtre', 'moteur']);
      // ...alors que l'arrêt du moteur n'a toujours pas abouti.
      expect(moteurArrete, isFalse);
    });

    test('atMost rend la main au terme du délai, sans relancer la panne', () async {
      final jamais = Completer<void>();
      final montre = Stopwatch()..start();
      await atMost(() => jamais.future, court);
      montre.stop();
      expect(montre.elapsed, greaterThanOrEqualTo(court));
    });
  });
}
