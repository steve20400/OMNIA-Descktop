import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

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
  void onWindowMoved() => _geometry.add(null);

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
}
