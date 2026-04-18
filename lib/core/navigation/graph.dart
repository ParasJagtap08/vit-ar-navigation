/// Multi-layer navigation graph engine for indoor spaces.
///
/// Represents buildings as a weighted directed graph with:
/// - O(1) node lookup by ID
/// - O(1) neighbor lookup via adjacency list
/// - O(1) edge disable/enable for dynamic rerouting
/// - Floor-based and building-based node indexing for scalable queries
///
/// This graph is the single source of truth for all pathfinding algorithms
/// (Dijkstra, A*) and the dynamic rerouting engine.

import 'models.dart';

/// A scalable, multi-layer weighted graph for campus navigation.
///
/// ```dart
/// final graph = NavigationGraph();
/// graph.addNode(NavNode(id: 'CS-101', x: 5, y: 0, z: 20, floor: 1, building: 'cs', type: NodeType.room));
/// graph.addNode(NavNode(id: 'CS-CORR-1', x: 5, y: 0, z: 15, floor: 1, building: 'cs', type: NodeType.corridor));
/// graph.addEdge(NavEdge(from: 'CS-CORR-1', to: 'CS-101', weight: 5.0, type: EdgeType.walk));
/// // ^ automatically creates reverse edge (bidirectional)
///
/// final neighbors = graph.getNeighbors('CS-CORR-1');
/// // → [NavEdge(CS-CORR-1 → CS-101, 5.0m)]
/// ```
class NavigationGraph {
  // ─────────────────────────────────────────────────────────────────────────
  // Core Data Structures
  // ─────────────────────────────────────────────────────────────────────────

  /// All nodes indexed by their unique ID.
  /// Guarantees O(1) lookup for any node.
  final Map<String, NavNode> _nodes = {};

  /// Adjacency list: nodeId → list of outgoing edges.
  /// This is the primary structure for pathfinding traversal.
  final Map<String, List<NavEdge>> _adjacencyList = {};

  /// Reverse adjacency: nodeId → list of incoming edges.
  /// Used for efficient edge removal and bidirectional management.
  final Map<String, List<NavEdge>> _reverseAdjacencyList = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Scalability Indexes
  // ─────────────────────────────────────────────────────────────────────────

  /// Nodes grouped by floor number.
  /// Enables O(1) floor-based queries instead of scanning all nodes.
  final Map<int, Set<String>> _floorLayers = {};

  /// Nodes grouped by building ID.
  /// Enables O(1) building-based queries for multi-building campuses.
  final Map<String, Set<String>> _buildingGroups = {};

  /// Set of disabled edge IDs (for dynamic rerouting).
  /// Using a Set gives O(1) containment checks during pathfinding.
  final Set<String> _disabledEdges = {};

  // ─────────────────────────────────────────────────────────────────────────
  // Public Accessors
  // ─────────────────────────────────────────────────────────────────────────

  /// Read-only access to all nodes.
  Iterable<NavNode> get nodes => _nodes.values;

  /// Read-only access to all edges (including disabled ones).
  Iterable<NavEdge> get allEdges =>
      _adjacencyList.values.expand((edges) => edges);

  /// All currently traversable edges.
  Iterable<NavEdge> get activeEdges =>
      allEdges.where((e) => e.isActive && !_disabledEdges.contains(e.id));

  /// Total number of nodes in the graph.
  int get nodeCount => _nodes.length;

  /// Total number of edges (forward direction only).
  int get edgeCount => allEdges.length;

  /// Sorted list of all floor numbers present in the graph.
  List<int> get floors => _floorLayers.keys.toList()..sort();

  /// List of all building IDs present in the graph.
  List<String> get buildings => _buildingGroups.keys.toList();

  // ─────────────────────────────────────────────────────────────────────────
  // Construction
  // ─────────────────────────────────────────────────────────────────────────

  /// Create an empty graph.
  NavigationGraph();

  /// Create a graph from pre-built lists of nodes and edges.
  ///
  /// This is the primary factory used when loading data from
  /// Firebase or local cache.
  factory NavigationGraph.fromData({
    required List<NavNode> nodes,
    required List<NavEdge> edges,
  }) {
    final graph = NavigationGraph();
    for (final node in nodes) {
      graph.addNode(node);
    }
    for (final edge in edges) {
      graph.addEdge(edge);
    }
    return graph;
  }

  /// Create a graph from a JSON map (as deserialized from Hive cache).
  factory NavigationGraph.fromJson(Map<String, dynamic> json) {
    final nodes = (json['nodes'] as List)
        .map((n) => NavNode.fromJson(n as Map<String, dynamic>))
        .toList();
    final edges = (json['edges'] as List)
        .map((e) => NavEdge.fromJson(e as Map<String, dynamic>))
        .toList();
    return NavigationGraph.fromData(nodes: nodes, edges: edges);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Node Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Add a node to the graph.
  ///
  /// - Duplicate IDs are silently ignored (no-op if node already exists).
  /// - Automatically indexes the node by floor and building for
  ///   scalable queries on large campus graphs.
  ///
  /// Time complexity: O(1)
  void addNode(NavNode node) {
    // Prevent duplicate nodes
    if (_nodes.containsKey(node.id)) return;

    _nodes[node.id] = node;
    _adjacencyList.putIfAbsent(node.id, () => []);
    _reverseAdjacencyList.putIfAbsent(node.id, () => []);

    // Index by floor (for floor-based subgraph queries)
    _floorLayers.putIfAbsent(node.floor, () => {}).add(node.id);

    // Index by building (for building-scoped pathfinding)
    _buildingGroups.putIfAbsent(node.building, () => {}).add(node.id);
  }

  /// Get a node by its ID. Returns null if not found.
  ///
  /// Time complexity: O(1)
  NavNode? getNode(String id) => _nodes[id];

  /// Check whether a node with [id] exists in the graph.
  ///
  /// Time complexity: O(1)
  bool hasNode(String id) => _nodes.containsKey(id);

  // ─────────────────────────────────────────────────────────────────────────
  // Edge Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Add an edge to the graph.
  ///
  /// If the edge is bidirectional (default), a reverse edge is
  /// automatically created so pathfinding works in both directions.
  ///
  /// Safe: silently ignores edges referencing non-existent nodes.
  ///
  /// Time complexity: O(1)
  void addEdge(NavEdge edge) {
    // Safety: skip if either endpoint doesn't exist
    if (!_nodes.containsKey(edge.from) && !_nodes.containsKey(edge.to)) return;

    // Forward direction: from → to
    _adjacencyList.putIfAbsent(edge.from, () => []).add(edge);
    _reverseAdjacencyList.putIfAbsent(edge.to, () => []).add(edge);

    // Reverse direction: to → from (if bidirectional)
    if (edge.bidirectional) {
      final reverseEdge = NavEdge(
        from: edge.to,
        to: edge.from,
        weight: edge.weight,
        type: edge.type,
        bidirectional: false, // Prevent infinite recursion
        wheelchairAccessible: edge.wheelchairAccessible,
        status: edge.status,
        metadata: edge.metadata,
      );
      _adjacencyList.putIfAbsent(edge.to, () => []).add(reverseEdge);
      _reverseAdjacencyList.putIfAbsent(edge.from, () => []).add(reverseEdge);
    }
  }

  /// Remove an edge between [fromId] and [toId].
  ///
  /// Removes both forward and reverse edges for bidirectional connections.
  /// Safe: no-op if the edge doesn't exist.
  ///
  /// Time complexity: O(E_node) where E_node = edges from that node
  void removeEdge(String fromId, String toId) {
    // Remove forward edge: from → to
    _adjacencyList[fromId]?.removeWhere((e) => e.to == toId);
    _reverseAdjacencyList[toId]?.removeWhere((e) => e.from == fromId);

    // Remove reverse edge: to → from
    _adjacencyList[toId]?.removeWhere((e) => e.to == fromId);
    _reverseAdjacencyList[fromId]?.removeWhere((e) => e.from == toId);

    // Clean up disabled set
    _disabledEdges.remove('${fromId}_to_$toId');
    _disabledEdges.remove('${toId}_to_$fromId');
  }

  /// Disable an edge by its ID (mark as impassable without removing).
  ///
  /// This is the preferred method for dynamic rerouting — the edge
  /// stays in the graph but pathfinders will skip it. Call [enableEdge]
  /// to restore it later.
  ///
  /// Time complexity: O(1)
  void disableEdge(String edgeId) {
    _disabledEdges.add(edgeId);
  }

  /// Re-enable a previously disabled edge.
  ///
  /// Time complexity: O(1)
  void enableEdge(String edgeId) {
    _disabledEdges.remove(edgeId);
  }

  /// Update the real-time status of an edge (active / blocked / maintenance).
  ///
  /// Updates the edge's [status] and [isBlocked] fields. This affects
  /// pathfinding immediately — blocked edges are skipped by [getNeighbors].
  ///
  /// Time complexity: O(E_node)
  void updateEdgeStatus(String fromId, String toId, EdgeStatus status) {
    final blocked = status != EdgeStatus.active;

    // Update forward edge
    final forwardEdges = _adjacencyList[fromId];
    if (forwardEdges != null) {
      for (final edge in forwardEdges) {
        if (edge.to == toId) {
          edge.status = status;
          edge.isBlocked = blocked;
        }
      }
    }

    // Update reverse edge (for bidirectional)
    final reverseEdges = _adjacencyList[toId];
    if (reverseEdges != null) {
      for (final edge in reverseEdges) {
        if (edge.to == fromId) {
          edge.status = status;
          edge.isBlocked = blocked;
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Neighbor Queries (used by Dijkstra / A*)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all active outgoing edges from a node.
  ///
  /// This is the primary method called by pathfinding algorithms.
  /// It returns only traversable edges — filtering out:
  /// - Edges with `isBlocked == true`
  /// - Edges with non-active status
  /// - Edges in the `_disabledEdges` set
  /// - Stairs edges when [wheelchairMode] is true
  ///
  /// Returns an empty list if [nodeId] doesn't exist (safe null handling).
  ///
  /// Time complexity: O(E_node)
  List<NavEdge> getNeighbors(
    String nodeId, {
    bool wheelchairMode = false,
  }) {
    final edges = _adjacencyList[nodeId];
    if (edges == null) return [];

    return edges.where((edge) {
      // Skip blocked or disabled edges
      if (!edge.isActive) return false;
      if (_disabledEdges.contains(edge.id)) return false;

      // Skip non-wheelchair-accessible edges in wheelchair mode
      if (wheelchairMode && !edge.wheelchairAccessible) return false;

      return true;
    }).toList();
  }

  /// Convenience: same as [getNeighbors] (backward-compatible alias).
  List<NavEdge> getNeighborEdges(
    String nodeId, {
    bool wheelchairMode = false,
  }) {
    return getNeighbors(nodeId, wheelchairMode: wheelchairMode);
  }

  /// Get neighbor node IDs (just the IDs, not the full edges).
  ///
  /// Useful for quick connectivity checks without edge weight data.
  List<String> getNeighborIds(String nodeId, {bool wheelchairMode = false}) {
    return getNeighbors(nodeId, wheelchairMode: wheelchairMode)
        .map((e) => e.to)
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Floor & Building Queries (Scalability)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all nodes on a specific floor.
  ///
  /// Uses the floor index — O(F) where F = nodes on that floor,
  /// not O(N) scanning of all nodes.
  List<NavNode> getNodesOnFloor(int floor) {
    final nodeIds = _floorLayers[floor] ?? {};
    return nodeIds
        .map((id) => _nodes[id])
        .whereType<NavNode>()
        .toList();
  }

  /// Get all nodes in a specific building.
  ///
  /// Uses the building index — O(B) where B = nodes in that building.
  List<NavNode> getNodesInBuilding(String building) {
    final nodeIds = _buildingGroups[building] ?? {};
    return nodeIds
        .map((id) => _nodes[id])
        .whereType<NavNode>()
        .toList();
  }

  /// Check if two nodes are on different floors.
  ///
  /// Used by the orchestrator to decide between Dijkstra (same floor)
  /// and A* (cross-floor).
  bool requiresFloorTransition(String nodeA, String nodeB) {
    final a = _nodes[nodeA];
    final b = _nodes[nodeB];
    if (a == null || b == null) return false;
    return a.floor != b.floor;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spatial Queries
  // ─────────────────────────────────────────────────────────────────────────

  /// Find the nearest graph node to a given 3D position.
  ///
  /// Optionally constrain the search to a specific [floor] or [building].
  /// When [floor] is provided, uses 2D distance (ignoring vertical).
  ///
  /// Time complexity: O(C) where C = candidate nodes after filtering.
  NavNode? findNearestNode(
    Position3D position, {
    int? floor,
    String? building,
  }) {
    Iterable<NavNode> candidates = _nodes.values;

    if (floor != null) {
      final floorIds = _floorLayers[floor];
      if (floorIds == null) return null;
      candidates = floorIds.map((id) => _nodes[id]).whereType<NavNode>();
    }
    if (building != null) {
      candidates = candidates.where((n) => n.building == building);
    }

    NavNode? nearest;
    double minDist = double.infinity;

    for (final node in candidates) {
      final dist = floor != null
          ? position.distanceTo2D(node.position)
          : position.distanceTo(node.position);
      if (dist < minDist) {
        minDist = dist;
        nearest = node;
      }
    }

    return nearest;
  }

  /// Search nodes by name, ID, or department (case-insensitive partial match).
  ///
  /// Searches across: node ID, display name, and department metadata.
  ///
  /// Time complexity: O(N) — acceptable for campus-scale graphs (< 1000 nodes).
  List<NavNode> searchNodes(String query) {
    if (query.trim().isEmpty) return [];
    final lowerQuery = query.toLowerCase();

    return _nodes.values.where((node) {
      return node.id.toLowerCase().contains(lowerQuery) ||
          node.displayName.toLowerCase().contains(lowerQuery) ||
          (node.metadata['department'] as String?)
                  ?.toLowerCase()
                  .contains(lowerQuery) ==
              true;
    }).toList();
  }

  /// Get all navigable destination nodes (rooms, labs, offices, washrooms).
  ///
  /// Returns sorted by display name for UI presentation.
  List<NavNode> get destinations {
    const destinationTypes = {
      NodeType.room,
      NodeType.lab,
      NodeType.office,
      NodeType.washroom,
    };
    return _nodes.values
        .where((n) => destinationTypes.contains(n.type))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Subgraph Extraction (Scalability)
  // ─────────────────────────────────────────────────────────────────────────

  /// Extract a subgraph containing only nodes on [floor].
  ///
  /// Includes edges that connect nodes within this floor.
  /// Used for floor-isolated Dijkstra queries.
  NavigationGraph subgraphForFloor(int floor) {
    final subgraph = NavigationGraph();
    final floorNodeIds = _floorLayers[floor] ?? {};

    for (final nodeId in floorNodeIds) {
      final node = _nodes[nodeId];
      if (node != null) subgraph.addNode(node);
    }

    for (final nodeId in floorNodeIds) {
      for (final edge in _adjacencyList[nodeId] ?? []) {
        if (floorNodeIds.contains(edge.to)) {
          subgraph.addEdge(edge);
        }
      }
    }

    return subgraph;
  }

  /// Extract a subgraph for a specific building (all floors).
  ///
  /// Useful for building-scoped navigation (most common use case).
  NavigationGraph subgraphForBuilding(String building) {
    final subgraph = NavigationGraph();
    final buildingNodeIds = _buildingGroups[building] ?? {};

    for (final nodeId in buildingNodeIds) {
      final node = _nodes[nodeId];
      if (node != null) subgraph.addNode(node);
    }

    for (final nodeId in buildingNodeIds) {
      for (final edge in _adjacencyList[nodeId] ?? []) {
        if (buildingNodeIds.contains(edge.to)) {
          subgraph.addEdge(edge);
        }
      }
    }

    return subgraph;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Diagnostics & Validation
  // ─────────────────────────────────────────────────────────────────────────

  /// Validate graph connectivity using BFS from the first node.
  ///
  /// Returns a list of unreachable node IDs (empty = fully connected).
  /// Call this after loading a graph to detect data issues.
  ///
  /// Time complexity: O(V + E)
  List<String> findUnreachableNodes() {
    if (_nodes.isEmpty) return [];

    final visited = <String>{};
    final queue = <String>[_nodes.keys.first];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);

      for (final edge in getNeighbors(current)) {
        if (!visited.contains(edge.to)) {
          queue.add(edge.to);
        }
      }
    }

    return _nodes.keys.where((id) => !visited.contains(id)).toList();
  }

  /// Get a summary of the graph for debugging.
  Map<String, dynamic> get diagnostics => {
        'nodeCount': nodeCount,
        'edgeCount': edgeCount,
        'floors': floors,
        'buildings': buildings,
        'disabledEdges': _disabledEdges.length,
        'blockedEdges': allEdges.where((e) => e.isBlocked).length,
        'unreachableNodes': findUnreachableNodes(),
      };

  @override
  String toString() =>
      'NavigationGraph($nodeCount nodes, $edgeCount edges, '
      'floors=$floors, buildings=$buildings)';
}
