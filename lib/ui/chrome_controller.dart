import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/omnia_theme.dart';

/// Visibilité des contrôles posés sur le média : barre de lecture, languette
/// du panneau de fichiers.
///
/// Quand le masquage automatique est actif, ils disparaissent après quelques
/// secondes sans mouvement de souris, et reviennent au premier mouvement :
/// le média garde toute la place. Ce comportement vaut dans tous les modes
/// d'affichage (fenêtre, petite fenêtre, plein écran, mini-lecteur).
///
/// Ce qui demande l'attention de l'utilisateur les retient visibles : le
/// pointeur posé sur la barre, un menu ouvert, un panneau d'outils, un
/// glissement sur la barre de progression. Chaque source pose une « retenue »
/// nommée et la lève elle-même quand elle se termine.
///
/// État purement visuel : il reste dans l'UI, hors du core et du bus.
class ChromeController extends Notifier<bool> {
  Timer? _timer;
  bool _autoHide = false;

  /// Vrai quand un simple mouvement de souris réveille les contrôles.
  ///
  /// Faux pour un document : on y passe son temps à bouger le pointeur et à
  /// faire défiler, si bien que la barre ne s'effaçait jamais et mangeait le
  /// bas de l'écran en permanence. Seul un clic la rappelle alors.
  bool _pointerWakes = true;

  /// Délai avant effacement. Plus long pour un document, qu'on lit sans rien
  /// toucher : s'effacer trop vite y serait aussi gênant que ne jamais le
  /// faire.
  Duration _delay = OmniaMotion.idleHide;
  final Set<Object> _holds = {};
  final Stopwatch _sinceArm = Stopwatch();

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return true;
  }

  /// Vrai si les contrôles peuvent se masquer d'eux-mêmes.
  bool get autoHide => _autoHide;

  /// Active ou coupe le masquage automatique. Coupé, les contrôles restent
  /// affichés.
  void setAutoHide(
    bool enabled, {
    bool pointerWakes = true,
    Duration? delay,
  }) {
    _autoHide = enabled;
    _pointerWakes = pointerWakes;
    _delay = delay ?? OmniaMotion.idleHide;
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      _show();
      return;
    }
    _arm();
  }

  /// Mouvement ou clic de souris : les contrôles reviennent, et le délai
  /// repart de zéro.
  void activity() {
    // Un document ne se réveille pas au mouvement : seul [tap] le fait.
    if (!_pointerWakes) return;
    _show();
    // Un mouvement de souris produit des dizaines d'événements par seconde :
    // le délai n'est relancé qu'une fois toutes les 200 ms.
    if (_timer != null && _sinceArm.elapsedMilliseconds < 200) return;
    _arm();
  }

  /// Clic ou toucher : les contrôles reviennent, quel que soit le média.
  ///
  /// C'est le seul geste qui les rappelle sur un document, où bouger et faire
  /// défiler ne comptent pas comme une activité.
  void tap() {
    _show();
    _arm();
  }

  /// Pointeur sorti de la zone du média : les contrôles s'effacent plus vite,
  /// comme dans mpv.
  void pointerLeft() {
    _timer?.cancel();
    _timer = null;
    if (!_autoHide || _holds.isNotEmpty) return;
    _timer = Timer(OmniaMotion.chromeLeaveHide, _hide);
  }

  /// Retient les contrôles visibles tant que [reason] n'est pas levée.
  void hold(Object reason) {
    _holds.add(reason);
    _timer?.cancel();
    _timer = null;
    _show();
  }

  /// Lève la retenue [reason] ; le délai de masquage repart.
  void release(Object reason) {
    if (_holds.remove(reason)) _arm();
  }

  void _show() {
    if (!state) state = true;
  }

  void _hide() {
    _timer = null;
    state = false;
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    _sinceArm
      ..reset()
      ..start();
    if (!_autoHide || _holds.isNotEmpty) return;
    _timer = Timer(_delay, _hide);
  }
}

final chromeProvider = NotifierProvider<ChromeController, bool>(ChromeController.new);
