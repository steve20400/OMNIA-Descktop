import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnia/core/commands/player_command.dart';
import 'package:omnia/core/commands/player_command_bus.dart';
import 'package:omnia/core/models/media_file.dart';
import 'package:omnia/core/models/media_type.dart';
import 'package:omnia/core/models/playback_state.dart';
import 'package:omnia/core/providers.dart';
import 'package:omnia/core/services/folder_scanner.dart';
import 'package:omnia/core/services/history_store.dart';
import 'package:omnia/core/services/playlist_service.dart';
import 'package:omnia/core/services/settings_store.dart';
import 'package:omnia/ui/document_ui_controller.dart';
import 'package:omnia/ui/shortcuts/shortcut_handler.dart';

import 'narrow_harness.dart';

void main() {
  group('Raccourcis PageUp/PageDown et navigation de documents', () {
    late PlayerCommandBus bus;
    late PlaylistService playlist;
    late List<PlayerCommand> dispatched;

    setUp(() async {
      bus = PlayerCommandBus();
      dispatched = [];
      bus.stream.listen((cmd) => dispatched.add(cmd.command));

      final scanner = FakeFolderScanner({
        '/folder': [
          MediaFile(path: '/folder/doc1.pdf', type: MediaType.pdf, size: 100, modifiedAt: DateTime(2026)),
          MediaFile(path: '/folder/doc2.pdf', type: MediaType.pdf, size: 100, modifiedAt: DateTime(2026)),
        ],
      });
      playlist = PlaylistService(bus: bus, scanner: scanner, history: MemoryHistoryStore());
      await playlist.scanFolder('/folder');
      playlist.setCurrent('/folder/doc1.pdf');
    });

    tearDown(() async {
      await playlist.dispose();
      await bus.dispose();
    });

    testWidgets('sans clic sur le document, PageDown navigue vers le fichier suivant', (tester) async {
      final store = MemorySettingsStore();
      await store.setKeymapOverrides({
        'nextFile': ['PageDown'],
        'previousFile': ['PageUp'],
      });

      const state = PlaybackState(
        file: MediaFile(path: '/folder/doc1.pdf', type: MediaType.pdf),
        currentPage: 2,
        totalPages: 10,
      );

      final container = ProviderContainer(
        overrides: [
          commandBusProvider.overrideWithValue(bus),
          settingsStoreProvider.overrideWithValue(store),
          playlistServiceProvider.overrideWithValue(playlist),
          playbackStateProvider.overrideWith(() => FixedPlaybackState(state)),
        ],
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(container.read(documentUiProvider).documentFocused, isFalse);

      final event = const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.pageDown,
        logicalKey: LogicalKeyboardKey.pageDown,
        timeStamp: Duration.zero,
      );

      final result = handleShortcut(event, capturedRef);
      expect(result, KeyEventResult.handled);
      expect(dispatched, contains(const NextFile()));
    });

    testWidgets('avec clic sur le document, PageDown scrolle le document (NextPage)', (tester) async {
      final store = MemorySettingsStore();
      await store.setKeymapOverrides({
        'nextFile': ['PageDown'],
        'previousFile': ['PageUp'],
      });

      const state = PlaybackState(
        file: MediaFile(path: '/folder/doc1.pdf', type: MediaType.pdf),
        currentPage: 2,
        totalPages: 10,
      );

      final container = ProviderContainer(
        overrides: [
          commandBusProvider.overrideWithValue(bus),
          settingsStoreProvider.overrideWithValue(store),
          playlistServiceProvider.overrideWithValue(playlist),
          playbackStateProvider.overrideWith(() => FixedPlaybackState(state)),
        ],
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      // L'utilisateur clique sur le document
      container.read(documentUiProvider.notifier).setDocumentFocused(true);
      expect(container.read(documentUiProvider).documentFocused, isTrue);

      final event = const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.pageDown,
        logicalKey: LogicalKeyboardKey.pageDown,
        timeStamp: Duration.zero,
      );

      final result = handleShortcut(event, capturedRef);
      expect(result, KeyEventResult.handled);
      expect(dispatched, contains(const NextPage()));
    });

    testWidgets('sans clic et sans autre fichier dans la playlist, PageDown se replie sur le document', (tester) async {
      final store = MemorySettingsStore();
      await store.setKeymapOverrides({
        'nextFile': ['PageDown'],
        'previousFile': ['PageUp'],
      });

      // Se positionner sur le dernier fichier de la playlist
      playlist.setCurrent('/folder/doc2.pdf');

      const state = PlaybackState(
        file: MediaFile(path: '/folder/doc2.pdf', type: MediaType.pdf),
        currentPage: 5,
        totalPages: 10,
      );

      final container = ProviderContainer(
        overrides: [
          commandBusProvider.overrideWithValue(bus),
          settingsStoreProvider.overrideWithValue(store),
          playlistServiceProvider.overrideWithValue(playlist),
          playbackStateProvider.overrideWith(() => FixedPlaybackState(state)),
        ],
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(container.read(documentUiProvider).documentFocused, isFalse);

      final event = const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.pageDown,
        logicalKey: LogicalKeyboardKey.pageDown,
        timeStamp: Duration.zero,
      );

      final result = handleShortcut(event, capturedRef);
      expect(result, KeyEventResult.handled);
      // Comme nextPath() est null, repli sur le défilement du document
      expect(dispatched, contains(const NextPage()));
    });
  });
}
