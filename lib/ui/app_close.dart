import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

/// Ferme proprement et immédiatement l'application :
/// 1. Coupe instantanément tout flux audio et vidéo mpv en cours
///    (pour éliminer le son résiduel qui traîne après la fermeture).
/// 2. Ferme la fenêtre native de l'application.
Future<void> closeApplication(WidgetRef ref) async {
  try {
    await ref.read(avControllerProvider).player.stop();
  } catch (_) {}
  try {
    await ref.read(playbackServiceProvider).stopImmediately();
  } catch (_) {}
  await ref.read(windowServiceProvider).close();
}
