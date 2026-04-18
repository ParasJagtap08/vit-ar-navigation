/// Dijkstra's shortest path algorithm for indoor navigation.
///
/// Guaranteed to find the optimal shortest path in graphs with
/// non-negative edge weights. Best suited for same-floor navigation
/// where the search space is small (≤ 100 nodes).
///
/// For cross-floor or large graph scenarios, prefer A* which uses
/// a heuristic to prune the search space.
///
/// Time complexity: O((V + E) log V) with binary heap priority queue.
/// Space complexity: O(V) for distance and predecessor maps.

import 'dart:collection';

import 'models.dart';
import 'graph.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRIORITY QUEUE ENTRY
// ─────────────────────────────────────────────────────────────────────────────

/// Min-heap entry for the priority queue.
///
/// Sorted by [distance] (ascending). Ties broken by [nodeId] to ensure
/// deterministic ordering in the [SplayTreeSet].
class _PQEntry implements Comparable<_PQEntry> {
  final String nodeId;
  final double distance;

  const _PQEntry(this.nodeId, this.distance);

  @override
  int compareTo(_PQEntry other) {
    final cmp = distance.compareTo(other.distance);
    if (cmp != 0) return cmp;
    return nodeId.compareTo(other.nodeId); // stable tie-breaking
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIJKSTRA PATHFINDER
// ─────────────────────────────────────────────────────────────────────────────

/// Dijkstra's shortest path algorithm implementation.
///
/// Features:
/// - Returns the full node path as `List<String>` (node IDs in order)
/// - Ignores blocked / disabled edges automatically
/// - Handles unreachable destinations (returns empty list)
/// - Wheelchair accessibility mode (filters out stairs)
/// - Early termination when destination is reached
/// - "Find nearest of type" query (e.g. nearest washroom)
///
/// ```dart
/// final dijkstra = DijkstraPathfinder(graph);
///
/// // Basic: get the node-ID path
/// final path = dijkstra.findShortestPath(graph, 'CS-ENT-1F', 'CS-103');
/// // → ['CS-ENT-1F', 'CS-CORR-1F-01', 'CS-CORR-1F-02', 'CS-CORR-1F-03', 'CS-103']
///
/// // Full: get NavPath with distance, edges, and ETA
/// final navPath = dijkstra.findPath('CS-ENT-1F', 'CS-103');
/// print(navPath?.totalDistance); // 30.1
/// ```
class DijkstraPathfinder {
  final NavigationGraph graph;

  /// When true, stairs edges are excluded from pathfinding.
  final bool wheelchairMode;

  const DijkstraPathfinder(
    this.graph, {
    this.wheelchairMode = false,
  });

  // ─────────────────────────────────────────
  // Primary API: findShortestPath
  // ─────────────────────────────────────────

  /// Find the shortest path between [start] and [end].
  ///
  /// Returns an ordered `List<String>` of node IDs from source to
  /// destination. Returns an **empty list** if:
  /// - [start] or [end] doesn't exist in the graph
  /// - No path exists (destination is unreachable)
  ///
  /// Blocked edges are automatically skipped — the algorithm only
  /// traverses edges where `edge.isActive == true`.
  ///
  /// **Algorithm:**
  /// 1. Initialize distances: source = 0, all others = ∞
  /// 2. Push source into priority queue (min-heap)
  /// 3. While queue is not empty:
  ///    a. Pop the node with minimum distance
  ///    b. If it's the destination → reconstruct and return path
  ///    c. For each active neighbor edge:
  ///       - Calculate new distance through current node
  ///       - If shorter than known distance → update and push
  /// 4. If destination never reached → return empty list
  ///
  /// Time complexity: O((V + E) log V)
  List<String> findShortestPath(
    NavigationGraph graph,
    String start,
    String end,
  ) {
    // ── Validate inputs ──
    if (!graph.hasNode(start) || !graph.hasNode(end)) {
      return []; // Invalid node IDs
    }
    if (start == end) {
      return [start]; // Already at destination
    }

    // ── Data structures ──

    // Best known distance from [start] to each node
    final distances = <String, double>{start: 0.0};

    // Predecessor map: nodeId → previous nodeId on shortest path
    final predecessors = <String, String>{};

    // Visited set — once a node is finalized, we never revisit it
    final visited = <String>{};

    // Priority queue — always pops the node with smallest distance
    final pq = SplayTreeSet<_PQEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    pq.add(_PQEntry(start, 0.0));

    // ── Main loop ──
    while (pq.isNotEmpty) {
      // Pop minimum-distance node
      final current = pq.first;
      pq.remove(current);

      final currentId = current.nodeId;

      // Skip stale entries (already processed via a shorter path)
      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      // Early termination: destination reached
      if (currentId == end) {
        return _reconstructPath(start, end, predecessors);
      }

      // Explore all active neighbors
      final neighbors = graph.getNeighbors(
        currentId,
        wheelchairMode: wheelchairMode,
      );

      for (final edge in neighbors) {
        final neighborId = edge.to;

        // Skip already-finalized nodes
        if (visited.contains(neighborId)) continue;

        // Calculate distance through current node
        final newDist = distances[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);

        final currentBest = distances[neighborId] ?? double.infinity;

        // Found a shorter path to this neighbor
        if (newDist < currentBest) {
          // Remove old entry from PQ if it exists
          if (distances.containsKey(neighborId)) {
            pq.remove(_PQEntry(neighborId, currentBest));
          }

          distances[neighborId] = newDist;
          predecessors[neighborId] = currentId;
          pq.add(_PQEntry(neighborId, newDist));
        }
      }
    }

    // Destination is unreachable
    return [];
  }

  // ─────────────────────────────────────────
  // Rich API: findPath (returns NavPath)
  // ─────────────────────────────────────────

  /// Find the shortest path and return a full [NavPath] object.
  ///
  /// Returns `null` if no path exists.
  /// The returned [NavPath] includes:
  /// - Ordered list of [NavNode] objects
  /// - Ordered list of [NavEdge] objects traversed
  /// - Total distance in meters
  /// - Estimated time (via `navPath.estimatedTimeSeconds`)
  NavPath? findPath(String startId, String endId) {
    // Use the core algorithm
    final pathIds = findShortestPath(graph, startId, endId);

    // Handle unreachable / invalid
    if (pathIds.isEmpty) return null;

    // Single node — already at destination
    if (pathIds.length == 1) {
      final node = graph.getNode(pathIds.first)!;
      return NavPath(nodes: [node], edges: [], totalDistance: 0);
    }

    // Build the full NavPath with nodes, edges, and total distance
    return _buildNavPath(pathIds);
  }

  // ─────────────────────────────────────────
  // Utility: Find All Distances
  // ─────────────────────────────────────────

  /// Compute shortest distances from [startId] to ALL reachable nodes.
  ///
  /// Useful for:
  /// - Finding the nearest washroom/stairs/lift
  /// - Pre-computing distance matrices
  /// - Graph analysis and diagnostics
  ///
  /// Time complexity: O((V + E) log V) — full Dijkstra without early termination.
  Map<String, double> findAllDistances(String startId) {
    if (!graph.hasNode(startId)) return {};

    final distances = <String, double>{startId: 0.0};
    final visited = <String>{};
    final pq = SplayTreeSet<_PQEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    pq.add(_PQEntry(startId, 0.0));

    while (pq.isNotEmpty) {
      final current = pq.first;
      pq.remove(current);
      final currentId = current.nodeId;

      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      for (final edge
          in graph.getNeighbors(currentId, wheelchairMode: wheelchairMode)) {
        final neighborId = edge.to;
        if (visited.contains(neighborId)) continue;

        final newDist = distances[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);
        final currentBest = distances[neighborId] ?? double.infinity;

        if (newDist < currentBest) {
          if (distances.containsKey(neighborId)) {
            pq.remove(_PQEntry(neighborId, currentBest));
          }
          distances[neighborId] = newDist;
          pq.add(_PQEntry(neighborId, newDist));
        }
      }
    }

    return distances;
  }

  // ─────────────────────────────────────────
  // Utility: Find Nearest of Type
  // ─────────────────────────────────────────

  /// Find the nearest node of a specific [NodeType] from [startId].
  ///
  /// Expands outward from [startId] using Dijkstra and returns the
  /// path to the first node matching [targetType].
  ///
  /// ```dart
  /// final path = dijkstra.findNearestOfType('CS-CORR-1F-01', NodeType.washroom);
  /// // Returns path to the closest washroom
  /// ```
  ///
  /// Returns `null` if no node of [targetType] is reachable.
  NavPath? findNearestOfType(String startId, NodeType targetType) {
    if (!graph.hasNode(startId)) return null;

    final distances = <String, double>{startId: 0.0};
    final predecessors = <String, String>{};
    final visited = <String>{};
    final pq = SplayTreeSet<_PQEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    pq.add(_PQEntry(startId, 0.0));

    while (pq.isNotEmpty) {
      final current = pq.first;
      pq.remove(current);
      final currentId = current.nodeId;

      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      // Check if this node matches the target type (skip start node)
      final node = graph.getNode(currentId);
      if (node != null && node.type == targetType && currentId != startId) {
        final pathIds = _reconstructPath(startId, currentId, predecessors);
        return _buildNavPath(pathIds);
      }

      for (final edge
          in graph.getNeighbors(currentId, wheelchairMode: wheelchairMode)) {
        final neighborId = edge.to;
        if (visited.contains(neighborId)) continue;

        final newDist = distances[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);
        final currentBest = distances[neighborId] ?? double.infinity;

        if (newDist < currentBest) {
          if (distances.containsKey(neighborId)) {
            pq.remove(_PQEntry(neighborId, currentBest));
          }
          distances[neighborId] = newDist;
          predecessors[neighborId] = currentId;
          pq.add(_PQEntry(neighborId, newDist));
        }
      }
    }

    return null; // No node of target type reachable
  }

  // ─────────────────────────────────────────
  // Path Reconstruction
  // ─────────────────────────────────────────

  /// Reconstruct the path from [start] to [end] using the predecessors map.
  ///
  /// Traces backward from [end] to [start] via the predecessor chain,
  /// then reverses to produce a source → destination ordered list.
  ///
  /// Time complexity: O(P) where P = path length
  List<String> _reconstructPath(
    String start,
    String end,
    Map<String, String> predecessors,
  ) {
    final path = <String>[];
    String? current = end;

    // Trace backward from destination to source
    while (current != null && current != start) {
      path.add(current);
      current = predecessors[current];
    }

    // Add the start node
    if (current == start) {
      path.add(start);
    }

    // Reverse to get source → destination order
    return path.reversed.toList();
  }

  /// Build a full [NavPath] from an ordered list of node IDs.
  ///
  /// Resolves each node ID to its [NavNode] object and finds the
  /// connecting edge between consecutive nodes.
  NavPath? _buildNavPath(List<String> pathIds) {
    if (pathIds.isEmpty) return null;

    final nodes = <NavNode>[];
    final edges = <NavEdge>[];
    double totalDistance = 0;

    for (int i = 0; i < pathIds.length; i++) {
      final node = graph.getNode(pathIds[i]);
      if (node == null) return null; // Shouldn't happen, but safety first
      nodes.add(node);

      // Find the edge connecting this node to the next
      if (i < pathIds.length - 1) {
        final fromId = pathIds[i];
        final toId = pathIds[i + 1];
        final neighborEdges = graph.getNeighbors(fromId, wheelchairMode: wheelchairMode);
        final edge = neighborEdges.where((e) => e.to == toId).firstOrNull;

        if (edge != null) {
          edges.add(edge);
          totalDistance += edge.weight;
        }
      }
    }

    return NavPath(
      nodes: nodes,
      edges: edges,
      totalDistance: totalDistance,
    );
  }
}
