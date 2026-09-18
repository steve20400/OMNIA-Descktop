import 'package:flutter_riverpod/flutter_riverpod.dart';

/// État d'interface propre aux documents : barre de recherche, champ « aller
/// à la page », mode édition pour les fichiers texte/code modifiables.
class DocumentUiState {
  const DocumentUiState({
    this.findVisible = false,
    this.goToPageRequest = 0,
    this.isEditing = false,
    this.saveRequest = 0,
    this.hasUnsavedChanges = false,
  });

  /// La barre de recherche (`Ctrl+F`) est affichée.
  final bool findVisible;

  /// Compteur incrémenté à chaque `Ctrl+G` : la barre de document réagit au
  /// changement en donnant le focus au champ de page.
  final int goToPageRequest;

  /// Vrai si l'utilisateur est en mode édition (lecture / écriture).
  final bool isEditing;

  /// Compteur incrémenté pour déclencher l'enregistrement (`Ctrl+S` ou bouton).
  final int saveRequest;

  /// Vrai si le texte a été modifié mais pas encore enregistré sur le disque.
  final bool hasUnsavedChanges;

  DocumentUiState copyWith({
    bool? findVisible,
    int? goToPageRequest,
    bool? isEditing,
    int? saveRequest,
    bool? hasUnsavedChanges,
  }) =>
      DocumentUiState(
        findVisible: findVisible ?? this.findVisible,
        goToPageRequest: goToPageRequest ?? this.goToPageRequest,
        isEditing: isEditing ?? this.isEditing,
        saveRequest: saveRequest ?? this.saveRequest,
        hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
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

  void toggleEdit() => state = state.copyWith(isEditing: !state.isEditing);
  void setEditing(bool value) => state = state.copyWith(isEditing: value);
  void requestSave() => state = state.copyWith(saveRequest: state.saveRequest + 1);
  void setUnsavedChanges(bool value) =>
      state = state.copyWith(hasUnsavedChanges: value);
}
