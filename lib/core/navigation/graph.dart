/// Multi-layer navigation graph for indoor spaces.
///
/// The graph is structured as a set of layers (one per floor) with
/// inter-layer connections (stairs, lifts). This allows efficient
/// same-floor queries while supporting cross-floor navigation.

import 'models.dart';

/// A multi-layer weighted graph representing the navigable spaces
/// within one or more buildings.
///
/// Design decisions:
/// - Adjacency list representation (sparse graphs in buildings)
/// - O(1) node lookup by ID
/// - O(1) neighbor lookup
/// - Support for dynamic edge enable/disable without rebuilding
class NavigationGraph {
  /// All nodes indexed by their ID.
  final Map<String, NavNode> _nodes = {};

  /// Adjacency list: nodeId → list of outgoing edges.
  final Map<String, List<NavEdge>> _adjacencyList = {};

  /// Reverse adjacency: nodeId → list of incoming edges.
  /// Used for bidirectional edge management.
  final Map<String, List<NavEdge>> _reverseAdjacencyList = {};

  /// Nodes grouped by floor for layer-based queries.
  final Map<int, Set<String>> _floorLayers = {};

  /// Nodes grouped by building.
  final Map<String, Set<String>> _buildingGroups = {};

  /// Disabled edge IDs (for dynamic rerouting).
  final Set<String> _disabledEdges = {};

  // ─────────────────────────────────────────
  // Accessors
  // ─────────────────────────────────────────

  /// All nodes in the graph.
  Iterable<NavNode> get nodes => _nodes.values;

  /// All edges in the graph (including disabled).
  Iterable<NavEdge> get allEdges =>
      _adjacencyList.values.expand((edges) => edges);

  /// All active (traversable) edges.
  Iterable<NavEdge> get activeEdges =>
      allEdges.where((e) => e.isActive && !_disabledEdges.contains(e.id));

  /// Number of nodes.
  int get nodeCount => _nodes.length;

  /// Number of edges (counting bidirectional edges once).
  int get edgeCount => allEdges.length;

  /// Available floors.
  List<int> get floors => _floorLayers.keys.toList()..sort();

  /// Available buildings.
  List<String> get buildings => _buildingGroups.keys.toList();

  // ─────────────────────────────────────────
  // Construction
  // ─────────────────────────────────────────

  /// Create an empty graph.
  NavigationGraph();

  /// Create a graph from lists of nodes and edges.
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

  /// Create a graph from JSON data (as fetched from Firebase).
  factory NavigationGraph.fromJson(Map<String, dynamic> json) {
    final nodes = (json['nodes'] as List)
        .map((n) => NavNode.fromJson(n as Map<String, dynamic>))
        .toList();
    final edges = (json['edges'] as List)
        .map((e) => NavEdge.fromJson(e as Map<String, dynamic>))
        .toList();
    return NavigationGraph.fromData(nodes: nodes, edges: edges);
  }

  // ─────────────────────────────────────────
  // Mutation
  // ─────────────────────────────────────────

  /// Add a node to the graph.
  void addNode(NavNode node) {
    _nodes[node.id] = node;
    _adjacencyList.putIfAbsent(node.id, () => []);
    _reverseAdjacencyList.putIfAbsent(node.id, () => []);

    // Index by floor
    _floorLayers.putIfAbsent(node.floor, () => {}).add(node.id);

    // Index by building
    _buildingGroups.putIfAbsent(node.building, () => {}).add(node.id);
  }

  /// Add an edge to the graph.
  ///
  /// If the edge is bidirectional, a reverse edge is automatically created.
  void addEdge(NavEdge edge) {
    // Forward direction
    _adjacencyList.putIfAbsent(edge.from, () => []).add(edge);
    _reverseAdjacencyList.putIfAbsent(edge.to, () => []).add(edge);

    // Reverse direction (if bidirectional)
    if (edge.bidirectional) {
      final reverseEdge = NavEdge(
        from: edge.to,
        to: edge.from,
        weight: edge.weight,
        type: edge.type,
        bidirectional: false, // Prevent infinite recursion
        status: edge.status,
        metadata: edge.metadata,
      );
      _adjacencyList.putIfAbsent(edge.to, () => []).add(reverseEdge);
      _reverseAdjacencyList
          .putIfAbsent(edge.from, () => [])
          .add(reverseEdge);
    }
  }

  /// Disable an edge (mark as impassable without removing).
  ///
  /// Used for dynamic rerouting when paths are blocked.
  void disableEdge(String edgeId) {
    _disabledEdges.add(edgeId);
  }

  /// Re-enable a previously disabled edge.
  void enableEdge(String edgeId) {
    _disabledEdges.remove(edgeId);
  }

  /// Update the status of an edge.
  void updateEdgeStatus(String fromId, String toId, EdgeStatus status) {
    final edges = _adjacencyList[fromId];
    if (edges != null) {
      for (final edge in edges) {
        if (edge.to == toId) {
          edge.status = status;
        }
      }
    }
  }

  // ─────────────────────────────────────────
  // Queries
  // ─────────────────────────────────────────

  /// Get a node by its ID.
  NavNode? getNode(String id) => _nodes[id];

  /// Get all active outgoing edges from a node.
  ///
  /// Filters out disabled edges and edges with non-active status.
  /// Optionally applies accessibility filtering.
  List<NavEdge> getNeighborEdges(
    String nodeId, {
    bool wheelchairMode = false,
  }) {
    final edges = _adjacencyList[nodeId] ?? [];
    return edges.where((edge) {
      if (!edge.isActive || _disabledEdges.contains(edge.id)) return false;
      if (wheelchairMode && !edge.wheelchairAccessible) return false;
      return true;
    }).toList();
  }

  /// Get neighbor node IDs for a given node.
  List<String> getNeighborIds(String nodeId, {bool wheelchairMode = false}) {
    return getNeighborEdges(nodeId, wheelchairMode: wheelchairMode)
        .map((e) => e.to)
        .toList();
  }

  /// Get all nodes on a specific floor.
  List<NavNode> getNodesOnFloor(int floor) {
    final nodeIds = _floorLayers[floor] ?? {};
    return nodeIds.map((id) => _nodes[id]!).toList();
  }

  /// Get all nodes in a specific building.
  List<NavNode> getNodesInBuilding(String building) {
    final nodeIds = _buildingGroups[building] ?? {};
    return nodeIds.map((id) => _nodes[id]!).toList();
  }

  /// Find the nearest graph node to a given position.
  ///
  /// Optionally constrain to a specific floor or building.
  NavNode? findNearestNode(
    Position3D position, {
    int? floor,
    String? building,
  }) {
    Iterable<NavNode> candidates = _nodes.values;

    if (floor != null) {
      candidates = candidates.where((n) => n.floor == floor);
    }
    if (building != null) {
      candidates = candidates.where((n) => n.building == building);
    }

    NavNode? nearest;
    double minDist = double.infinity;

    for (final node in candidates) {
      final dist =
          floor != null
              ? position.distanceTo2D(node.position)
              : position.distanceTo(node.position);
      if (dist < minDist) {
        minDist = dist;
        nearest = node;
      }
    }

    return nearest;
  }

  /// Search nodes by name or ID (case-insensitive, partial match).
  List<NavNode> searchNodes(String query) {
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

  /// Check if two nodes are on different floors (requires floor transition).
  bool requiresFloorTransition(String nodeA, String nodeB) {
    final a = _nodes[nodeA];
    final b = _nodes[nodeB];
    if (a == null || b == null) return false;
    return a.floor != b.floor;
  }

  // ─────────────────────────────────────────
  // Subgraph Extraction
  // ─────────────────────────────────────────

  /// Extract a subgraph for a specific floor.
  ///
  /// Includes inter-floor edges (stairs, lifts) that connect to this floor.
  NavigationGraph subgraphForFloor(int floor) {
    final subgraph = NavigationGraph();
    final floorNodeIds = _floorLayers[floor] ?? {};

    for (final nodeId in floorNodeIds) {
      subgraph.addNode(_nodes[nodeId]!);
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
  NavigationGraph subgraphForBuilding(String building) {
    final subgraph = NavigationGraph();
    final buildingNodeIds = _buildingGroups[building] ?? {};

    for (final nodeId in buildingNodeIds) {
      subgraph.addNode(_nodes[nodeId]!);
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

  // ─────────────────────────────────────────
  // Diagnostics
  // ─────────────────────────────────────────

  /// Validate graph connectivity.
  ///
  /// Returns a list of unreachable nodes (if any).
  List<String> findUnreachableNodes() {
    if (_nodes.isEmpty) return [];

    final visited = <String>{};
    final queue = <String>[_nodes.keys.first];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);

      for (final edge in getNeighborEdges(current)) {
        if (!visited.contains(edge.to)) {
          queue.add(edge.to);
        }
      }
    }

    return _nodes.keys.where((id) => !visited.contains(id)).toList();
  }

  @override
  String toString() =>
      'NavigationGraph($nodeCount nodes, $edgeCount edges, '
      'floors=$floors, buildings=$buildings)';
}
