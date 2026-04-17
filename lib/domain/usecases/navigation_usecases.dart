/// Domain use cases — single-responsibility operations that
/// compose repository data with business logic.

import '../../core/navigation/models.dart';
import '../../core/navigation/graph.dart';
import '../../core/navigation/astar.dart';
import '../../core/navigation/dijkstra.dart';
import '../repositories/navigation_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// USE CASE: Navigate To Destination
// ─────────────────────────────────────────────────────────────────────────────

/// Computes the optimal path from the user's current position to a destination.
///
/// Orchestrates:
/// 1. Graph loading (from cache or Firebase)
/// 2. Algorithm selection (Dijkstra vs A*)
/// 3. Path computation
/// 4. Result packaging with metadata
class NavigateToDestinationUseCase {
  final NavigationRepository _repository;

  const NavigateToDestinationUseCase(this._repository);

  Future<NavigationResult> execute({
    required String fromNodeId,
    required String toNodeId,
    required String buildingId,
    bool wheelchairMode = false,
  }) async {
    // 1. Load graph
    final graph = await _repository.getBuildingGraph(buildingId);

    // 2. Validate nodes exist
    final fromNode = graph.getNode(fromNodeId);
    final toNode = graph.getNode(toNodeId);

    if (fromNode == null) {
      return NavigationResult.failure('Source node "$fromNodeId" not found.');
    }
    if (toNode == null) {
      return NavigationResult.failure('Destination "$toNodeId" not found.');
    }

    // 3. Select algorithm
    final isCrossFloor = fromNode.floor != toNode.floor;
    final stopwatch = Stopwatch()..start();

    NavPath? path;
    String algorithm;
    int nodesExplored = 0;

    if (isCrossFloor || graph.nodeCount > 100) {
      algorithm = 'A*';
      final astar = AStarPathfinder(graph, wheelchairMode: wheelchairMode);
      final result = astar.findPathWithStats(fromNodeId, toNodeId);
      path = result.path;
      nodesExplored = result.nodesExplored;
    } else {
      algorithm = 'Dijkstra';
      final dijkstra = DijkstraPathfinder(graph, wheelchairMode: wheelchairMode);
      path = dijkstra.findPath(fromNodeId, toNodeId);
    }

    stopwatch.stop();

    if (path == null) {
      return NavigationResult.failure(
        'No path found from "${fromNode.displayName}" to "${toNode.displayName}". '
        '${wheelchairMode ? "Try disabling wheelchair mode — stairs may be the only route." : "Some corridors may be blocked."}',
      );
    }

    return NavigationResult.success(
      path: path,
      algorithm: algorithm,
      computeTimeMs: stopwatch.elapsedMilliseconds,
      nodesExplored: nodesExplored,
      graph: graph,
    );
  }
}

/// Result of a navigation computation.
class NavigationResult {
  final bool isSuccess;
  final NavPath? path;
  final String? errorMessage;
  final String? algorithm;
  final int computeTimeMs;
  final int nodesExplored;
  final NavigationGraph? graph;

  const NavigationResult._({
    required this.isSuccess,
    this.path,
    this.errorMessage,
    this.algorithm,
    this.computeTimeMs = 0,
    this.nodesExplored = 0,
    this.graph,
  });

  factory NavigationResult.success({
    required NavPath path,
    required String algorithm,
    required int computeTimeMs,
    required int nodesExplored,
    required NavigationGraph graph,
  }) {
    return NavigationResult._(
      isSuccess: true,
      path: path,
      algorithm: algorithm,
      computeTimeMs: computeTimeMs,
      nodesExplored: nodesExplored,
      graph: graph,
    );
  }

  factory NavigationResult.failure(String message) {
    return NavigationResult._(isSuccess: false, errorMessage: message);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USE CASE: Search Destinations
// ─────────────────────────────────────────────────────────────────────────────

/// Searches for navigable destinations across the campus.
class SearchDestinationsUseCase {
  final NavigationRepository _repository;

  const SearchDestinationsUseCase(this._repository);

  Future<List<NavNode>> execute(String query) async {
    if (query.trim().isEmpty) return [];
    return _repository.searchDestinations(query.trim());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USE CASE: Get Building Info
// ─────────────────────────────────────────────────────────────────────────────

/// Retrieves all buildings on campus.
class GetBuildingsUseCase {
  final NavigationRepository _repository;

  const GetBuildingsUseCase(this._repository);

  Future<List<BuildingInfo>> execute() async {
    return _repository.getAllBuildings();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USE CASE: Watch Blocked Edges
// ─────────────────────────────────────────────────────────────────────────────

/// Streams real-time blocked edge updates for a building.
class WatchBlockedEdgesUseCase {
  final NavigationRepository _repository;

  const WatchBlockedEdgesUseCase(this._repository);

  Stream<EdgeStatusUpdate> execute(String buildingId) {
    return _repository.watchBlockedEdges(buildingId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USE CASE: Find Nearest Amenity
// ─────────────────────────────────────────────────────────────────────────────

/// Finds the nearest node of a specific type (washroom, stairs, lift).
class FindNearestAmenityUseCase {
  final NavigationRepository _repository;

  const FindNearestAmenityUseCase(this._repository);

  Future<NavPath?> execute({
    required String fromNodeId,
    required String buildingId,
    required NodeType amenityType,
    bool wheelchairMode = false,
  }) async {
    final graph = await _repository.getBuildingGraph(buildingId);
    final dijkstra = DijkstraPathfinder(graph, wheelchairMode: wheelchairMode);
    return dijkstra.findNearestOfType(fromNodeId, amenityType);
  }
}
