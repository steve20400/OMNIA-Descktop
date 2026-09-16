// Outils communs aux tests des écrans étroits : tailles de fenêtre,
// application minimale, et un OMNIA sans moteur ni stockage, où l'état de
// lecture est fixé d'avance et chaque commande émise est relevée.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:omnia/l10n/app_localizations.dart';
import 'package:omnia/ui/osd/osd_controller.dart';
import 'package:omnia/ui/osd/osd_message.dart';
import 'package:omnia/ui/recent_files.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';

/// Largeurs parcourues : fenêtre d'aujourd'hui, fenêtre moyenne, seuil des
/// présentations compactes, fenêtre minimale, et en deçà.
const narrowWidths = <double>[1200, 800, 480, 360, 320];

/// État de lecture fixé d'avance, sans service de lecture derrière.
class FixedPlaybackState extends PlaybackStateNotifier {
  FixedPlaybackState(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

/// Préférences par défaut, en français.
class FixedPreferences extends PreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences(language: AppLanguage.fr);
}

/// Aucun fichier récent, sans historique derrière.
class NoRecentFiles extends RecentFilesNotifier {
  @override
  List<RecentFile> build() => const [];
}

/// Message OSD fixé d'avance, sans bus à écouter.
class FixedOsd extends OsdController {
  FixedOsd(this.message);

  final OsdMessage? message;

  @override
  OsdMessage? build() => message;
}

/// Un conteneur de providers pour les widgets feuilles : état de lecture
/// fixé, réglages en mémoire, fenêtre factice, et un bus dont chaque
/// commande est relevée dans [commands].
class LeafHarness {
  LeafHarness({PlaybackState state = const PlaybackState(), List<Override> overrides = const []}) {
    _subscription = bus.commands.listen(commands.add);
    container = ProviderContainer(
      overrides: [
        commandBusProvider.overrideWithValue(bus),
        settingsStoreProvider.overrideWithValue(MemorySettingsStore()),
        windowServiceProvider.overrideWithValue(window),
        playbackStateProvider.overrideWith(() => FixedPlaybackState(state)),
        preferencesProvider.overrideWith(FixedPreferences.new),
        recentFilesProvider.overrideWith(NoRecentFiles.new),
        ...overrides,
      ],
    );
  }

  final PlayerCommandBus bus = PlayerCommandBus();
  final FakeWindowService window = FakeWindowService();
  final List<PlayerCommand> commands = [];
  late final ProviderContainer container;
  late final StreamSubscription<PlayerCommand> _subscription;

  /// Prépare la fenêtre de test (densité 1) et range tout en fin de test.
  void attach(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(dispose);
  }

  Future<void> dispose() async {
    container.dispose();
    await _subscription.cancel();
    await bus.dispose();
  }
}

/// L'application minimale autour de [child] : thème sombre, français, un
/// Material au-dessus.
Widget omniaTestApp(ProviderContainer container, Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildOmniaTheme(Brightness.dark),
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(child: child),
      ),
    );

/// Donne à la fenêtre de test la taille [size] et laisse l'écran se refaire.
Future<void> resizeWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

/// Les widgets dont l'infobulle commence par [prefix] : l'infobulle peut
/// porter le raccourci à la suite du libellé.
Finder byTooltipPrefix(String prefix) => find.byWidgetPredicate(
      (widget) => widget is Tooltip && (widget.message?.startsWith(prefix) ?? false),
      description: 'infobulle « $prefix… »',
    );

/// L'élément trouvé est entièrement dans [bounds] : ni rogné, ni hors d'atteinte.
void expectWithin(WidgetTester tester, Finder finder, Rect bounds, {String? reason}) {
  final rect = tester.getRect(finder);
  // Demi-pixel de tolérance : les positions centrées tombent entre deux pixels.
  final inside = rect.left >= bounds.left - 0.5 &&
      rect.top >= bounds.top - 0.5 &&
      rect.right <= bounds.right + 0.5 &&
      rect.bottom <= bounds.bottom + 0.5;
  expect(inside, isTrue, reason: '${reason ?? '$finder'} : $rect hors de $bounds');
}
