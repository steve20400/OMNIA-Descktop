import 'dart:io';
import 'dart:ui';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/app_preferences.dart';
import 'local_storage.dart';
import 'single_instance.dart';

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
  static const preferences = 'preferences';
  static const lastVolume = 'playback.lastVolume';
  static const keymapOverrides = 'keymap.overrides';
}

/// Préférences persistantes d'OMNIA : réglages de l'utilisateur, et état
/// d'interface à retrouver d'une session à l'autre.
abstract interface class SettingsStore {
  /// Réglages de l'écran Paramètres.
  AppPreferences get preferences;
  Future<void> setPreferences(AppPreferences value);

  /// Dernier volume utilisé, pour « volume au démarrage : dernier ».
  double? get lastVolume;
  Future<void> setLastVolume(double value);

  /// Raccourcis modifiés par l'utilisateur (seuls les écarts aux défauts).
  Map<String, Object?> get keymapOverrides;
  Future<void> setKeymapOverrides(Map<String, Object?> value);

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
  HiveSettingsStore._(this._box, this._dataDirectory);

  final Box<dynamic> _box;

  /// Dossier de données, où vit le marqueur « plusieurs instances ».
  final Directory? _dataDirectory;

  static const boxName = 'settings';

  /// Initialise Hive et ouvre la boîte des préférences.
  static Future<HiveSettingsStore> open() async {
    await initialiseLocalStorage();
    final box = await Hive.openBox<dynamic>(boxName);
    return HiveSettingsStore._(box, await localStorageDirectory());
  }

  @override
  AppPreferences get preferences {
    final raw = _box.get(SettingsKeys.preferences);
    if (raw is! Map) return AppPreferences.defaults;
    try {
      return AppPreferences.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      return AppPreferences.defaults;
    }
  }

  @override
  Future<void> setPreferences(AppPreferences value) async {
    await _box.put(SettingsKeys.preferences, value.toJson());
    // L'instance unique se décide avant l'ouverture de Hive : le réglage est
    // aussi reflété par un fichier marqueur, et les préférences par une copie
    // en clair, lisibles sans base de données.
    final dir = _dataDirectory;
    if (dir != null) {
      await writeSingleInstancePreference(dir, enabled: value.singleInstance);
      await writePreferencesSnapshot(dir, value);
    }
  }

  @override
  double? get lastVolume => (_box.get(SettingsKeys.lastVolume) as num?)?.toDouble();

  @override
  Future<void> setLastVolume(double value) => _box.put(SettingsKeys.lastVolume, value);

  @override
  Map<String, Object?> get keymapOverrides {
    final raw = _box.get(SettingsKeys.keymapOverrides);
    if (raw is! Map) return const {};
    return Map<String, Object?>.from(raw);
  }

  @override
  Future<void> setKeymapOverrides(Map<String, Object?> value) =>
      value.isEmpty ? _box.delete(SettingsKeys.keymapOverrides) : _box.put(SettingsKeys.keymapOverrides, value);

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

/// Implémentation en mémoire : tests, et repli quand le stockage local est
/// déjà tenu par une autre instance.
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore({AppPreferences? preferences}) {
    if (preferences != null) _preferences = preferences;
  }

  AppPreferences _preferences = AppPreferences.defaults;
  double? _lastVolume;
  Map<String, Object?> _keymap = const {};

  @override
  AppPreferences get preferences => _preferences;

  @override
  Future<void> setPreferences(AppPreferences value) async => _preferences = value;

  @override
  double? get lastVolume => _lastVolume;

  @override
  Future<void> setLastVolume(double value) async => _lastVolume = value;

  @override
  Map<String, Object?> get keymapOverrides => _keymap;

  @override
  Future<void> setKeymapOverrides(Map<String, Object?> value) async =>
      _keymap = Map.unmodifiable(value);

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
