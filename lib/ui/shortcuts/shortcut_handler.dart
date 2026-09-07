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
/// Ignoré si un champ de texte a le focus (recherche de la playlist, etc.).
KeyEventResult handleShortcut(KeyEvent event, WidgetRef ref) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;
  if (_textFieldHasFocus()) return KeyEventResult.ignored;

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

  // Touches de vitesse par caractère (indépendant de la disposition).
  final char = event.character;
  if (char != null && !keyboard.isControlPressed && !keyboard.isAltPressed) {
    final command = characterKeymap[char];
    if (command != null) {
      ref.dispatch(command, source: CommandSource.keyboard);
      return KeyEventResult.handled;
    }
  }
  return KeyEventResult.ignored;
}

bool _textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}
