/// Dijkstra's shortest path algorithm for indoor navigation.
///
/// This is the baseline pathfinding algorithm, guaranteed to find the
/// shortest path. Best used for same-floor navigation where the graph
/// is small (≤100 nodes). For larger search spaces (cross-floor,
/// cross-building), prefer A* which uses a heuristic to prune the search.
///
/// Time complexity: O((V + E) log V) with binary heap priority queue.
/// Space complexity: O(V) for distance and predecessor maps.

import 'dart:collection';
import 'models.dart';
import 'graph.dart';

/// Priority queue entry for Dijkstra's algorithm.
class _DijkstraEntry implements Comparable<_DijkstraEntry> {
  final String nodeId;
  final double distance;

  const _DijkstraEntry(this.nodeId, this.distance);

  @override
  int compareTo(_DijkstraEntry other) => distance.compareTo(other.distance);
}

/// Dijkstra's shortest path algorithm implementation.
///
/// Features:
/// - Standard single-source shortest path
/// - Early termination when destination is reached
/// - Wheelchair accessibility mode
/// - Returns full path with edges, distances, and nodes
///
/// Usage:
/// ```dart
/// final dijkstra = DijkstraPathfinder(graph);
/// final path = dijkstra.findPath('CS-CORR-1F-01', 'CS-101');
/// if (path != null) {
///   print('Distance: ${path.totalDistance}m');
///   print('ETA: ${path.estimatedTimeSeconds}s');
/// }
/// ```
class DijkstraPathfinder {
  final NavigationGraph graph;

  /// Whether to filter out stairs (wheelchair accessibility mode).
  final bool wheelchairMode;

  const DijkstraPathfinder(
    this.graph, {
    this.wheelchairMode = false,
  });

  /// Find the shortest path from [startId] to [endId].
  ///
  /// Returns null if no path exists.
  ///
  /// Algorithm:
  /// 1. Initialize distances: source = 0, all others = ∞
  /// 2. Push source into priority queue
  /// 3. While queue is not empty:
  ///    a. Pop node with minimum distance
  ///    b. If it's the destination → reconstruct path
  ///    c. For each neighbor:
  ///       - Calculate new distance through current node
  ///       - If shorter than known distance → update and push
  /// 4. If destination never reached → return null
  NavPath? findPath(String startId, String endId) {
    // Validate inputs
    if (graph.getNode(startId) == null || graph.getNode(endId) == null) {
      return null;
    }
    if (startId == endId) {
      final node = graph.getNode(startId)!;
      return NavPath(nodes: [node], edges: [], totalDistance: 0);
    }

    // Distance from source to each node (initialized to infinity).
    final distances = <String, double>{};

    // Predecessor map for path reconstruction.
    // Maps nodeId → (predecessor nodeId, edge used to get here).
    final predecessors = <String, (String, NavEdge)>{};

    // Visited set to avoid reprocessing.
    final visited = <String>{};

    // Priority queue (min-heap).
    final pq = SplayTreeSet<_DijkstraEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId); // Tie-breaking by ID
      },
    );

    // Initialize
    distances[startId] = 0;
    pq.add(_DijkstraEntry(startId, 0));

    while (pq.isNotEmpty) {
      // Pop the node with minimum distance
      final current = pq.first;
      pq.remove(current);

      final currentId = current.nodeId;

      // Skip if already visited (stale entry)
      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      // Early termination: destination reached
      if (currentId == endId) {
        return _reconstructPath(startId, endId, predecessors);
      }

      // Process all neighbors
      final edges =
          graph.getNeighborEdges(currentId, wheelchairMode: wheelchairMode);

      for (final edge in edges) {
        final neighborId = edge.to;
        if (visited.contains(neighborId)) continue;

        final newDist =
            distances[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);

        final currentBest = distances[neighborId] ?? double.infinity;

        if (newDist < currentBest) {
          // Remove old entry if exists (update priority)
          if (distances.containsKey(neighborId)) {
            pq.remove(_DijkstraEntry(neighborId, currentBest));
          }

          distances[neighborId] = newDist;
          predecessors[neighborId] = (currentId, edge);
          pq.add(_DijkstraEntry(neighborId, newDist));
        }
      }
    }

    // No path found
    return null;
  }

  /// Find shortest paths from [startId] to ALL reachable nodes.
  ///
  /// Useful for:
  /// - Finding nearest washroom/stairs/lift
  /// - Generating a distance matrix
  /// - Pre-computing distances for A* heuristic refinement
  Map<String, double> findAllDistances(String startId) {
    final distances = <String, double>{startId: 0};
    final visited = <String>{};
    final pq = SplayTreeSet<_DijkstraEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    pq.add(_DijkstraEntry(startId, 0));

    while (pq.isNotEmpty) {
      final current = pq.first;
      pq.remove(current);
      final currentId = current.nodeId;

      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      for (final edge
          in graph.getNeighborEdges(currentId, wheelchairMode: wheelchairMode)) {
        final neighborId = edge.to;
        if (visited.contains(neighborId)) continue;

        final newDist =
            distances[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);
        final currentBest = distances[neighborId] ?? double.infinity;

        if (newDist < currentBest) {
          if (distances.containsKey(neighborId)) {
            pq.remove(_DijkstraEntry(neighborId, currentBest));
          }
          distances[neighborId] = newDist;
          pq.add(_DijkstraEntry(neighborId, newDist));
        }
      }
    }

    return distances;
  }

  /// Find the nearest node of a specific type from [startId].
  ///
  /// Example: Find nearest washroom from current position.
  /// ```dart
  /// final nearest = dijkstra.findNearestOfType('CS-CORR-1F-01', NodeType.washroom);
  /// ```
  NavPath? findNearestOfType(String startId, NodeType targetType) {
    final distances = <String, double>{startId: 0};
    final predecessors = <String, (String, NavEdge)>{};
    final visited = <String>{};
    final pq = SplayTreeSet<_DijkstraEntry>(
      (a, b) {
        final cmp = a.distance.compareTo(b.distance);
        if (cmp != 0) return cmp;
        return a.nodeId.compareTo(b.nodeId);
      },
    );

    pq.add(_DijkstraEntry(startId, 0));

    while (pq.isNotEmpty) {
      final current = pq.first;
      pq.remove(current);
      final currentId = current.nodeId;

      if (visited.contains(currentId)) continue;
      visited.add(currentId);

      // Check if this node matches the target type
      final node = graph.getNode(currentId);
      if (node != null && node.type == targetType && currentId != startId) {
        return _reconstructPath(startId, currentId, predecessors);
      }

      for (final edge
          in graph.getNeighborEdges(currentId, wheelchairMode: wheelchairMode)) {
        final neighborId = edge.to;
        if (visited.contains(neighborId)) continue;

        final newDist =
            distances[currentId]! +
            edge.effectiveWeight(wheelchairMode: wheelchairMode);
        final currentBest = distances[neighborId] ?? double.infinity;

        if (newDist < currentBest) {
          if (distances.containsKey(neighborId)) {
            pq.remove(_DijkstraEntry(neighborId, currentBest));
          }
          distances[neighborId] = newDist;
          predecessors[neighborId] = (currentId, edge);
          pq.add(_DijkstraEntry(neighborId, newDist));
        }
      }
    }

    return null; // No node of target type found
  }

  /// Reconstruct the path from predecessors map.
  NavPath _reconstructPath(
    String startId,
    String endId,
    Map<String, (String, NavEdge)> predecessors,
  ) {
    final nodeIds = <String>[];
    final edges = <NavEdge>[];
    double totalDistance = 0;

    // Trace back from destination to source
    String current = endId;
    while (current != startId) {
      nodeIds.add(current);
      final (predId, edge) = predecessors[current]!;
      edges.add(edge);
      totalDistance += edge.weight;
      current = predId;
    }
    nodeIds.add(startId);

    // Reverse to get source → destination order
    nodeIds.reversed;
    edges.reversed;

    final nodes = nodeIds.reversed.map((id) => graph.getNode(id)!).toList();
    final orderedEdges = edges.reversed.toList();

    return NavPath(
      nodes: nodes,
      edges: orderedEdges,
      totalDistance: totalDistance,
    );
  }
}
