import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/history_entry.dart';
import 'local_storage.dart';

/// Mémoire de lecture d'OMNIA : positions reprises et fichiers récents.
abstract interface class HistoryStore {
  /// Ce qui est retenu de [path], ou `null` si le fichier n'a jamais été ouvert.
  HistoryEntry? entryFor(String path);

  /// Enregistre la progression. Les positions trop proches du début ou de la
  /// fin sont effacées plutôt que conservées (voir [HistoryEntry]).
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  });

  /// Marque le fichier comme vu en entier.
  Future<void> markCompleted(String path, {DateTime? now});

  /// Note que le fichier vient d'être ouvert, sans toucher à sa position.
  ///
  /// C'est ce qui l'inscrit dans les récents dès l'ouverture : attendre la
  /// première sauvegarde de position laisserait de côté un fichier fermé
  /// avant la première minute.
  Future<void> touch(String path, {DateTime? now});

  /// Documents : mémorise la page courante et le nombre de pages (PDF), ou la
  /// position de défilement (texte).
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  });

  /// Fichiers récemment ouverts, du plus récent au plus ancien.
  List<HistoryEntry> recent({int limit = 20});

  /// Oublie un fichier.
  Future<void> forget(String path);

  /// Vide la liste des récents, en gardant les positions mémorisées.
  Future<void> clearRecent();

  /// Oublie toutes les positions, en gardant la liste des récents.
  Future<void> clearPositions();

  /// Efface tout l'historique.
  Future<void> clear();
}

/// Implémentation Hive, sur une boîte dédiée.
class HiveHistoryStore implements HistoryStore {
  HiveHistoryStore(this._box);

  final Box<dynamic> _box;

  static const boxName = 'history';

  static Future<HiveHistoryStore> open() async {
    await initialiseLocalStorage();
    return HiveHistoryStore(await Hive.openBox<dynamic>(boxName));
  }

  @override
  HistoryEntry? entryFor(String path) {
    final raw = _box.get(path);
    if (raw is! Map) return null;
    try {
      return HistoryEntry.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      // Entrée écrite par une version antérieure : on l'ignore plutôt que de
      // faire échouer l'ouverture du fichier.
      return null;
    }
  }

  @override
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  }) async {
    final reached = duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >=
            HistoryEntry.completionThreshold;

    if (reached) {
      await markCompleted(path, now: now);
      return;
    }
    if (!HistoryEntry.isWorthSaving(position, duration)) {
      // Trop tôt dans le fichier : on garde une trace « déjà ouvert » sans
      // position, pour la liste des récents.
      final existing = entryFor(path);
      await _put(
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: duration,
          lastOpened: now ?? DateTime.now(),
          completed: existing?.completed ?? false,
        ),
      );
      return;
    }

    await _put(
      HistoryEntry(
        path: path,
        position: position,
        duration: duration,
        lastOpened: now ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<void> markCompleted(String path, {DateTime? now}) async {
    final existing = entryFor(path);
    await _put(
      HistoryEntry(
        path: path,
        position: Duration.zero,
        duration: existing?.duration ?? Duration.zero,
        lastOpened: now ?? DateTime.now(),
        completed: true,
        pageCount: existing?.pageCount ?? 0,
      ),
    );
  }

  Future<void> _put(HistoryEntry entry) => _box.put(entry.path, entry.toJson());

  @override
  Future<void> touch(String path, {DateTime? now}) async {
    final existing = entryFor(path);
    await _put(
      existing?.copyWith(lastOpened: now ?? DateTime.now(), listed: true) ??
          HistoryEntry(
            path: path,
            position: Duration.zero,
            duration: Duration.zero,
            lastOpened: now ?? DateTime.now(),
          ),
    );
  }

  List<HistoryEntry> _all() {
    final entries = <HistoryEntry>[];
    for (final key in _box.keys) {
      final entry = entryFor(key as String);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  @override
  Future<void> clearRecent() async {
    for (final entry in _all()) {
      if (entry.listed) await _put(entry.copyWith(listed: false));
    }
  }

  @override
  Future<void> clearPositions() async {
    for (final entry in _all()) {
      await _put(entry.withoutProgress());
    }
  }

  @override
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  }) async {
    final existing = entryFor(path) ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: now ?? DateTime.now(),
        );
    await _put(
      existing.copyWith(
        page: page,
        pageCount: pageCount,
        scrollFraction: scrollFraction?.clamp(0.0, 1.0),
        lastOpened: now ?? DateTime.now(),
        // Lu jusqu'à la dernière page : on le note, comme pour un média.
        completed: page != null && pageCount != null && pageCount > 0 && page >= pageCount
            ? true
            : existing.completed,
      ),
    );
  }

  @override
  List<HistoryEntry> recent({int limit = 20}) {
    final entries = _all().where((e) => e.listed).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return entries.take(limit).toList();
  }

  @override
  Future<void> forget(String path) => _box.delete(path);

  @override
  Future<void> clear() => _box.clear();
}

/// Implémentation en mémoire, pour les tests.
class MemoryHistoryStore implements HistoryStore {
  final Map<String, HistoryEntry> entries = {};

  @override
  HistoryEntry? entryFor(String path) => entries[path];

  @override
  Future<void> savePosition(
    String path, {
    required Duration position,
    required Duration duration,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final reached = duration > Duration.zero &&
        position.inMilliseconds / duration.inMilliseconds >=
            HistoryEntry.completionThreshold;
    if (reached) {
      await markCompleted(path, now: stamp);
      return;
    }
    if (!HistoryEntry.isWorthSaving(position, duration)) {
      entries[path] = HistoryEntry(
        path: path,
        position: Duration.zero,
        duration: duration,
        lastOpened: stamp,
        completed: entries[path]?.completed ?? false,
      );
      return;
    }
    entries[path] = HistoryEntry(
      path: path,
      position: position,
      duration: duration,
      lastOpened: stamp,
    );
  }

  @override
  Future<void> markCompleted(String path, {DateTime? now}) async {
    final existing = entries[path];
    entries[path] = HistoryEntry(
      path: path,
      position: Duration.zero,
      duration: existing?.duration ?? Duration.zero,
      lastOpened: now ?? DateTime.now(),
      completed: true,
      pageCount: existing?.pageCount ?? 0,
    );
  }

  @override
  Future<void> touch(String path, {DateTime? now}) async {
    final stamp = now ?? DateTime.now();
    entries[path] = entries[path]?.copyWith(lastOpened: stamp, listed: true) ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: stamp,
        );
  }

  @override
  Future<void> clearRecent() async {
    entries.updateAll((_, e) => e.copyWith(listed: false));
  }

  @override
  Future<void> clearPositions() async {
    entries.updateAll((_, e) => e.withoutProgress());
  }

  @override
  Future<void> saveDocumentPosition(
    String path, {
    int? page,
    int? pageCount,
    double? scrollFraction,
    DateTime? now,
  }) async {
    final stamp = now ?? DateTime.now();
    final existing = entries[path] ??
        HistoryEntry(
          path: path,
          position: Duration.zero,
          duration: Duration.zero,
          lastOpened: stamp,
        );
    entries[path] = existing.copyWith(
      page: page,
      pageCount: pageCount,
      scrollFraction: scrollFraction?.clamp(0.0, 1.0),
      lastOpened: stamp,
      completed: page != null && pageCount != null && pageCount > 0 && page >= pageCount
          ? true
          : existing.completed,
    );
  }

  @override
  List<HistoryEntry> recent({int limit = 20}) {
    final list = entries.values.where((e) => e.listed).toList()
      ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return list.take(limit).toList();
  }

  @override
  Future<void> forget(String path) async => entries.remove(path);

  @override
  Future<void> clear() async => entries.clear();
}
