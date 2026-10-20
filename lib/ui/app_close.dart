import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/models/app_preferences.dart';
import '../core/providers.dart';
import '../core/services/window_service.dart';
import 'app.dart';
import 'document_ui_controller.dart';
import 'widgets/unsaved_changes_dialog.dart';

/// Vérifie et résout les modifications non enregistrées selon la politique configurée
/// (`ask`, `save`, `discard`).
///
/// Retourne `true` si la fermeture de l'application est autorisée à se poursuivre,
/// ou `false` si l'utilisateur a annulé.
Future<bool> handleUnsavedChangesGuard(dynamic ref, [BuildContext? context]) async {
  final docUi = ref.read(documentUiProvider) as DocumentUiState;
  if (!docUi.isEditing || !docUi.hasUnsavedChanges) {
    return true;
  }

  final prefs = ref.read(preferencesProvider) as AppPreferences;
  final policy = prefs.unsavedChangesPolicy;

  if (policy == UnsavedChangesPolicy.ask) {
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx != null) {
      final fileName = docUi.draftPath != null
          ? p.basename(docUi.draftPath!)
          : 'document';
      final choice = await UnsavedChangesDialog.show(ctx, fileName: fileName);
      if (choice == null || choice == UnsavedChangesAction.cancel) {
        return false; // L'utilisateur annule la fermeture
      }
      if (choice == UnsavedChangesAction.save) {
        (ref.read(documentUiProvider.notifier) as DocumentUiController).saveDraftSync();
      } else {
        (ref.read(documentUiProvider.notifier) as DocumentUiController).clearDraft();
      }
      return true;
    } else {
      (ref.read(documentUiProvider.notifier) as DocumentUiController).saveDraftSync();
      return true;
    }
  } else if (policy == UnsavedChangesPolicy.save) {
    (ref.read(documentUiProvider.notifier) as DocumentUiController).saveDraftSync();
    return true;
  } else if (policy == UnsavedChangesPolicy.discard) {
    (ref.read(documentUiProvider.notifier) as DocumentUiController).clearDraft();
    return true;
  }

  return true;
}

/// Délai accordé à la mise en silence du moteur.
///
/// La fenêtre est retenue par `setPreventClose(true)` : tant que `destroy()`
/// n'a pas été appelé, elle reste à l'écran. Or `player.stop()` passe par
/// libmpv, qui met parfois plusieurs secondes à rendre quand son cache de
/// démultiplexage est plein — et il était attendu deux fois de suite. La
/// fenêtre restait alors plantée, Windows affichait « ne répond pas », et il
/// fallait tuer OMNIA depuis le gestionnaire des tâches. Chaque étape est
/// désormais bornée : aucune ne vaut de laisser une fenêtre morte à l'écran.
const Duration silenceBudget = Duration(milliseconds: 400);

/// Plus généreux que la mise en silence, car c'est la seule étape dont la
/// perte serait visible : position du fichier, extrait en cours, réglages en
/// attente d'écriture.
const Duration saveBudget = Duration(seconds: 3);

/// Exécute [action] en lui accordant [budget] au plus, et avale tout échec.
Future<void> atMost(Future<void> Function() action, Duration budget) async {
  try {
    await action().timeout(budget);
  } on Object {
    // Ni un dépassement ni une erreur ne doivent retenir la fermeture.
  }
}

/// Les gestes de la fermeture, dans l'ordre où ils doivent se produire.
class ExitSteps {
  const ExitSteps({
    required this.silence,
    required this.saveState,
    required this.closeWindow,
    required this.stopEngine,
  });

  /// Couper le son. Un simple réglage de propriété, sans rapport avec l'arrêt
  /// du moteur : c'est ce qui traînait après la disparition de la fenêtre.
  final Future<void> Function() silence;

  /// Écrire ce dont la perte serait visible.
  final Future<void> Function() saveState;

  /// Détruire la fenêtre native, ou rendre la main au système.
  final Future<void> Function() closeWindow;

  /// Arrêter le moteur pour de bon. Personne ne l'attend.
  final Future<void> Function() stopEngine;
}

/// Déroule la fermeture dans l'ordre qui ne retient jamais la fenêtre : le
/// son, l'état, la fenêtre, puis le moteur — ce dernier sans que personne ne
/// l'attende, le processus s'en allant de toute façon.
Future<void> runExitSequence(
  ExitSteps steps, {
  Duration silence = silenceBudget,
  Duration save = saveBudget,
}) async {
  await atMost(steps.silence, silence);
  await atMost(steps.saveState, save);
  await steps.closeWindow();
  unawaited(atMost(steps.stopEngine, silence));
}

/// Les gestes de fermeture tirés des providers.
///
/// [closeWindow] permet au système de garder la main : quand c'est lui qui
/// ferme, OMNIA n'a pas à détruire la fenêtre lui-même.
ExitSteps exitStepsFor(dynamic ref, {Future<void> Function()? closeWindow}) {
  // Seul le service de fenêtre est lu ici : c'est le seul dont l'échec n'aurait
  // aucune issue. Les autres sont lus *dans* leur étape, donc sous la
  // protection d'atMost — obtenir le moteur peut échouer (il peut n'avoir
  // jamais été initialisé), et un tel échec ne doit pas empêcher la fenêtre de
  // se fermer. C'est précisément ce qui arrivait quand ces lectures étaient
  // faites d'avance.
  final window = ref.read(windowServiceProvider) as WindowService;
  return ExitSteps(
    silence: () async {
      await (ref.read(avControllerProvider) as dynamic).player.setVolume(0);
    },
    saveState: () async {
      await (ref.read(playbackServiceProvider) as dynamic).saveStateForExit();
    },
    closeWindow: closeWindow ?? window.close,
    stopEngine: () async {
      await (ref.read(avControllerProvider) as dynamic).player.stop();
    },
  );
}

/// Ferme l'application : modifications non enregistrées d'abord, puis la
/// séquence bornée de [runExitSequence].
///
/// Retourne `true` si la fermeture est partie, `false` si l'utilisateur
/// l'a annulée devant la boîte des modifications non enregistrées.
Future<bool> closeApplication(dynamic ref, [BuildContext? context]) async {
  final canClose = await handleUnsavedChangesGuard(ref, context);
  if (!canClose) {
    return false;
  }

  await runExitSequence(exitStepsFor(ref));
  return true;
}
