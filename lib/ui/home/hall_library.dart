import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/media_file.dart';
import '../../core/providers.dart';
import '../../core/services/user_library.dart';
import 'hall_artwork.dart';

/// Les dossiers personnels parcourus pour remplir les rayons de l'accueil.
///
/// Vide sous les tests d'interface (comme les affiches) : ils n'ont pas à
/// lire le disque de la machine qui les fait tourner.
final hallLibraryRootsProvider = Provider<List<String>>(
  (ref) => ref.watch(hallArtworkEnabledProvider) ? defaultUserMediaFolders() : const [],
);

/// Les médias des dossiers personnels, du plus récent au plus ancien — vide
/// si l'utilisateur a choisi de ne montrer que ce qu'il a déjà ouvert.
final userLibraryProvider = FutureProvider<List<MediaFile>>((ref) async {
  final enabled = ref.watch(preferencesProvider.select((p) => p.hallShowsLibrary));
  if (!enabled) return const [];
  return scanUserLibrary(ref.watch(hallLibraryRootsProvider));
});
