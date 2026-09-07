import 'dart:ui';

import 'package:hive_ce_flutter/hive_flutter.dart';

/// Clés de persistance. Centralisées pour éviter les chaînes magiques.
abstract final class SettingsKeys {
  static const windowBounds = 'window.bounds';
  static const windowMaximized = 'window.maximized';
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
}

/// Implémentation Hive (fichier local dans le dossier de données de l'app).
class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore._(this._box);

  final Box<dynamic> _box;

  static const boxName = 'settings';

  /// Initialise Hive et ouvre la boîte des préférences.
  static Future<HiveSettingsStore> open() async {
    await Hive.initFlutter('omnia');
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
}

/// Implémentation en mémoire pour les tests.
class MemorySettingsStore implements SettingsStore {
  Rect? _bounds;
  bool _maximized = false;

  @override
  Rect? get windowBounds => _bounds;

  @override
  Future<void> setWindowBounds(Rect bounds) async => _bounds = bounds;

  @override
  bool get windowMaximized => _maximized;

  @override
  Future<void> setWindowMaximized(bool value) async => _maximized = value;
}
