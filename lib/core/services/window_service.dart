import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../models/window_sizes.dart';

/// Abstraction de la fenêtre native.
///
/// Le core ne dépend jamais directement du plugin : cette interface permet de
/// tester [PlaybackService] sans fenêtre, et de changer d'implémentation par
/// plateforme si nécessaire.
abstract interface class WindowService {
  Future<bool> isFullscreen();
  Future<void> setFullscreen(bool value);
  Future<bool> isAlwaysOnTop();
  Future<void> setAlwaysOnTop(bool value);
  Future<bool> isMaximized();
  Future<void> minimize();
  Future<void> toggleMaximize();
  Future<void> close();
  Future<void> setTitle(String title);
  Future<Rect> getBounds();
  Future<void> setBounds(Rect bounds);

  /// Ramène la fenêtre au premier plan (restaure si réduite), sans changer
  /// sa géométrie. Utilisé quand une seconde instance nous confie un fichier.
  Future<void> focus();

  /// Taille minimale de la fenêtre (le mini-lecteur descend sous celle du
  /// lecteur principal).
  Future<void> setMinimumSize(Size size);

  /// Verrouille le ratio largeur / hauteur de la fenêtre (mini-lecteur
  /// vidéo) ; `ratio <= 0` lève le verrou. Sous Windows, il ne vaut que pour
  /// le redimensionnement à la souris ; sous Linux, le gestionnaire de
  /// fenêtres l'applique aussi aux tailles demandées par le programme.
  Future<void> setAspectRatio(double ratio);

  /// Agrandit la fenêtre, ou lui rend sa taille normale. Se termine une fois
  /// le changement fait : le mini-lecteur lit et pose la géométrie juste
  /// après.
  Future<void> setMaximized(bool value);

  /// Émet à chaque déplacement/redimensionnement/maximisation.
  Stream<void> get geometryChanges;
}

/// Implémentation basée sur `window_manager`.
class WindowManagerService with WindowListener implements WindowService {
  WindowManagerService() {
    windowManager.addListener(this);
  }

  final StreamController<void> _geometry = StreamController<void>.broadcast();

  @override
  Stream<void> get geometryChanges => _geometry.stream;

  @override
  Future<bool> isFullscreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullscreen(bool value) => windowManager.setFullScreen(value);

  @override
  Future<bool> isAlwaysOnTop() => windowManager.isAlwaysOnTop();

  @override
  Future<void> setAlwaysOnTop(bool value) => windowManager.setAlwaysOnTop(value);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> setTitle(String title) => windowManager.setTitle(title);

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);

  @override
  Future<void> focus() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  /// Valeur qui lève le verrou de ratio sur les deux plateformes.
  ///
  /// window_manager 0.5.2 n'a pas de méthode dédiée, et ses greffons ne lisent
  /// pas 0 de la même façon : sous Windows, le ratio n'est appliqué (dans
  /// `WM_SIZING`) que s'il est positif ; sous Linux, toute valeur positive OU
  /// NULLE pose `GDK_HINT_ASPECT`, et 0 imposerait un ratio nul. Seule une
  /// valeur négative retire l'indice : -1 lève le verrou partout.
  static const double _noAspectRatio = -1;

  @override
  Future<void> setAspectRatio(double ratio) =>
      windowManager.setAspectRatio(ratio > 0 ? ratio : _noAspectRatio);

  @override
  Future<void> setMaximized(bool value) async {
    await (value ? windowManager.maximize() : windowManager.unmaximize());
    // window_manager 0.5.2 ne fait que DEMANDER le changement : message posté
    // sous Windows (SC_MAXIMIZE, SC_RESTORE), requête au gestionnaire de
    // fenêtres sous Linux. On attend qu'il ait eu lieu (un tiers de seconde au
    // plus) : la géométrie lue ou posée juste après viserait sinon la fenêtre
    // encore agrandie.
    for (var i = 0; i < 10 && await windowManager.isMaximized() != value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  @override
  void onWindowMoved() => _geometry.add(null);

  /// Sous Linux, window_manager 0.5.2 n'émet jamais « moved » ni « resized »
  /// (macOS et Windows seulement), mais « move » à chaque configure-event :
  /// déplacement comme redimensionnement. Sans lui, rien n'y serait
  /// enregistré après un geste à la souris ; sa cadence est absorbée par la
  /// sauvegarde différée de l'application.
  @override
  void onWindowMove() {
    if (Platform.isLinux) _geometry.add(null);
  }

  @override
  void onWindowResized() => _geometry.add(null);

  @override
  void onWindowMaximize() => _geometry.add(null);

  @override
  void onWindowUnmaximize() => _geometry.add(null);

  void dispose() {
    windowManager.removeListener(this);
    _geometry.close();
  }
}

/// Fenêtre factice pour les tests et les environnements sans plugin.
class FakeWindowService implements WindowService {
  bool fullscreen = false;
  bool alwaysOnTop = false;
  bool maximized = false;
  bool closed = false;
  int focusCount = 0;
  String title = '';
  Rect bounds = const Rect.fromLTWH(0, 0, 1200, 760);

  final StreamController<void> _geometry = StreamController<void>.broadcast();

  @override
  Stream<void> get geometryChanges => _geometry.stream;

  @override
  Future<bool> isFullscreen() async => fullscreen;

  @override
  Future<void> setFullscreen(bool value) async => fullscreen = value;

  @override
  Future<bool> isAlwaysOnTop() async => alwaysOnTop;

  @override
  Future<void> setAlwaysOnTop(bool value) async => alwaysOnTop = value;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> minimize() async {}

  @override
  Future<void> toggleMaximize() async => maximized = !maximized;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<void> setTitle(String value) async => title = value;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<void> setBounds(Rect value) async {
    bounds = value;
    _geometry.add(null);
  }

  @override
  Future<void> focus() async => focusCount++;

  Size minimumSize = WindowSizes.mainMinimum;

  @override
  Future<void> setMinimumSize(Size size) async => minimumSize = size;

  /// Ratio verrouillé, 0 quand aucun verrou n'est posé.
  double aspectRatio = 0;

  @override
  Future<void> setAspectRatio(double ratio) async => aspectRatio = ratio > 0 ? ratio : 0;

  @override
  Future<void> setMaximized(bool value) async => maximized = value;
}
