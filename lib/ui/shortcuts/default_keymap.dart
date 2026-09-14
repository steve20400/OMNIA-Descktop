import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/commands/player_command.dart';
import '../../core/models/document_layout.dart';

/// Actions clavier qui ne sont pas des commandes du lecteur (dialogues, aide,
/// champs de saisie des documents).
enum UiAction { openFileDialog, openFolderDialog, toggleHelp, goToPage, findInDocument }

/// Table de raccourcis par défaut (§8 du cahier des charges).
///
/// Phase 1 : sous-ensemble utile. La personnalisation (éditeur, conflits,
/// persistance) arrive en Phase 6 ; cette table restera la valeur « défaut ».
///
/// Les valeurs sont soit une [PlayerCommand], soit une [UiAction].
final Map<ShortcutActivator, Object> defaultKeymap = {
  // Transport
  const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false): const TogglePlay(),
  const SingleActivator(LogicalKeyboardKey.mediaPlayPause, includeRepeats: false): const TogglePlay(),
  const SingleActivator(LogicalKeyboardKey.arrowLeft): const SeekRelative(-5),
  const SingleActivator(LogicalKeyboardKey.arrowRight): const SeekRelative(5),
  const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): const SeekRelative(-30),
  const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): const SeekRelative(30),
  const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): const SeekRelative(-60),
  const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): const SeekRelative(60),

  // Volume
  const SingleActivator(LogicalKeyboardKey.arrowUp): const VolumeRelative(5),
  const SingleActivator(LogicalKeyboardKey.arrowDown): const VolumeRelative(-5),
  const SingleActivator(LogicalKeyboardKey.keyM, includeRepeats: false): const ToggleMute(),

  // Fenêtre
  const SingleActivator(LogicalKeyboardKey.keyF, includeRepeats: false): const ToggleFullscreen(),
  const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false): const ExitFullscreen(),
  const SingleActivator(LogicalKeyboardKey.keyT, includeRepeats: false): const ToggleAlwaysOnTop(),

  // Playlist (opérationnel en Phase 2)
  const SingleActivator(LogicalKeyboardKey.keyN, includeRepeats: false): const NextFile(),
  const SingleActivator(LogicalKeyboardKey.keyP, includeRepeats: false): const PreviousFile(),
  const SingleActivator(LogicalKeyboardKey.keyL, includeRepeats: false): const CycleLoopMode(),
  const SingleActivator(LogicalKeyboardKey.tab, includeRepeats: false): const ToggleSidePanel(),

  // Vitesse (les touches +/-/= sont aussi reconnues par caractère, voir handler)
  const SingleActivator(LogicalKeyboardKey.numpadAdd): const SpeedRelative(0.25),
  const SingleActivator(LogicalKeyboardKey.numpadSubtract): const SpeedRelative(-0.25),

  // Ouverture
  const SingleActivator(LogicalKeyboardKey.keyO, control: true, includeRepeats: false):
      UiAction.openFileDialog,
  const SingleActivator(LogicalKeyboardKey.keyO, control: true, shift: true, includeRepeats: false):
      UiAction.openFolderDialog,

  // Vidéo (Phase 5)
  const SingleActivator(LogicalKeyboardKey.keyS, includeRepeats: false): const TakeScreenshot(),
  const SingleActivator(LogicalKeyboardKey.keyA, includeRepeats: false): const CycleAbLoop(),
  const SingleActivator(LogicalKeyboardKey.keyV, includeRepeats: false): const ToggleSubtitles(),
  const SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true, includeRepeats: false):
      const ToggleMiniPlayer(),

  // Documents (Phase 4)
  const SingleActivator(LogicalKeyboardKey.pageUp): const PreviousPage(),
  const SingleActivator(LogicalKeyboardKey.pageDown): const NextPage(),
  const SingleActivator(LogicalKeyboardKey.digit0, control: true, includeRepeats: false):
      const FitZoom(FitMode.width),
  const SingleActivator(LogicalKeyboardKey.keyG, control: true, includeRepeats: false):
      UiAction.goToPage,
  const SingleActivator(LogicalKeyboardKey.keyF, control: true, includeRepeats: false):
      UiAction.findInDocument,
  const SingleActivator(LogicalKeyboardKey.keyR, control: true, includeRepeats: false):
      const RotateDocument(),
  const SingleActivator(LogicalKeyboardKey.keyD, control: true, includeRepeats: false):
      const ToggleReadingDarkMode(),

  // Aide
  const SingleActivator(LogicalKeyboardKey.f1, includeRepeats: false): UiAction.toggleHelp,
};

/// Raccourcis saisis par caractère, indépendants de la disposition clavier
/// (AZERTY/QWERTY) : `+` accélère, `-` ralentit, `=` revient à 1×.
const Map<String, PlayerCommand> characterKeymap = {
  '+': SpeedRelative(0.25),
  '-': SpeedRelative(-0.25),
  '=': SetSpeed(1.0),
};
