// Test de fumée de l'écran principal, monté tel que l'application le monte.
//
// Les autres tests d'interface enveloppent leurs widgets dans un Material :
// ils ne pouvaient pas voir qu'en vrai, l'écran principal n'en avait aucun
// au-dessus de lui (textes soulignés de jaune, menus et champs en erreur).
// Celui-ci monte OmniaApp sans rien ajouter et parcourt les états visibles.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/controllers/media_controller.dart';
import 'package:omnia/core/controllers/media_router.dart';
import 'package:omnia/core/controllers/text_controller.dart';
import 'package:omnia/core/models/app_preferences.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_status.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playback_service.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/screen_wake.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/core/services/window_service.dart';
import 'package:omnia/ui/app.dart';
import 'package:omnia/ui/document_ui_controller.dart';
import 'package:omnia/ui/help_overlay_controller.dart';
import 'package:omnia/ui/settings/settings_controller.dart';
import 'package:omnia/ui/widgets/find_bar.dart';
import 'package:omnia/ui/widgets/mini_player.dart';
import 'package:omnia/ui/widgets/resume_prompt.dart';
import 'package:omnia/ui/widgets/stage.dart';
import 'package:omnia/ui/widgets/window_drag_area.dart';
import 'package:path/path.dart' as p;

/// Lecteur audio factice : quatre minutes, sans son.
class _SilentPlayer implements MediaController {
  @override
  Set<MediaType> get supportedTypes => const {MediaType.video, MediaType.audio};

  @override
  Future<void> open(MediaFile file, PlaybackStateSink sink) async {
    sink.update(
      (s) => s.copyWith(
        file: file,
        status: PlaybackStatus.playing,
        duration: const Duration(minutes: 4),
        position: Duration.zero,
        hasVideo: false,
        clearError: true,
      ),
    );
  }

  @override
  Future<bool> handle(PlayerCommand command) async => true;

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}
}

/// Vrai pour le style que Flutter donne aux textes sans Material : rouge,
/// double soulignement jaune.
bool _isFallbackStyle(TextStyle style) =>
    (style.debugLabel?.contains('fallback style') ?? false) ||
    (style.decorationStyle == TextDecorationStyle.double &&
        style.decorationColor == const Color(0xFFFFFF00));

/// Aucune exception, et aucun texte visible au style de secours.
void _expectWellFormed(WidgetTester tester, String where) {
  expect(tester.takeException(), isNull, reason: where);
  final unstyled = [
    for (final text in tester.widgetList<RichText>(find.byType(RichText)))
      if (text.text.style case final style? when _isFallbackStyle(style))
        text.text.toPlainText(),
  ];
  expect(unstyled, isEmpty, reason: '$where : textes sans Material au-dessus');
}

/// Laisse le bus livrer les commandes et le service les traiter.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

/// Comme [_drain], en laissant aussi aboutir les lectures de fichiers : elles
/// se terminent hors du temps simulé, puis libèrent des microtâches dedans.
Future<void> _drainIo(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('omnia_smoke_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Nettoyé par le système.
    }
  });

  testWidgets('l’écran principal a partout un Material au-dessus de ses textes', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final folder = Directory(p.join(root.path, 'Album'))..createSync();
    final tracks = [for (var i = 1; i <= 3; i++) p.join(folder.path, 'Piste $i.mp3')];
    final notes = p.join(folder.path, 'Notes.txt');
    for (final path in tracks) {
      File(path).writeAsStringSync('');
    }
    File(notes).writeAsStringSync('Première ligne\nDeuxième ligne avec un mot\nFin\n');

    final bus = PlayerCommandBus();
    // Reprise « demander » : l'invite de reprise fait partie du parcours.
    final store = MemorySettingsStore(
      preferences: const AppPreferences(language: AppLanguage.fr, resumePolicy: ResumePolicy.ask),
    );
    final history = MemoryHistoryStore();
    await history.savePosition(
      tracks[1],
      position: const Duration(minutes: 1, seconds: 20),
      duration: const Duration(minutes: 4),
    );
    final scanner = FakeFolderScanner({
      folder.path: [
        for (final path in tracks)
          MediaFile(path: path, type: MediaType.audio, size: 1000, modifiedAt: DateTime(2026)),
        MediaFile(path: notes, type: MediaType.text, size: 40, modifiedAt: DateTime(2026)),
      ],
    });
    final text = TextController(preferences: () => store.preferences);
    final playlist = PlaylistService(bus: bus, scanner: scanner, history: history, settings: store);
    final service = PlaybackService(
      bus: bus,
      router: MediaRouter([_SilentPlayer(), text]),
      window: FakeWindowService(),
      playlist: playlist,
      history: history,
      settings: store,
    );
    // Déplacements de fenêtre demandés au système : il n'y en a pas sous un
    // test, mais le mini-lecteur doit bien les demander.
    var windowDrags = 0;
    final container = ProviderContainer(
      overrides: [
        startWindowDragProvider.overrideWithValue(() => windowDrags++),
        commandBusProvider.overrideWithValue(bus),
        settingsStoreProvider.overrideWithValue(store),
        historyStoreProvider.overrideWithValue(history),
        playbackServiceProvider.overrideWithValue(service),
        playlistServiceProvider.overrideWithValue(playlist),
        textControllerProvider.overrideWithValue(text),
        windowServiceProvider.overrideWithValue(FakeWindowService()),
        screenWakeProvider.overrideWithValue(RecordingScreenWake()),
      ],
    );
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
    _expectWellFormed(tester, 'accueil');

    // Lecture dans un dossier : panneau de playlist (menus de tri et de
    // filtre), barre de contrôle, vue audio.
    bus.dispatch(OpenFile(tracks[0]));
    await _drain(tester);
    expect(container.read(playbackStateProvider).file?.path, tracks[0]);
    _expectWellFormed(tester, 'lecture audio');

    // Menu du clic droit : un clic gauche sur la scène le ferme, sans lancer
    // ni arrêter la lecture.
    final commands = <PlayerCommand>[];
    final subscription = bus.commands.listen(commands.add);
    addTearDown(subscription.cancel);
    final stage = tester.getRect(find.byType(Stage));
    await tester.tapAt(stage.center, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsWidgets, reason: 'menu ouvert');
    // Trop haut pour tenir sous le clic, le menu remonte et couvre le centre :
    // le clic gauche tombe à côté, sur la scène.
    final beside = Offset(stage.left + 40, stage.center.dy);
    expect(tester.getRect(find.byType(MenuItemButton).first).left, greaterThan(beside.dx));
    commands.clear();
    await tester.tapAt(beside);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing, reason: 'menu fermé');
    expect(commands.whereType<TogglePlay>(), isEmpty);
    _expectWellFormed(tester, 'menu du clic droit');

    // Fenêtre étroite : les commandes qui ne tiennent plus passent dans le
    // menu « ⋯ », sans débordement.
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Plus de commandes'), findsOneWidget);
    _expectWellFormed(tester, 'barre de contrôles étroite');
    await tester.tap(find.byTooltip('Plus de commandes'));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsWidgets, reason: 'menu « ⋯ » ouvert');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();

    // Fichier à reprendre : l'invite propose de reprendre ou de recommencer.
    bus.dispatch(OpenFile(tracks[1]));
    await _drain(tester);
    expect(container.read(playbackStateProvider).resumeOffer, isNotNull);
    expect(find.byType(ResumePrompt), findsOneWidget);
    _expectWellFormed(tester, 'invite de reprise');
    bus.dispatch(const DeclineResume());
    await _drain(tester);

    // Chaque section des paramètres, dont les champs de saisie.
    for (final section in SettingsSection.values) {
      container.read(settingsUiProvider.notifier).show(section);
      await tester.pumpAndSettle();
      _expectWellFormed(tester, 'paramètres : ${section.name}');
    }
    container.read(settingsUiProvider.notifier).hide();
    await tester.pumpAndSettle();

    container.read(helpVisibleProvider.notifier).toggle();
    await tester.pumpAndSettle();
    _expectWellFormed(tester, 'aide');
    container.read(helpVisibleProvider.notifier).hide();
    await tester.pumpAndSettle();

    // Document texte, avec la barre de recherche et son champ.
    bus.dispatch(OpenFile(notes));
    await _drainIo(tester);
    expect(container.read(playbackStateProvider).isDocument, isTrue);
    container.read(documentUiProvider.notifier).showFind();
    await tester.pumpAndSettle();
    expect(find.byType(FindBar), findsOneWidget);
    _expectWellFormed(tester, 'document texte et recherche');
    container.read(documentUiProvider.notifier).hideFind();
    await tester.pumpAndSettle();

    // Mini-lecteur : il remplace tout l'écran, il lui faut son propre Material.
    bus.dispatch(OpenFile(tracks[2]));
    await _drain(tester);
    bus.dispatch(const ToggleMiniPlayer());
    await _drain(tester);
    expect(find.byType(MiniPlayer), findsOneWidget);
    _expectWellFormed(tester, 'mini-lecteur');

    // Saisi ailleurs que sur une commande, il déplace la fenêtre : la pression
    // traverse bien le voile de dépôt et le Material qui l'enveloppent, et le
    // glissement part dès le premier mouvement.
    final mini = tester.getRect(find.byType(MiniPlayer));
    final windowDrag = await tester.startGesture(
      mini.topLeft + const Offset(8, 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await windowDrag.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(windowDrags, 1, reason: 'mini-lecteur déplaçable à la souris');
    await windowDrag.up();
    await _drain(tester);

    bus.dispatch(const ToggleMiniPlayer());
    await _drain(tester);
    // On démonte l'arbre, puis on laisse passer les minuteries restantes
    // (délai de l'invite de reprise, sauvegarde différée des réglages).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
  });
}
