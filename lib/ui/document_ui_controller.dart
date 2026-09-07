import 'package:flutter_riverpod/flutter_riverpod.dart';

/// État d'interface propre aux documents : barre de recherche, champ « aller
/// à la page ». Purement visuel, donc hors du core.
class DocumentUiState {
  const DocumentUiState({
    this.findVisible = false,
    this.goToPageRequest = 0,
  });

  /// La barre de recherche (`Ctrl+F`) est affichée.
  final bool findVisible;

  /// Compteur incrémenté à chaque `Ctrl+G` : la barre de document réagit au
  /// changement en donnant le focus au champ de page.
  final int goToPageRequest;

  DocumentUiState copyWith({bool? findVisible, int? goToPageRequest}) =>
      DocumentUiState(
        findVisible: findVisible ?? this.findVisible,
        goToPageRequest: goToPageRequest ?? this.goToPageRequest,
      );
}

final documentUiProvider =
    NotifierProvider<DocumentUiController, DocumentUiState>(DocumentUiController.new);

class DocumentUiController extends Notifier<DocumentUiState> {
  @override
  DocumentUiState build() => const DocumentUiState();

  void showFind() => state = state.copyWith(findVisible: true);
  void hideFind() => state = state.copyWith(findVisible: false);
  void toggleFind() => state = state.copyWith(findVisible: !state.findVisible);
  void requestGoToPage() =>
      state = state.copyWith(goToPageRequest: state.goToPageRequest + 1);
}
