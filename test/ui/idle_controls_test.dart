// Les contrôles qui n'ont rien à piloter ne s'affichent pas.
//
// Sur l'accueil — aucun fichier ouvert —, la barre de lecture n'a ni lecture,
// ni progression, ni piste à commander : elle ne doit pas être là. Tout ce qui
// sert à ouvrir un fichier, lui, reste : barre de titre, languette du panneau,
// paramètres, menu du clic droit, et le volume au clavier.
//
// L'écran est monté tel que l'application le monte (OmniaApp), avec des
// stockages en mémoire et un lecteur factice à la place de mpv : même montage
// que le test de fumée.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/core/services/audio_metadata_service.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/screen_wake.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:omnia/ui/app.dart';
import 'package:omnia/ui/chrome_controller.dart';
import 'package:omnia/ui/osd/osd_controller.dart';
import 'package:omnia/ui/osd/osd_message.dart';
import 'package:omnia/ui/settings/settings_controller.dart';
import 'package:omnia/ui/theme/omnia_theme.dart';
import 'package:omnia/ui/widgets/control_bar.dart';
import 'package:omnia/ui/widgets/document_bar.dart';
import 'package:omnia/ui/widgets/image_bar.dart';
import 'package:omnia/ui/widgets/mini_player.dart';
import 'package:omnia/ui/widgets/omnia_button.dart';
import 'package:omnia/ui/widgets/side_panel.dart';
import 'package:omnia/ui/widgets/stage.dart';
import 'package:omnia/ui/widgets/title_bar.dart';

import 'narrow_harness.dart';

const _folder = '/musique';
const _track = '/musique/Piste.mp3';
const _film = '/musique/Film.mkv';

/// Lecteur factice : quatre minutes, sans son. Une vidéo annonce une image —
/// c'est elle qui active le masquage automatique des contrôles. Sa fermeture
/// vide l'état, comme le vrai moteur.
class _SilentPlayer implements MediaController {
  PlaybackStateSink? _sink;

  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    _sink = sink;
    sink.update(
      (s) => s.copyWith(
        file: file,
        status: PlaybackStatus.playing,
        duration: const Duration(minutes: 4),
        position: Duration.zero,
        hasVideo: file.type == MediaType.video,
        videoWidth: file.type == MediaType.video ? 1920 : 0,
        videoHeight: file.type == MediaType.video ? 1080 : 0,
        clearError: true,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async => true;

  @override
  Future<void> close() async {
    _sink?.update((s) => s.copyWith(clearFile: true, status: PlaybackStatus.idle));
  }

  @override
  Future<void> dispose() async {}
}

/// OMNIA au complet : bus, stockages en mémoire, fenêtre factice.
class _AppHarness {
  _AppHarness() {
    final store = MemorySettingsStore(
      preferences: const AppPreferences(language: AppLanguage.fr),
    );
    final history = MemoryHistoryStore();
    final scanner = FakeFolderScanner({
      _folder: [
        MediaFile(path: _track, type: MediaType.audio, size: 1000, modifiedAt: DateTime(2026)),
        MediaFile(path: _film, type: MediaType.video, size: 2000, modifiedAt: DateTime(2026)),
      ],
    });
    playlist = PlaylistService(bus: bus, scanner: scanner, history: history, settings: store);
    service = PlaybackService(
      bus: bus,
      router: MediaRouter([_SilentPlayer()]),
      window: window,
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
        windowServiceProvider.overrideWithValue(window),
        screenWakeProvider.overrideWithValue(RecordingScreenWake()),
        // Les chemins du test n'existent pas sur le disque : la lecture des
        // tags n'a rien à y trouver, et surtout rien à lancer dans un isolate.
        audioMetadataServiceProvider.overrideWithValue(
          FakeAudioMetadataService(const {}),
        ),
        // La vraie surface vidéo réclame libmpv : un aplat suffit ici.
        videoSurfaceProvider.overrideWithValue(
          (context, {required fit, aspectRatio}) => const ColoredBox(color: Colors.black),
        ),
      ],
    );
  }

  final PlayerCommandBus bus = PlayerCommandBus();
  final FakeWindowService window = FakeWindowService();
  late final PlaylistService playlist;
  late final PlaybackService service;
  late final ProviderContainer container;

  PlaybackState get state => container.read(playbackStateProvider);

  /// Monte l'application dans une fenêtre de bureau ordinaire et range tout en
  /// fin de test.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      container.dispose();
      await service.dispose();
      await playlist.dispose();
      await bus.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const OmniaApp()),
    );
    await tester.pumpAndSettle();
  }
}

/// Laisse le bus livrer les commandes et le service les traiter.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

/// Démonte l'arbre et laisse passer les minuteries restantes (effacement de
/// l'OSD, sauvegardes différées).
Future<void> _settleTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  group('Accueil', () {
    testWidgets('sans fichier, aucune barre de lecture ne s’affiche', (tester) async {
      final app = _AppHarness();
      await app.pump(tester);

      expect(app.state.hasFile, isFalse);
      expect(find.byType(ControlBar), findsNothing);
      expect(find.byType(DocumentBar), findsNothing);
      expect(find.byType(ImageBar), findsNothing);

      await _settleTimers(tester);
    });

    testWidgets('l’accueil garde de quoi ouvrir un fichier et régler OMNIA', (tester) async {
      final app = _AppHarness();
      await app.pump(tester);

      // La barre de titre et ses boutons de fenêtre.
      expect(find.byType(TitleBar), findsOneWidget);
      // Les deux boutons de la scène vide.
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un fichier'), findsOneWidget);
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un dossier'), findsOneWidget);

      // La languette, dès que le panneau est replié.
      app.bus.dispatch(const SetSidePanelVisible(false));
      await _drain(tester);
      expect(find.byType(PanelEdgeTab), findsOneWidget);

      // Les paramètres, par la barre de titre.
      await tester.tap(byTooltipPrefix('Paramètres'));
      await tester.pumpAndSettle();
      expect(app.container.read(settingsUiProvider).visible, isTrue);
      app.container.read(settingsUiProvider.notifier).hide();
      await tester.pumpAndSettle();

      await _settleTimers(tester);
    });

    testWidgets('sans fichier, le volume se règle encore au clavier', (tester) async {
      final app = _AppHarness();
      await app.pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _drain(tester);

      // Le réglage est retenu pour le prochain fichier, et l'affichage à
      // l'écran le confirme : c'est le seul retour possible sans barre.
      expect(app.state.volume, 95);
      final osd = app.container.read(osdProvider);
      expect(osd, isA<OsdVolume>());
      expect((osd! as OsdVolume).volume, 95);

      await _settleTimers(tester);
    });

    testWidgets('sans fichier, le mini-lecteur ne s’ouvre pas au clavier', (tester) async {
      final app = _AppHarness();
      await app.pump(tester);

      // `Ctrl+Maj+M` : le seul chemin qui reste vers le mini-lecteur sans
      // barre ni menu — le bouton et la ligne du clic droit demandent déjà un
      // fichier.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _drain(tester);

      // Rien à montrer dans une fenêtre compacte : OMNIA reste entière, ne
      // passe pas au premier plan, et l'affichage à l'écran n'annonce pas le
      // contraire.
      expect(app.state.miniPlayer, isFalse);
      expect(app.state.alwaysOnTop, isFalse);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un fichier'), findsOneWidget);
      expect(app.container.read(osdProvider), isNull);

      await _settleTimers(tester);
    });

    testWidgets('la barre revient avec un fichier, et repart avec lui', (tester) async {
      final app = _AppHarness();
      await app.pump(tester);

      app.bus.dispatch(const OpenFile(_track));
      await _drain(tester);
      expect(app.state.file?.path, _track);
      expect(find.byType(ControlBar), findsOneWidget);

      app.bus.dispatch(const Stop());
      await _drain(tester);
      expect(app.state.hasFile, isFalse);
      expect(find.byType(ControlBar), findsNothing);
      expect(find.widgetWithText(OmniaButton, 'Ouvrir un fichier'), findsOneWidget);

      await _settleTimers(tester);
    });

    testWidgets('la retenue de la barre ne survit pas au fichier', (tester) async {
      final app = _AppHarness();
      await app.pump(tester);

      // Une vidéo : c'est le seul média dont les contrôles se masquent d'eux-
      // mêmes en fenêtre.
      app.bus.dispatch(const OpenFile(_film));
      await _drain(tester);
      expect(find.byType(ControlBar), findsOneWidget);

      // Le pointeur se pose sur la barre : elle est retenue visible, et le
      // délai de masquage ne l'efface plus.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(ControlBar)));
      await _drain(tester);
      await tester.pump(OmniaMotion.idleHide * 2);
      expect(app.container.read(chromeProvider), isTrue, reason: 'retenue par le pointeur');

      // Le fichier se referme sous le pointeur : la barre disparaît de l'arbre
      // sans que son `onExit` ne se déclenche. Si sa retenue restait posée,
      // plus rien ne se masquerait — même au fichier suivant.
      app.bus.dispatch(const Stop());
      await _drain(tester);
      expect(find.byType(ControlBar), findsNothing);

      // Le pointeur s'écarte de la place de la barre, puis une vidéo repart :
      // les contrôles doivent savoir se masquer de nouveau.
      await mouse.moveTo(const Offset(8, 8));
      await _drain(tester);
      app.bus.dispatch(const OpenFile(_film));
      await _drain(tester);
      expect(app.container.read(chromeProvider), isTrue);

      await tester.pump(OmniaMotion.idleHide * 2);
      expect(
        app.container.read(chromeProvider),
        isFalse,
        reason: 'aucune retenue ne doit survivre à la barre du fichier précédent',
      );

      await _settleTimers(tester);
    });
  });

  group('Mini-lecteur', () {
    test('ce que le mini-lecteur sait montrer', () {
      const idle = PlaybackState();
      expect(idle.canMiniPlayer, isFalse);

      const audio = PlaybackState(
        file: MediaFile(path: '/musique/Piste.mp3', type: MediaType.audio),
        status: PlaybackStatus.playing,
      );
      expect(audio.canMiniPlayer, isTrue);

      // Un document et une image aussi : le mini-lecteur est universel, seule
      // l'absence de fichier le prive de contenu.
      const pdf = PlaybackState(
        file: MediaFile(path: '/docs/Manuel.pdf', type: MediaType.pdf),
        status: PlaybackStatus.playing,
      );
      expect(pdf.canMiniPlayer, isTrue);

      const broken = PlaybackState(
        file: MediaFile(path: '/films/Cassé.mkv', type: MediaType.video),
        status: PlaybackStatus.error,
        error: PlaybackError(PlaybackErrorCode.decodeFailed),
      );
      expect(broken.canMiniPlayer, isFalse);
    });

    test('sans fichier, l’affichage à l’écran n’annonce rien', () {
      const idle = PlaybackState();
      expect(osdFor(const ToggleMiniPlayer(), idle), isNull);

      const mini = PlaybackState(
        file: MediaFile(path: '/musique/Piste.mp3', type: MediaType.audio),
        status: PlaybackStatus.playing,
        miniPlayer: true,
      );
      expect(osdFor(const ToggleMiniPlayer(), mini), isA<OsdMiniPlayer>());
    });
  });
}
