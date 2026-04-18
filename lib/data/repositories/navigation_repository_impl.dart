/// Concrete implementation of NavigationRepository.
///
/// Coordinates between Firebase (remote) and Hive (local cache)
/// using a cache-first strategy with version-based invalidation.

import '../../core/navigation/models.dart';
import '../../core/navigation/graph.dart';
import '../../domain/repositories/navigation_repository.dart';
import '../datasources/firebase_datasource.dart';
import '../datasources/local_datasource.dart';

class NavigationRepositoryImpl implements NavigationRepository {
  final FirebaseNavigationDatasource _remote;
  final LocalNavigationDatasource _local;

  /// In-memory graph cache (avoids repeated deserialization within a session).
  final Map<String, NavigationGraph> _memoryCache = {};

  NavigationRepositoryImpl({
    required FirebaseNavigationDatasource remote,
    required LocalNavigationDatasource local,
  })  : _remote = remote,
        _local = local;

  @override
  Future<NavigationGraph> getBuildingGraph(String buildingId) async {
    // Level 1: In-memory cache (instant, same session)
    if (_memoryCache.containsKey(buildingId)) {
      return _memoryCache[buildingId]!;
    }

    // Level 2: Hive disk cache (fast, offline capable)
    try {
      final serverVersion = await _remote.getGraphVersion(buildingId);
      final isFresh = await _local.isCacheFresh(buildingId, serverVersion);

      if (isFresh) {
        final cached = await _local.getCachedGraph(buildingId);
        if (cached != null) {
          _memoryCache[buildingId] = cached;
          return cached;
        }
      }
    } catch (_) {
      // Offline — try disk cache even if version is unknown
      final cached = await _local.getCachedGraph(buildingId);
      if (cached != null) {
        _memoryCache[buildingId] = cached;
        return cached;
      }
    }

    // Level 3: Firebase fetch (network)
    final graph = await _remote.fetchBuildingGraph(buildingId);
    _memoryCache[buildingId] = graph;

    // Cache to disk (fire and forget)
    _cacheGraphToDisk(buildingId, graph);

    return graph;
  }

  @override
  Future<List<BuildingInfo>> getAllBuildings() {
    return _remote.getAllBuildings();
  }

  @override
  Future<List<NavNode>> searchDestinations(String query) {
    return _remote.searchDestinations(query);
  }

  @override
  Future<List<QRAnchor>> getQRAnchors(String buildingId) {
    return _remote.getQRAnchors(buildingId);
  }

  @override
  Stream<EdgeStatusUpdate> watchBlockedEdges(String buildingId) {
    return _remote.watchBlockedEdges(buildingId);
  }

  @override
  Future<void> reportBlockedPath(String edgeId, String reason) async {
    // Extract building from edge ID (format: "CS-XXX_to_CS-YYY")
    final parts = edgeId.split('-');
    if (parts.isEmpty) return;
    final buildingId = parts[0].toLowerCase();
    await _remote.reportBlockedPath(buildingId, edgeId, reason);
  }

  @override
  Future<void> invalidateCache(String buildingId) async {
    _memoryCache.remove(buildingId);
    await _local.invalidateCache(buildingId);
  }

  /// Background task: serialize graph to Hive disk cache.
  Future<void> _cacheGraphToDisk(String buildingId, NavigationGraph graph) async {
    try {
      final nodesJson = graph.nodes.map((n) => n.toJson()).toList();
      final edgesJson = graph.allEdges.map((e) => e.toJson()).toList();
      final version = await _remote.getGraphVersion(buildingId);

      await _local.cacheGraph(
        buildingId,
        {'nodes': nodesJson, 'edges': edgesJson},
        version,
      );
    } catch (_) {
      // Non-critical — cache failure doesn't break navigation
    }
  }
}
