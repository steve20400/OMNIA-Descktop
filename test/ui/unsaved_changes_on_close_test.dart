import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/app_close.dart';
import 'package:omnia/ui/document_ui_controller.dart';
import 'package:omnia/ui/widgets/unsaved_changes_dialog.dart';
import 'package:path/path.dart' as p;

import 'narrow_harness.dart';

void main() {
  group('Gestion des modifications non enregistrées à la fermeture', () {
    late Directory tempDir;
    late String filePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('omnia_close_test');
      filePath = p.join(tempDir.path, 'notes.txt');
      File(filePath).writeAsStringSync('Original file text');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('Politique ask : clic sur Annuler annule la fermeture', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
      );
      harness.attach(tester);

      // Activer l'édition et simuler des modifications
      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Modified text not saved',
          );

      late BuildContext testContext;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Déclencher la fermeture en tâche asynchrone
      bool? closedResult;
      closeApplication(harness.container, testContext).then((res) => closedResult = res);
      await tester.pumpAndSettle();

      // La boîte de dialogue doit s'afficher
      expect(find.byType(UnsavedChangesDialog), findsOneWidget);
      expect(find.text('Enregistrer les modifications ?'), findsOneWidget);

      // Clic sur Annuler
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // Fermeture annulée
      expect(closedResult, isFalse);
      expect(harness.window.closed, isFalse);
      // Le fichier d'origine n'a pas été écrasé
      expect(File(filePath).readAsStringSync(), 'Original file text');
      // Le brouillon reste conservé
      expect(harness.container.read(documentUiProvider).hasUnsavedChanges, isTrue);
    });

    testWidgets('Politique ask : clic sur Enregistrer sauvegarde puis ferme', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Modified text to be saved',
          );

      late BuildContext testContext;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      bool? closedResult;
      closeApplication(harness.container, testContext).then((res) => closedResult = res);
      await tester.pumpAndSettle();

      expect(find.byType(UnsavedChangesDialog), findsOneWidget);

      // Clic sur Enregistrer
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(closedResult, isTrue);
      expect(harness.window.closed, isTrue);
      // Le fichier a été mis à jour
      expect(File(filePath).readAsStringSync(), 'Modified text to be saved');
    });

    testWidgets('Politique ask : clic sur Ne pas enregistrer ferme sans sauvegarder', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Discarded modifications',
          );

      late BuildContext testContext;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      bool? closedResult;
      closeApplication(harness.container, testContext).then((res) => closedResult = res);
      await tester.pumpAndSettle();

      expect(find.byType(UnsavedChangesDialog), findsOneWidget);

      // Clic sur Ne pas enregistrer
      await tester.tap(find.text('Ne pas enregistrer'));
      await tester.pumpAndSettle();

      expect(closedResult, isTrue);
      expect(harness.window.closed, isTrue);
      // Le fichier original reste intact
      expect(File(filePath).readAsStringSync(), 'Original file text');
    });

    testWidgets('Politique save : enregistre automatiquement et ferme sans dialogue', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
        overrides: [
          preferencesProvider.overrideWith(
            () => _TestPreferences(
              const AppPreferences(
                unsavedChangesPolicy: UnsavedChangesPolicy.save,
              ),
            ),
          ),
        ],
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Auto saved on close',
          );

      late BuildContext testContext;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final res = await closeApplication(
        harness.container,
        testContext,
      );

      // Aucun dialogue affiché
      expect(find.byType(UnsavedChangesDialog), findsNothing);
      expect(res, isTrue);
      expect(harness.window.closed, isTrue);
      expect(File(filePath).readAsStringSync(), 'Auto saved on close');
    });

    testWidgets('Politique discard : ferme directement sans enregistrer ni afficher de dialogue', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
        overrides: [
          preferencesProvider.overrideWith(
            () => _TestPreferences(
              const AppPreferences(
                unsavedChangesPolicy: UnsavedChangesPolicy.discard,
              ),
            ),
          ),
        ],
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Ignored on close',
          );

      late BuildContext testContext;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final res = await closeApplication(
        harness.container,
        testContext,
      );

      expect(find.byType(UnsavedChangesDialog), findsNothing);
      expect(res, isTrue);
      expect(harness.window.closed, isTrue);
      expect(File(filePath).readAsStringSync(), 'Original file text');
    });

    testWidgets('Mode Mini-lecteur compact : le dialogue s’affiche et fonctionne sans débordement', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
          miniPlayer: true,
        ),
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Mini player modifications',
          );

      late BuildContext testContext;
      // Simuler une surface compacte typique d’un mini-lecteur (380x280)
      tester.view.physicalSize = const Size(380, 280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      bool? closedResult;
      closeApplication(harness.container, testContext).then((res) => closedResult = res);
      await tester.pumpAndSettle();

      expect(find.byType(UnsavedChangesDialog), findsOneWidget);
      expect(find.text('Enregistrer les modifications ?'), findsOneWidget);

      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(closedResult, isTrue);
      expect(harness.window.closed, isTrue);
      expect(File(filePath).readAsStringSync(), 'Mini player modifications');
    });

    testWidgets('Demande de fermeture native OS (Alt+F4 / taskbar) : interceptée et gardée', (tester) async {
      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);
      harness.container.read(documentUiProvider.notifier).setDraft(
            path: filePath,
            text: 'Intercepted OS close',
          );

      late BuildContext testContext;
      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          Builder(
            builder: (ctx) {
              testContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Écouter closeRequests et router vers closeApplication comme dans OmniaApp
      harness.window.closeRequests.listen((_) {
        closeApplication(harness.container, testContext);
      });

      // Émettre une demande de fermeture native OS
      harness.window.emitCloseRequest();
      await tester.pumpAndSettle();

      // Le dialogue modal de confirmation doit surgir
      expect(find.byType(UnsavedChangesDialog), findsOneWidget);
      expect(find.text('Enregistrer les modifications ?'), findsOneWidget);

      // Clic sur Annuler
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // La fenêtre n'est pas fermée
      expect(harness.window.closed, isFalse);
      expect(File(filePath).readAsStringSync(), 'Original file text');
    });
  });
}

class _TestPreferences extends PreferencesNotifier {
  _TestPreferences(this._prefs);
  final AppPreferences _prefs;

  @override
  AppPreferences build() => _prefs;
}
