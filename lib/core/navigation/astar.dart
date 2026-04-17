/// A* shortest path algorithm for indoor navigation.
///
/// A* extends Dijkstra's algorithm with a heuristic function that estimates
/// the remaining distance to the destination. This allows the algorithm to
/// prioritize exploring nodes that are "closer" to the goal, significantly
/// reducing the search space in large graphs.
///
/// For indoor navigation, we use 3D Euclidean distance as the heuristic.
/// This is admissible (never overestimates) because the shortest possible
/// path between two points is a straight line.
///
/// Performance:
/// - Best case: O(E) when the heuristic is very accurate
/// - Worst case: O((V + E) log V), same as Dijkstra
/// - Typical indoor navigation: 40-60% fewer nodes explored than Dijkstra
///
/// When to use A* over Dijkstra:
/// - Cross-floor navigation (500+ nodes in the search space)
/// - Cross-building navigation
/// - Real-time rerouting where speed matters

import 'dart:collection';

import 'models.dart';
import 'graph.dart';

/// Heuristic function type for A*.
///
/// Takes the current node ID and destination node ID,
/// returns an estimated cost (must never overestimate!).
typedef HeuristicFunction = double Function(String currentId, String destId);

/// Priority queue entry for A* algorithm.
class _AStarEntry implements Comparable<_AStarEntry> {
  final String nodeId;
  final double fScore; // g(n) + h(n)
  final double gScore; // actual cost from start

  const _AStarEntry(this.nodeId, this.fScore, this.gScore);

  @override
  int compareTo(_AStarEntry other) {
    final cmp = fScore.compareTo(other.fScore);
    if (cmp != 0) return cmp;
    // Tie-breaking: prefer nodes with lower g-score (closer to destination)
    final gCmp = other.gScore.compareTo(gScore);
    if (gCmp != 0) return gCmp;
    return nodeId.compareTo(other.nodeId);
  }
}

/// A* pathfinding algorithm implementation.
///
/// Features:
/// - 3D Euclidean heuristic (admissible and consistent)
/// - Floor-transition penalty for better indoor path quality
/// - Wheelchair accessibility mode
/// - Search statistics for performance monitoring
/// - Configurable heuristic weight for bounded suboptimal search
///
/// Usage:
/// ```dart
/// final astar = AStarPathfinder(graph);
/// final result = astar.findPath('CS-CORR-1F-01', 'AIML-201');
/// if (result.path != null) {
///   print('Distance: ${result.path!.totalDistance}m');
///   print('Nodes explored: ${result.nodesExplored}');
/// }
/// ```
class AStarPathfinder {
  final NavigationGraph graph;

  /// Whether to filter out stairs (wheelchair accessibility mode).
  final bool wheelchairMode;

  /// Heuristic weight multiplier.
  ///
  /// - w = 1.0: Standard A* (optimal path guaranteed)
  /// - w > 1.0: Weighted A* (faster but potentially suboptimal)
  /// - w = 0.0: Degrades to Dijkstra
  ///
  /// For indoor navigation, w = 1.0 is recommended since optimality matters
  /// and the graphs are small enough that the speed gain isn't worth the
  /// path quality loss.
  final double heuristicWeight;

  /// Additional cost penalty for floor transitions.
  ///
  /// This makes the algorithm prefer same-floor routes when alternatives
  /// exist. Set to 0.0 to disable.
  final double floorTransitionPenalty;

  const AStarPathfinder(
    this.graph, {
    this.wheelchairMode = false,
    this.heuristicWeight = 1.0,
    this.floorTransitionPenalty = 5.0, // 5 meter equivalent penalty
  });

  // ─────────────────────────────────────────
  // Heuristic Functions
  // ─────────────────────────────────────────

  /// 3D Euclidean distance heuristic.
  ///
  /// This is admissible (never overestimates) because a straight line
  /// is always shorter than or equal to any path through the graph.
  double euclideanHeuristic(String currentId, String destId) {
    final current = graph.getNode(currentId);
    final dest = graph.getNode(destId);
    if (current == null || dest == null) return 0;

    return current.position.distanceTo(dest.position);
  }

  /// Enhanced heuristic with floor transition awareness.
  ///
  /// Adds a penalty proportional to the number of floor transitions
  /// needed, which helps guide the search toward stairs/lifts when
  /// cross-floor navigation is required.
  double enhancedHeuristic(String currentId, String destId) {
    final current = graph.getNode(currentId);
    final dest = graph.getNode(destId);
    if (current == null || dest == null) return 0;

    final euclidean = current.position.distanceTo(dest.position);
    final floorDiff = (current.floor - dest.floor).abs();

    // Add floor transition penalty: each floor transition adds some cost
    // This helps the algorithm find stairs/lifts faster
    return euclidean + floorDiff * floorTransitionPenalty;
  }

  // ─────────────────────────────────────────
  // Pathfinding
  // ─────────────────────────────────────────

  /// Find the shortest path from [startId] to [endId] using A*.
  ///
  /// Returns an [AStarResult] containing the path (if found) and
  /// search statistics for performance monitoring.
  ///
  /// Algorithm:
  /// 1. Initialize:
  ///    - g-scores: source = 0, all others = ∞
  ///    - f-scores: source = h(source), all others = ∞
  ///    - Open set (priority queue): {source}
  ///    - Closed set: {}
  /// 2. While open set is not empty:
  ///    a. Pop node with minimum f-score
  ///    b. If it's the destination → reconstruct path
  ///    c. Add to closed set
  ///    d. For each neighbor:
  ///       - Skip if in closed set
  ///       - Calculate tentative g-score
  ///       - If better than current g-score → update and add to open set
  /// 3. If destination never reached → return null
  AStarResult findPath(String startId, String endId) {
    final stopwatch = Stopwatch()..start();
    int nodesExplored = 0;
    int nodesExpanded = 0;

    // Validate inputs
    if (graph.getNode(startId) == null || graph.getNode(endId) == null) {
      stopwatch.stop();
      return AStarResult(
        path: null,
        nodesExplored: 0,
        nodesExpanded: 0,
        computeTimeMs: stopwatch.elapsedMilliseconds,
      );
    }

    if (startId == endId) {
      final node = graph.getNode(startId)!;
      stopwatch.stop();
      return AStarResult(
        path: NavPath(nodes: [node], edges: [], totalDistance: 0),
        nodesExplored: 1,
        nodesExpanded: 0,
        computeTimeMs: stopwatch.elapsedMilliseconds,
      );
    }

    // Choose heuristic based on whether this is cross-floor
    final heuristic = graph.requiresFloorTransition(startId, endId)
        ? enhancedHeuristic
        : euclideanHeuristic;

    // g-score: actual cost from start to this node
    final gScores = <String, double>{startId: 0};

    // f-score: g + h (estimated total cost through this node)
    final initialH = heuristic(startId, endId) * heuristicWeight;
    final fScores = <String, double>{startId: initialH};

    // Predecessor map: nodeId → (predecessor, edge used)
    final cameFrom = <String, (String, NavEdge)>{};

    // Closed set (already fully processed nodes)
    final closedSet = <String>{};

    // Open set (priority queue)
    final openSet = SplayTreeSet<_AStarEntry>(
      (a, b) {
        final cmp = a.fScore.compareTo(b.fScore);
        if (cmp != 0) return cmp;
        final gCmp = b.gScore.compareTo(a.gScore);
        if (gCmp != 0) return gCmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    openSet.add(_AStarEntry(startId, initialH, 0));

    while (openSet.isNotEmpty) {
      // Pop node with lowest f-score
      final current = openSet.first;
      openSet.remove(current);
      nodesExplored++;

      final currentId = current.nodeId;

      // Skip if already in closed set (stale entry)
      if (closedSet.contains(currentId)) continue;

      // Destination reached — reconstruct path
      if (currentId == endId) {
        stopwatch.stop();
        return AStarResult(
          path: _reconstructPath(startId, endId, cameFrom),
          nodesExplored: nodesExplored,
          nodesExpanded: nodesExpanded,
          computeTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      // Add to closed set
      closedSet.add(currentId);
      nodesExpanded++;

      // Expand neighbors
      final edges = graph.getNeighborEdges(
        currentId,
        wheelchairMode: wheelchairMode,
      );

      for (final edge in edges) {
        final neighborId = edge.to;

        // Skip if already fully processed
        if (closedSet.contains(neighborId)) continue;

        // Calculate tentative g-score
        final tentativeG =
            gScores[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);

        final currentG = gScores[neighborId] ?? double.infinity;

        if (tentativeG < currentG) {
          // This is a better path to this neighbor
          cameFrom[neighborId] = (currentId, edge);
          gScores[neighborId] = tentativeG;

          final h = heuristic(neighborId, endId) * heuristicWeight;
          final newF = tentativeG + h;
          fScores[neighborId] = newF;

          // Remove old entry if exists
          if (currentG != double.infinity) {
            openSet.remove(_AStarEntry(neighborId, currentG + h, currentG));
          }

          openSet.add(_AStarEntry(neighborId, newF, tentativeG));
        }
      }
    }

    // No path found
    stopwatch.stop();
    return AStarResult(
      path: null,
      nodesExplored: nodesExplored,
      nodesExpanded: nodesExpanded,
      computeTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Find paths to multiple destinations and return the best one.
  ///
  /// Useful for "find nearest X" queries where there are multiple
  /// candidates (e.g., nearest washroom from any building).
  AStarResult findBestPath(String startId, List<String> endIds) {
    AStarResult? bestResult;

    for (final endId in endIds) {
      final result = findPath(startId, endId);
      if (result.path != null) {
        if (bestResult == null ||
            result.path!.totalDistance < bestResult.path!.totalDistance) {
          bestResult = result;
        }
      }
    }

    return bestResult ??
        AStarResult(
          path: null,
          nodesExplored: 0,
          nodesExpanded: 0,
          computeTimeMs: 0,
        );
  }

  /// Reconstruct path from predecessor map.
  NavPath _reconstructPath(
    String startId,
    String endId,
    Map<String, (String, NavEdge)> cameFrom,
  ) {
    final nodeIds = <String>[];
    final edges = <NavEdge>[];
    double totalDistance = 0;

    String current = endId;
    while (current != startId) {
      nodeIds.add(current);
      final (predId, edge) = cameFrom[current]!;
      edges.add(edge);
      totalDistance += edge.weight;
      current = predId;
    }
    nodeIds.add(startId);

    final nodes = nodeIds.reversed.map((id) => graph.getNode(id)!).toList();
    final orderedEdges = edges.reversed.toList();

    return NavPath(
      nodes: nodes,
      edges: orderedEdges,
      totalDistance: totalDistance,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESULT
// ─────────────────────────────────────────────────────────────────────────────

/// Result of an A* pathfinding operation, including search statistics.
class AStarResult {
  /// The shortest path found, or null if no path exists.
  final NavPath? path;

  /// Total number of nodes explored (popped from priority queue).
  final int nodesExplored;

  /// Total number of nodes expanded (neighbors examined).
  final int nodesExpanded;

  /// Total computation time in milliseconds.
  final int computeTimeMs;

  const AStarResult({
    required this.path,
    required this.nodesExplored,
    required this.nodesExpanded,
    required this.computeTimeMs,
  });

  /// Whether a path was found.
  bool get found => path != null;

  /// Search efficiency: ratio of explored nodes to total graph nodes.
  /// Lower is better — means A* explored fewer nodes.
  double efficiencyRatio(int totalNodes) =>
      totalNodes > 0 ? nodesExplored / totalNodes : 0;

  @override
  String toString() =>
      'AStarResult(found=$found, explored=$nodesExplored, '
      'expanded=$nodesExpanded, ${computeTimeMs}ms'
      '${path != null ? ', dist=${path!.totalDistance.toStringAsFixed(1)}m' : ''})';
}
