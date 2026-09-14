import 'dart:ui';

import 'package:hive_ce_flutter/hive_flutter.dart';

import 'local_storage.dart';

/// Clés de persistance. Centralisées pour éviter les chaînes magiques.
abstract final class SettingsKeys {
  static const windowBounds = 'window.bounds';
  static const windowMaximized = 'window.maximized';
  static const sidePanelVisible = 'panel.visible';
  static const sidePanelWidth = 'panel.width';
  static const playlistSort = 'playlist.sort';
  static const playlistDescending = 'playlist.descending';
  static const endOfPlaybackMode = 'playback.endMode';
  static const screenshotFolder = 'screenshots.folder';
}

/// Préférences persistantes d'OMNIA.
///
/// Interface minimale en Phase 1 (géométrie de fenêtre) ; les phases suivantes
/// ajoutent positions de lecture, historique et paramètres.
abstract interface class SettingsStore {
  Rect? get windowBounds;
  Future<void> setWindowBounds(Rect bounds);

  bool get windowMaximized;
  Future<void> setWindowMaximized(bool value);

  /// Le panneau de dossier est déployé.
  bool get sidePanelVisible;
  Future<void> setSidePanelVisible(bool value);

  /// Largeur du panneau, bornée par l'appelant.
  double get sidePanelWidth;
  Future<void> setSidePanelWidth(double value);

  /// Tri du panneau, conservé d'une session à l'autre.
  String? get playlistSort;
  bool get playlistDescending;
  Future<void> setPlaylistSort(String sort, bool descending);

  /// Comportement en fin de lecture.
  String? get endOfPlaybackMode;
  Future<void> setEndOfPlaybackMode(String mode);

  /// Dossier des captures d'écran ; `null` = dossier par défaut du système.
  String? get screenshotFolder;
  Future<void> setScreenshotFolder(String? path);
}

/// Implémentation Hive (fichier local dans le dossier de données de l'app).
class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore._(this._box);

  final Box<dynamic> _box;

  static const boxName = 'settings';

  /// Initialise Hive et ouvre la boîte des préférences.
  static Future<HiveSettingsStore> open() async {
    await initialiseLocalStorage();
    final box = await Hive.openBox<dynamic>(boxName);
    return HiveSettingsStore._(box);
  }

  @override
  Rect? get windowBounds {
    final raw = _box.get(SettingsKeys.windowBounds);
    if (raw is! List || raw.length != 4) return null;
    final v = raw.map((e) => (e as num).toDouble()).toList();
    if (v[2] < 200 || v[3] < 150) return null;
    return Rect.fromLTWH(v[0], v[1], v[2], v[3]);
  }

  @override
  Future<void> setWindowBounds(Rect b) => _box.put(
        SettingsKeys.windowBounds,
        <double>[b.left, b.top, b.width, b.height],
      );

  @override
  bool get windowMaximized =>
      _box.get(SettingsKeys.windowMaximized, defaultValue: false) as bool;

  @override
  Future<void> setWindowMaximized(bool value) =>
      _box.put(SettingsKeys.windowMaximized, value);

  @override
  bool get sidePanelVisible =>
      _box.get(SettingsKeys.sidePanelVisible, defaultValue: true) as bool;

  @override
  Future<void> setSidePanelVisible(bool value) =>
      _box.put(SettingsKeys.sidePanelVisible, value);

  @override
  double get sidePanelWidth =>
      (_box.get(SettingsKeys.sidePanelWidth) as num?)?.toDouble() ?? 0;

  @override
  Future<void> setSidePanelWidth(double value) =>
      _box.put(SettingsKeys.sidePanelWidth, value);

  @override
  String? get playlistSort => _box.get(SettingsKeys.playlistSort) as String?;

  @override
  bool get playlistDescending =>
      _box.get(SettingsKeys.playlistDescending, defaultValue: false) as bool;

  @override
  Future<void> setPlaylistSort(String sort, bool descending) async {
    await _box.put(SettingsKeys.playlistSort, sort);
    await _box.put(SettingsKeys.playlistDescending, descending);
  }

  @override
  String? get endOfPlaybackMode =>
      _box.get(SettingsKeys.endOfPlaybackMode) as String?;

  @override
  Future<void> setEndOfPlaybackMode(String mode) =>
      _box.put(SettingsKeys.endOfPlaybackMode, mode);

  @override
  String? get screenshotFolder => _box.get(SettingsKeys.screenshotFolder) as String?;

  @override
  Future<void> setScreenshotFolder(String? path) => path == null
      ? _box.delete(SettingsKeys.screenshotFolder)
      : _box.put(SettingsKeys.screenshotFolder, path);
}

/// Implémentation en mémoire pour les tests.
class MemorySettingsStore implements SettingsStore {
  Rect? _bounds;
  bool _maximized = false;
  bool _panelVisible = true;
  double _panelWidth = 0;
  String? _sort;
  bool _descending = false;
  String? _endMode;

  @override
  Rect? get windowBounds => _bounds;

  @override
  Future<void> setWindowBounds(Rect bounds) async => _bounds = bounds;

  @override
  bool get windowMaximized => _maximized;

  @override
  Future<void> setWindowMaximized(bool value) async => _maximized = value;

  @override
  bool get sidePanelVisible => _panelVisible;

  @override
  Future<void> setSidePanelVisible(bool value) async => _panelVisible = value;

  @override
  double get sidePanelWidth => _panelWidth;

  @override
  Future<void> setSidePanelWidth(double value) async => _panelWidth = value;

  @override
  String? get playlistSort => _sort;

  @override
  bool get playlistDescending => _descending;

  @override
  Future<void> setPlaylistSort(String sort, bool descending) async {
    _sort = sort;
    _descending = descending;
  }

  @override
  String? get endOfPlaybackMode => _endMode;

  @override
  Future<void> setEndOfPlaybackMode(String mode) async => _endMode = mode;

  String? _screenshotFolder;

  @override
  String? get screenshotFolder => _screenshotFolder;

  @override
  Future<void> setScreenshotFolder(String? path) async => _screenshotFolder = path;
}
