/// Local data source using Hive for offline graph caching.
///
/// Stores serialized navigation graphs so the app works offline
/// after the first load. Cache invalidation is version-based:
/// each building has a graph_version counter in Firestore.

import 'dart:convert';
import 'package:hive/hive.dart';
import '../../core/navigation/graph.dart';

class LocalNavigationDatasource {
  static const String _boxName = 'navigation_cache';
  static const String _versionBoxName = 'cache_versions';

  late Box<String> _graphBox;
  late Box<int> _versionBox;
  bool _isInitialized = false;

  /// Initialize Hive boxes. Call once at app startup.
  Future<void> init() async {
    if (_isInitialized) return;
    _graphBox = await Hive.openBox<String>(_boxName);
    _versionBox = await Hive.openBox<int>(_versionBoxName);
    _isInitialized = true;
  }

  /// Get a cached graph for a building. Returns null if no cache exists.
  Future<NavigationGraph?> getCachedGraph(String buildingId) async {
    await init();
    final jsonString = _graphBox.get(buildingId);
    if (jsonString == null) return null;

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return NavigationGraph.fromJson(json);
    } catch (e) {
      // Corrupted cache — delete and return null
      await _graphBox.delete(buildingId);
      return null;
    }
  }

  /// Cache a graph for a building.
  Future<void> cacheGraph(
    String buildingId,
    Map<String, dynamic> graphJson,
    int version,
  ) async {
    await init();
    await _graphBox.put(buildingId, jsonEncode(graphJson));
    await _versionBox.put(buildingId, version);
  }

  /// Get the cached graph version for a building.
  Future<int> getCachedVersion(String buildingId) async {
    await init();
    return _versionBox.get(buildingId) ?? 0;
  }

  /// Check if the cache is fresh (versions match).
  Future<bool> isCacheFresh(String buildingId, int serverVersion) async {
    final cachedVersion = await getCachedVersion(buildingId);
    return cachedVersion == serverVersion && cachedVersion > 0;
  }

  /// Invalidate cache for a building.
  Future<void> invalidateCache(String buildingId) async {
    await init();
    await _graphBox.delete(buildingId);
    await _versionBox.delete(buildingId);
  }

  /// Clear all cached data.
  Future<void> clearAll() async {
    await init();
    await _graphBox.clear();
    await _versionBox.clear();
  }
}
