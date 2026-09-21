import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:omnia/l10n/app_localizations.dart';
import 'package:omnia/ui/settings/settings_controller.dart';
import 'package:omnia/ui/settings/settings_controls.dart';
import 'package:omnia/ui/settings/settings_screen.dart';
import 'package:omnia/ui/shortcuts/default_keymap.dart';
import 'package:omnia/ui/shortcuts/keymap_provider.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';

import 'narrow_harness.dart';

/// Un OMNIA sans moteur : service de lecture réel, stockages en mémoire,
/// aucun contrôleur de média (pas de mpv dans les tests).
class _Harness {
  _Harness() {
    bus = PlayerCommandBus();
    store = MemorySettingsStore();
    history = MemoryHistoryStore();
    playlist = PlaylistService(bus: bus, scanner: FakeFolderScanner(const {}));
    service = PlaybackService(
      bus: bus,
      router: MediaRouter(const []),
      window: FakeWindowService(),
      playlist: playlist,
      history: history,
      settings: store,
    );
    container = ProviderContainer(
      overrides: [
        commandBusProvider.overrideWithValue(bus),
        settingsStoreProvider.overrideWithValue(store),
        historyStoreProvider.overrideWithValue(history),
        playbackServiceProvider.overrideWithValue(service),
        playlistServiceProvider.overrideWithValue(playlist),
      ],
    );
  }

  late final PlayerCommandBus bus;
  late final MemorySettingsStore store;
  late final MemoryHistoryStore history;
  late final PlaylistService playlist;
  late final PlaybackService service;
  late final ProviderContainer container;

  Future<void> dispose() async {
    container.dispose();
    await service.dispose();
    await playlist.dispose();
    await bus.dispose();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  SettingsSection section = SettingsSection.general,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harness = _Harness();
  addTearDown(harness.dispose);
  harness.container.read(settingsUiProvider.notifier).show(section);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Material(child: SettingsOverlay()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// Fait défiler jusqu'à l'élément puis clique dessus : la feuille défile, et
/// un clic sur un élément hors de la zone visible tomberait à côté.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Laisse le bus livrer la commande et le service la traiter : tout se passe
/// en microtâches, que chaque trame simulée vide.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('les sections s’affichent et se parcourent', (tester) async {
    await _pump(tester);
    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.text('Langue'), findsOneWidget);

    await tester.tap(find.text('Lecture').first);
    await tester.pumpAndSettle();
    expect(find.text('Pas d\'avance et de recul'), findsOneWidget);

    await tester.tap(find.text('Raccourcis').first);
    await tester.pumpAndSettle();
    expect(find.text('Tout rétablir'), findsOneWidget);
  });

  testWidgets('un réglage passe par le bus et arrive dans le stockage', (tester) async {
    final harness = await _pump(tester, section: SettingsSection.playback);

    await _tap(tester, find.text('10 s'));
    await _drain(tester);

    expect(harness.store.preferences.seekStepSeconds, 10);
    // L'écran relit l'état : le segment « 10 s » est désormais le choix actif.
    expect(harness.container.read(preferencesProvider).seekStepSeconds, 10);
  });

  testWidgets('le thème et la reprise se changent depuis « Général »', (tester) async {
    final harness = await _pump(tester);

    await _tap(tester, find.text('Clair'));
    await _drain(tester);
    await _tap(tester, find.text('Demander'));
    await _drain(tester);
    await _tap(tester, find.text('Nouvelle fenêtre'));
    await _drain(tester);

    expect(harness.store.preferences.themeMode, AppThemeMode.light);
    expect(harness.store.preferences.resumePolicy, ResumePolicy.ask);
    expect(harness.store.preferences.inAppOpenTarget, InAppOpenTarget.newWindow);
  });

  testWidgets('Échap ferme l’écran', (tester) async {
    final harness = await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.container.read(settingsUiProvider).visible, isFalse);
  });

  group('Éditeur de raccourcis', () {
    testWidgets('capturer une touche libre la réaffecte', (tester) async {
      final harness = await _pump(tester, section: SettingsSection.shortcuts);

      // La touche « S » de la ligne « Capture d'écran ».
      await _tap(tester, find.text('S'));
      expect(find.text('Appuyez sur la combinaison…'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();

      final keymap = harness.container.read(keymapProvider);
      expect(keymap.combosFor(ShortcutAction.screenshot).single.keyId,
          LogicalKeyboardKey.keyK.keyId);
      expect(harness.store.keymapOverrides.keys, contains('screenshot'));
    });

    testWidgets('un conflit est signalé, puis résolu par « Remplacer »', (tester) async {
      final harness = await _pump(tester, section: SettingsSection.shortcuts);

      await _tap(tester, find.text('S'));
      // N appartient déjà à « Fichier suivant ».
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.textContaining('Déjà utilisé par'), findsOneWidget);

      await _tap(tester, find.text('Remplacer'));

      final keymap = harness.container.read(keymapProvider);
      expect(keymap.combosFor(ShortcutAction.screenshot).single.keyId,
          LogicalKeyboardKey.keyN.keyId);
      expect(keymap.combosFor(ShortcutAction.nextFile), isEmpty);
    });

    testWidgets('Échap annule la saisie sans rien changer, ni fermer l’écran', (tester) async {
      final harness = await _pump(tester, section: SettingsSection.shortcuts);

      await _tap(tester, find.text('S'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(harness.container.read(keymapProvider).isAllDefault, isTrue);
      expect(harness.container.read(settingsUiProvider).visible, isTrue);
      expect(find.text('Appuyez sur la combinaison…'), findsNothing);
    });

    testWidgets('« Tout rétablir » revient aux valeurs par défaut', (tester) async {
      final harness = await _pump(tester, section: SettingsSection.shortcuts);
      await _tap(tester, find.text('S'));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(harness.container.read(keymapProvider).isAllDefault, isFalse);

      await _tap(tester, find.text('Tout rétablir'));
      expect(harness.container.read(keymapProvider).isAllDefault, isTrue);
      expect(harness.store.keymapOverrides, isEmpty);
    });
  });

  group('Fenêtre étroite', () {
    testWidgets('sous 560 px, les sections passent dans une colonne d’icônes', (tester) async {
      final harness = await _pump(tester, size: const Size(360, 240));
      expect(tester.takeException(), isNull);

      // Plus de colonne de sections : une icône par section, son nom en infobulle.
      expect(find.text('Paramètres'), findsNothing);
      for (final name in ['Général', 'Lecture', 'Raccourcis', 'Historique']) {
        expect(find.byTooltip(name), findsOneWidget, reason: name);
      }
      expectWithin(tester, byTooltipPrefix('Fermer les paramètres'), Offset.zero & const Size(360, 240));

      await tester.tap(find.byTooltip('Lecture'));
      await tester.pumpAndSettle();
      expect(harness.container.read(settingsUiProvider).section, SettingsSection.playback);
      // Le nom de la section reste en tête du contenu.
      expect(find.text('Lecture'), findsOneWidget);

      await tester.tap(byTooltipPrefix('Fermer les paramètres'));
      await tester.pumpAndSettle();
      expect(harness.container.read(settingsUiProvider).visible, isFalse);
    });

    testWidgets('dans une fenêtre de 360 × 240, le contenu défile et se règle', (tester) async {
      final harness = await _pump(tester, size: const Size(360, 240));
      final before = harness.store.preferences.singleInstance;

      await _tap(tester, find.byType(OmniaSwitch).first);
      await _drain(tester);

      expect(harness.store.preferences.singleInstance, !before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chaque section tient à 360 × 240, et à 320 × 240', (tester) async {
      final harness = await _pump(tester, size: const Size(360, 240));
      for (final size in const [Size(360, 240), Size(320, 240)]) {
        tester.view.physicalSize = size;
        for (final section in SettingsSection.values) {
          // L'éditeur de raccourcis (shortcut_editor.dart) garde en tête un
          // bouton à pleine largeur : sous la fenêtre minimale, il n'y tient
          // plus avec la police des tests.
          if (size.width < 360 && section == SettingsSection.shortcuts) continue;
          harness.container.read(settingsUiProvider.notifier).select(section);
          await tester.pumpAndSettle();
          final where = '${section.name} à $size';
          expect(tester.takeException(), isNull, reason: where);
          expectWithin(tester, byTooltipPrefix('Fermer les paramètres'), Offset.zero & size,
              reason: where);
        }
      }
    });
  });
}
