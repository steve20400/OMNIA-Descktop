import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command_bus.dart';
import '../../core/models/playback_state.dart';
import '../../core/providers.dart';
import '../chrome_controller.dart';
import '../theme/omnia_motion.dart';
import 'osd_message.dart';

/// Message OSD courant, `null` quand rien n'est affiché.
final osdProvider = NotifierProvider<OsdController, OsdMessage?>(OsdController.new);

/// Écoute le bus, attend que la commande soit traitée, puis publie le message
/// à afficher. Un nouveau message remplace le précédent et relance le délai.
class OsdController extends Notifier<OsdMessage?> {
  Timer? _hide;
  StreamSubscription<DispatchedCommand>? _subscription;
  StreamSubscription<PlaybackState>? _states;

  @override
  OsdMessage? build() {
    final bus = ref.watch(commandBusProvider);
    final service = ref.watch(playbackServiceProvider);

    _subscription = bus.stream.listen((dispatched) async {
      if (!osdWantedFor(dispatched.source, controlsHidden: !ref.read(chromeProvider))) {
        return;
      }
      // La commande n'est pas encore traitée quand elle arrive ici : on
      // attend que la file du service l'ait exécutée pour lire l'état obtenu.
      await service.idle;
      final message = osdFor(dispatched.command, service.state);
      if (message == null) return;
      show(message);
    });

    // Extraits : la fin d'un enregistrement s'annonce toujours, qu'elle vienne
    // de l'utilisateur ou d'un changement de fichier, et un échec aussi.
    var previous = service.state;
    _states = service.stream.listen((next) {
      final before = previous;
      previous = next;
      if (!before.recordingFailed && next.recordingFailed) {
        show(const OsdRecordingFailed());
        return;
      }
      final saved = next.lastRecording;
      if (before.recording && !next.recording && saved != null) {
        final started = before.recordingStartedAt;
        show(OsdRecordingSaved(
          saved,
          length: started == null ? null : DateTime.now().difference(started),
        ));
      }
    });

    ref.onDispose(() {
      _subscription?.cancel();
      _states?.cancel();
      _hide?.cancel();
    });
    return null;
  }

  void show(OsdMessage message) {
    state = message;
    _hide?.cancel();
    _hide = Timer(OmniaMotion.osdLinger, () => state = null);
  }
}
