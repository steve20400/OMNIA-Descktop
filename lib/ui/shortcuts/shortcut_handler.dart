import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/commands/player_command.dart';
import '../../core/commands/player_command_bus.dart';
import '../../core/providers.dart';
import '../document_ui_controller.dart';
import '../file_dialogs.dart';
import '../help_overlay_controller.dart';
import 'default_keymap.dart';
import 'keymap_provider.dart';

/// Traduit un événement clavier en commande sur le bus, d'après la table de
/// raccourcis de l'utilisateur.
///
/// Quand un champ de saisie a le focus (recherche du panneau), les raccourcis
/// se taisent : taper « pause » dans la recherche ne doit pas mettre le film en
/// pause. `Échap` fait exception — elle rend le focus au lecteur, sans quoi
/// l'utilisateur resterait piégé dans le champ, clavier inopérant.
KeyEventResult handleShortcut(KeyEvent event, WidgetRef ref) {
  if (event is KeyUpEvent) return KeyEventResult.ignored;

  // Le panneau d'aide ouvert capte Échap et F1 pour se fermer, et rien
  // d'autre : on ne pilote pas la lecture à l'aveugle derrière un voile.
  final help = ref.read(helpVisibleProvider.notifier);
  if (ref.read(helpVisibleProvider)) {
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.f1) {
      help.hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  if (textFieldHasFocus()) {
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      FocusManager.instance.primaryFocus?.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  final keyboard = HardwareKeyboard.instance;
  final action = ref.read(keymapProvider).match(
        key: event.logicalKey,
        character: event.character,
        control: keyboard.isControlPressed,
        shift: keyboard.isShiftPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
        isRepeat: event is KeyRepeatEvent,
      );
  if (action == null) {
    // `Shift+Tab` n'est volontairement pas capturé : il reste le moyen clavier
    // d'atteindre la recherche du panneau. Le piège classique — se retrouver
    // dans un champ, tous les raccourcis muets — est levé par `Échap`.
    return KeyEventResult.ignored;
  }

  switch (resolveShortcut(action, ref.read(preferencesProvider))) {
    case final PlayerCommand command:
      ref.dispatch(command, source: CommandSource.keyboard);
    case UiAction.openFileDialog:
      pickAndOpenFile(ref);
    case UiAction.openFolderDialog:
      pickAndOpenFolder(ref);
    case UiAction.toggleHelp:
      help.toggle();
    case UiAction.goToPage:
      if (!ref.read(playbackStateProvider).isDocument) return KeyEventResult.ignored;
      ref.read(documentUiProvider.notifier).requestGoToPage();
    case UiAction.findInDocument:
      if (!ref.read(playbackStateProvider).isDocument) return KeyEventResult.ignored;
      ref.read(documentUiProvider.notifier).showFind();
    case _:
      return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}

/// Vrai si le focus est dans un champ de texte.
bool textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
