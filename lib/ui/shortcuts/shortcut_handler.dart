import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/providers.dart';
import '../file_dialogs.dart';
import 'default_keymap.dart';

/// Traduit un événement clavier en commande sur le bus.
///
/// Quand un champ de saisie a le focus (recherche du panneau), les raccourcis
/// se taisent : taper « pause » dans la recherche ne doit pas mettre le film en
/// pause. `Échap` fait exception — elle rend le focus au lecteur, sans quoi
/// l'utilisateur resterait piégé dans le champ, clavier inopérant.
KeyEventResult handleShortcut(KeyEvent event, WidgetRef ref) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;

  if (textFieldHasFocus()) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      FocusManager.instance.primaryFocus?.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  final keyboard = HardwareKeyboard.instance;
  for (final entry in defaultKeymap.entries) {
    if (!entry.key.accepts(event, keyboard)) continue;
    final action = entry.value;
    switch (action) {
      case PlayerCommand():
        ref.dispatch(action, source: CommandSource.keyboard);
      case UiAction.openFileDialog:
        pickAndOpenFile(ref);
      case UiAction.openFolderDialog:
        pickAndOpenFolder(ref);
    }
    return KeyEventResult.handled;
  }

  // Touches de vitesse par caractère : `+`, `-` et `=` ne sont pas au même
  // endroit en AZERTY et en QWERTY, on les reconnaît donc au caractère produit.
  final char = event.character;
  if (char != null && !keyboard.isControlPressed && !keyboard.isAltPressed) {
    final command = characterKeymap[char];
    if (command != null) {
      ref.dispatch(command, source: CommandSource.keyboard);
      return KeyEventResult.handled;
    }
  }

  // `Shift+Tab` n'est volontairement pas capturé : il reste le moyen clavier
  // d'atteindre la recherche du panneau. Le piège classique — se retrouver
  // dans un champ, tous les raccourcis muets — est levé par `Échap` ci-dessus.
  return KeyEventResult.ignored;
}

/// Vrai si le focus est dans un champ de texte.
bool textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
