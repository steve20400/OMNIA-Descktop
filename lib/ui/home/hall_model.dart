import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/controllers/media_router.dart';
import '../../core/models/media_type.dart';
import '../../core/providers.dart';
import '../file_dialogs.dart';
import '../recent_files.dart';

/// Les rayons de l'accueil : tout, ou un seul type de média.
enum HallCategory {
  all('Tout'),
  video('Vidéos'),
  music('Musique'),
  documents('Documents'),
  images('Images');

  const HallCategory(this.label);

  final String label;

  /// Vrai si un média de type [type] figure dans ce rayon.
  bool accepts(MediaType type) => switch (this) {
        HallCategory.all => type != MediaType.unknown,
        HallCategory.video => type == MediaType.video,
        HallCategory.music => type == MediaType.audio,
        HallCategory.documents => type.isDocument,
        HallCategory.images => type == MediaType.image,
      };
}

/// Ce que montre l'accueil : le rayon choisi et l'affiche sélectionnée.
class HallState {
  const HallState({this.category = HallCategory.all, this.index = 0});

  final HallCategory category;

  /// Position de l'affiche sélectionnée dans le rayon.
  final int index;

  HallState copyWith({HallCategory? category, int? index}) => HallState(
        category: category ?? this.category,
        index: index ?? this.index,
      );
}

/// Sélection de l'accueil, partagée par la souris, le clavier et l'écran.
final hallProvider = NotifierProvider<HallController, HallState>(HallController.new);

class HallController extends Notifier<HallState> {
  @override
  HallState build() => const HallState();

  /// Change de rayon ; la sélection repart de la première affiche.
  void showCategory(HallCategory category) {
    if (category == state.category) return;
    state = HallState(category: category);
  }

  void select(int index) {
    if (index == state.index || index < 0) return;
    state = state.copyWith(index: index);
  }

  /// Déplace la sélection de [delta], bornée aux [count] affiches du rayon.
  void move(int delta, int count) {
    if (count <= 0) return;
    final next = (state.index + delta).clamp(0, count - 1);
    if (next != state.index) state = state.copyWith(index: next);
  }
}

/// Les fichiers récents que montre le rayon [category], du plus récent au
/// plus ancien.
List<RecentFile> hallItems(List<RecentFile> recents, HallCategory category) => [
      for (final recent in recents)
        if (category.accepts(MediaRouter.typeForPath(recent.path))) recent,
    ];

/// L'affiche sélectionnée, ramenée dans les bornes du rayon ; `null` s'il est
/// vide.
RecentFile? hallSelection(List<RecentFile> items, HallState hall) {
  if (items.isEmpty) return null;
  return items[hall.index.clamp(0, items.length - 1)];
}

/// Ouvre [recent] comme le ferait la liste des récents : dans cette fenêtre
/// ou dans une nouvelle, selon le réglage.
void openFromHall(WidgetRef ref, RecentFile recent) {
  if (!recent.exists) return;
  if (ref.read(preferencesProvider).inAppOpenNewWindow) {
    openInNewWindow(recent.path);
  } else {
    ref.dispatch(OpenFile(recent.path));
  }
}

/// Clavier de l'accueil : ← → parcourent les affiches, Début et Fin vont aux
/// extrémités, Entrée ouvre la sélection — comme sur l'accueil d'une console.
///
/// ↑ et ↓ n'en font pas partie : sur l'accueil, ils règlent toujours le
/// volume du prochain fichier. Rend vrai si la touche a servi.
bool handleHallKey(KeyEvent event, WidgetRef ref) {
  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isControlPressed ||
      keyboard.isAltPressed ||
      keyboard.isMetaPressed ||
      keyboard.isShiftPressed) {
    return false;
  }
  final hall = ref.read(hallProvider);
  final items = hallItems(ref.read(recentFilesProvider), hall.category);
  if (items.isEmpty) return false;
  final controller = ref.read(hallProvider.notifier);
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowLeft) {
    controller.move(-1, items.length);
  } else if (key == LogicalKeyboardKey.arrowRight) {
    controller.move(1, items.length);
  } else if (key == LogicalKeyboardKey.home) {
    controller.select(0);
  } else if (key == LogicalKeyboardKey.end) {
    controller.select(items.length - 1);
  } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
    // Une touche maintenue ne rouvre pas le fichier en boucle.
    if (event is KeyRepeatEvent) return true;
    final selected = hallSelection(items, hall);
    if (selected != null) openFromHall(ref, selected);
  } else {
    return false;
  }
  return true;
}
