import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/controllers/text_controller.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/ui/document_ui_controller.dart';
import 'package:omnia/ui/widgets/text_view.dart';
import 'package:path/path.dart' as p;

import 'narrow_harness.dart';

void main() {
  group('Sauvegarde automatique dans TextView', () {
    late Directory tempDir;
    late String filePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('omnia_autosave_test');
      filePath = p.join(tempDir.path, 'sample.txt');
      File(filePath).writeAsStringSync('Initial content');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('enregistre automatiquement après le délai d\'inactivité (debounce)', (tester) async {
      final doc = TextDocument(
        path: filePath,
        name: 'sample.txt',
        isMarkdown: false,
        text: 'Initial content',
      );

      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
        overrides: [
          preferencesProvider.overrideWith(
            () => _TestPreferences(
              const AppPreferences(
                docAutoSave: true,
                docAutoSaveIntervalSeconds: 1, // 1 seconde pour le test
              ),
            ),
          ),
        ],
      );
      harness.attach(tester);

      // Activer le mode édition
      harness.container.read(documentUiProvider.notifier).setEditing(true);

      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          TextView(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      // Saisir du texte dans le champ
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Updated content with auto-save');
      await tester.pump();

      // Des modifications non enregistrées sont détectées
      expect(harness.container.read(documentUiProvider).hasUnsavedChanges, isTrue);
      // Le fichier n'est pas encore écrit sur disque immédiatement (temporisation)
      expect(File(filePath).readAsStringSync(), 'Initial content');

      // Avancer le temps de 1.1s pour déclencher la sauvegarde automatique
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();

      // Le fichier a été automatiquement enregistré sur disque
      expect(File(filePath).readAsStringSync(), 'Updated content with auto-save');
      // Le drapeau de modifications est remis à false
      expect(harness.container.read(documentUiProvider).hasUnsavedChanges, isFalse);
    });

    testWidgets('enregistre immédiatement lors du passage en lecture seule', (tester) async {
      final doc = TextDocument(
        path: filePath,
        name: 'sample.txt',
        isMarkdown: false,
        text: 'Initial content',
      );

      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);

      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          TextView(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Content before toggling view');
      await tester.pump();

      expect(harness.container.read(documentUiProvider).hasUnsavedChanges, isTrue);

      // Basculer en lecture seule
      harness.container.read(documentUiProvider.notifier).setEditing(false);
      await tester.pump();
      await tester.pumpAndSettle();

      // Le fichier a été immédiatement écrit sur disque
      expect(File(filePath).readAsStringSync(), 'Content before toggling view');
      expect(harness.container.read(documentUiProvider).hasUnsavedChanges, isFalse);
    });

    testWidgets('sauvegarde synchrone lors de la destruction (dispose) du composant', (tester) async {
      final doc = TextDocument(
        path: filePath,
        name: 'sample.txt',
        isMarkdown: false,
        text: 'Initial content',
      );

      final harness = LeafHarness(
        state: PlaybackState(
          file: MediaFile(path: filePath, type: MediaType.text),
        ),
      );
      harness.attach(tester);

      harness.container.read(documentUiProvider.notifier).setEditing(true);

      await tester.pumpWidget(
        omniaTestApp(
          harness.container,
          TextView(document: doc),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Emergency unsaved changes');
      await tester.pump();

      // Démonter brusquement le widget (ex. fermeture de fenêtre ou changement de vue)
      await tester.pumpWidget(omniaTestApp(harness.container, const SizedBox.shrink()));
      await tester.pumpAndSettle();

      // Le fichier doit être sauvé sur disque grâce à la sauvegarde d'urgence dans dispose()
      expect(File(filePath).readAsStringSync(), 'Emergency unsaved changes');
    });
  });
}

class _TestPreferences extends PreferencesNotifier {
  _TestPreferences(this._prefs);
  final AppPreferences _prefs;

  @override
  AppPreferences build() => _prefs;
}
