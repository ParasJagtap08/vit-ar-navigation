import 'dart:collection';
import 'dart:math';
import 'models.dart';

// ─────────────────────────────────────────────────────────────
// NAVIGATION GRAPH
// ─────────────────────────────────────────────────────────────

class NavigationGraph {
  /// Adjacency list: nodeId → {neighborId → edge}
  final Map<String, Map<String, NavEdge>> _adjacency = {};

  /// All nodes: nodeId → NavNode
  final Map<String, NavNode> _nodes = {};

  /// Floor index: floor → [NavNode]
  final Map<int, List<NavNode>> _nodesByFloor = {};

  /// Building index: building → [NavNode]
  final Map<String, List<NavNode>> _nodesByBuilding = {};

  int get nodeCount => _nodes.length;
  int get edgeCount => _adjacency.values.fold(0, (s, m) => s + m.length);

  Iterable<NavNode> get nodes => _nodes.values;
  Set<String> get buildings => _nodesByBuilding.keys.toSet();

  // ─── Build ──────────────────────────────────────────────

  void addNode(NavNode node) {
    _nodes[node.id] = node;
    _adjacency.putIfAbsent(node.id, () => {});
    _nodesByFloor.putIfAbsent(node.floor, () => []).add(node);
    _nodesByBuilding.putIfAbsent(node.building, () => []).add(node);
  }

  void addEdge(NavEdge edge) {
    _adjacency.putIfAbsent(edge.fromNode, () => {})[edge.toNode] = edge;
    if (edge.bidirectional) {
      final reverse = NavEdge(
        id: '${edge.toNode}_to_${edge.fromNode}',
        fromNode: edge.toNode,
        toNode: edge.fromNode,
        weight: edge.weight,
        type: edge.type,
        bidirectional: true,
        status: edge.status,
      );
      _adjacency.putIfAbsent(edge.toNode, () => {})[edge.fromNode] = reverse;
    }
  }

  // ─── Query ──────────────────────────────────────────────

  NavNode? getNode(String id) => _nodes[id];

  Map<String, NavEdge> getNeighbors(String nodeId) =>
      _adjacency[nodeId] ?? {};

  List<NavNode> getNodesByFloor(int floor) =>
      _nodesByFloor[floor] ?? [];

  List<NavNode> getNodesByBuilding(String building) =>
      _nodesByBuilding[building] ?? [];

  List<NavNode> getDestinations({String? building, int? floor}) {
    var result = _nodes.values.where((n) => n.isDestination);
    if (building != null) {
      result = result.where((n) => n.building == building);
    }
    if (floor != null) {
      result = result.where((n) => n.floor == floor);
    }
    return result.toList();
  }

  bool requiresFloorTransition(String fromId, String toId) {
    final from = getNode(fromId);
    final to = getNode(toId);
    if (from == null || to == null) return false;
    return from.floor != to.floor;
  }

  NavNode? findNearestNode(Position3D pos, {int? floor, String? building}) {
    double minDist = double.infinity;
    NavNode? nearest;

    for (final node in _nodes.values) {
      if (floor != null && node.floor != floor) continue;
      if (building != null && node.building != building) continue;
      final d = pos.distanceTo2D(node.position);
      if (d < minDist) {
        minDist = d;
        nearest = node;
      }
    }
    return nearest;
  }

  // ─── Edge Management ────────────────────────────────────

  void disableEdge(String edgeId) {
    for (final neighbors in _adjacency.values) {
      for (final edge in neighbors.values) {
        if (edge.id == edgeId) {
          edge.status = EdgeStatus.blocked;
        }
      }
    }
  }

  void enableEdge(String edgeId) {
    for (final neighbors in _adjacency.values) {
      for (final edge in neighbors.values) {
        if (edge.id == edgeId) {
          edge.status = EdgeStatus.active;
        }
      }
    }
  }

  List<NavEdge> get allEdges {
    final edges = <NavEdge>[];
    for (final neighbors in _adjacency.values) {
      edges.addAll(neighbors.values);
    }
    return edges;
  }

  // ─── Search ─────────────────────────────────────────────

  List<NavNode> searchNodes(String query) {
    if (query.trim().isEmpty) return [];
    final lq = query.toLowerCase();
    return _nodes.values.where((n) {
      return n.isDestination &&
          (n.id.toLowerCase().contains(lq) ||
              n.displayName.toLowerCase().contains(lq) ||
              n.typeLabel.toLowerCase().contains(lq) ||
              n.building.toLowerCase().contains(lq));
    }).toList()
      ..sort((a, b) {
        // Prioritize exact matches
        final aExact = a.id.toLowerCase().startsWith(lq) ||
            a.displayName.toLowerCase().startsWith(lq);
        final bExact = b.id.toLowerCase().startsWith(lq) ||
            b.displayName.toLowerCase().startsWith(lq);
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
        return a.displayName.compareTo(b.displayName);
      });
  }
}

// ─────────────────────────────────────────────────────────────
// DIJKSTRA PATHFINDER
// ─────────────────────────────────────────────────────────────

class DijkstraPathfinder {
  final NavigationGraph graph;
  final bool wheelchairMode;

  DijkstraPathfinder(this.graph, {this.wheelchairMode = false});

  NavPath? findPath(String fromId, String toId) {
    final dist = <String, double>{};
    final prev = <String, String>{};
    final prevEdge = <String, NavEdge>{};

    // SplayTreeMap used as a priority queue
    final pq = SplayTreeSet<_PQEntry>((a, b) {
      final cmp = a.distance.compareTo(b.distance);
      return cmp != 0 ? cmp : a.nodeId.compareTo(b.nodeId);
    });

    dist[fromId] = 0;
    pq.add(_PQEntry(fromId, 0));

    while (pq.isNotEmpty) {
      final current = pq.first;
      pq.remove(current);
      final u = current.nodeId;

      if (u == toId) break;

      final uDist = dist[u] ?? double.infinity;
      if (current.distance > uDist) continue;

      for (final entry in graph.getNeighbors(u).entries) {
        final v = entry.key;
        final edge = entry.value;

        if (edge.isBlocked) continue;
        if (wheelchairMode && edge.type == EdgeType.stairs) continue;

        final alt = uDist + edge.weight;
        if (alt < (dist[v] ?? double.infinity)) {
          dist[v] = alt;
          prev[v] = u;
          prevEdge[v] = edge;
          pq.add(_PQEntry(v, alt));
        }
      }
    }

    if (!prev.containsKey(toId) && fromId != toId) return null;

    // Reconstruct path
    final path = <String>[toId];
    var current = toId;
    while (prev.containsKey(current)) {
      current = prev[current]!;
      path.add(current);
    }
    path.reversed;

    final nodeList = path.reversed
        .map((id) => graph.getNode(id)!)
        .toList();
    final edgeList = <NavEdge>[];
    for (int i = 0; i < nodeList.length - 1; i++) {
      edgeList.add(prevEdge[nodeList[i + 1].id]!);
    }

    return NavPath(
      nodes: nodeList,
      edges: edgeList,
      totalDistance: dist[toId] ?? 0,
    );
  }

  NavPath? findNearestOfType(String fromId, NodeType type) {
    NavPath? best;
    double bestDist = double.infinity;

    for (final node in graph.nodes) {
      if (node.type != type) continue;
      if (node.id == fromId) continue;

      final path = findPath(fromId, node.id);
      if (path != null && path.totalDistance < bestDist) {
        bestDist = path.totalDistance;
        best = path;
      }
    }
    return best;
  }
}

// ─────────────────────────────────────────────────────────────
// A* PATHFINDER
// ─────────────────────────────────────────────────────────────

class AStarPathfinder {
  final NavigationGraph graph;
  final bool wheelchairMode;
  final double floorTransitionPenalty;

  AStarPathfinder(
    this.graph, {
    this.wheelchairMode = false,
    this.floorTransitionPenalty = 8.0,
  });

  AStarResult findPathWithStats(String fromId, String toId) {
    final target = graph.getNode(toId);
    if (target == null) {
      return AStarResult(path: null, nodesExplored: 0, nodesExpanded: 0);
    }

    final gScore = <String, double>{};
    final fScore = <String, double>{};
    final prev = <String, String>{};
    final prevEdge = <String, NavEdge>{};
    int explored = 0;
    int expanded = 0;

    final openSet = SplayTreeSet<_PQEntry>((a, b) {
      final cmp = a.distance.compareTo(b.distance);
      return cmp != 0 ? cmp : a.nodeId.compareTo(b.nodeId);
    });

    gScore[fromId] = 0;
    fScore[fromId] = _heuristic(graph.getNode(fromId)!, target);
    openSet.add(_PQEntry(fromId, fScore[fromId]!));

    while (openSet.isNotEmpty) {
      final current = openSet.first;
      openSet.remove(current);
      final u = current.nodeId;
      expanded++;

      if (u == toId) break;

      final uG = gScore[u] ?? double.infinity;

      for (final entry in graph.getNeighbors(u).entries) {
        final v = entry.key;
        final edge = entry.value;
        explored++;

        if (edge.isBlocked) continue;
        if (wheelchairMode && edge.type == EdgeType.stairs) continue;

        double edgeCost = edge.weight;
        if (edge.type == EdgeType.stairs || edge.type == EdgeType.lift) {
          edgeCost += floorTransitionPenalty;
        }

        final tentativeG = uG + edgeCost;
        if (tentativeG < (gScore[v] ?? double.infinity)) {
          gScore[v] = tentativeG;
          prev[v] = u;
          prevEdge[v] = edge;

          final vNode = graph.getNode(v);
          final h = vNode != null ? _heuristic(vNode, target) : 0.0;
          fScore[v] = tentativeG + h;
          openSet.add(_PQEntry(v, fScore[v]!));
        }
      }
    }

    if (!prev.containsKey(toId) && fromId != toId) {
      return AStarResult(path: null, nodesExplored: explored, nodesExpanded: expanded);
    }

    // Reconstruct
    final path = <String>[toId];
    var current = toId;
    while (prev.containsKey(current)) {
      current = prev[current]!;
      path.add(current);
    }

    final nodeList = path.reversed
        .map((id) => graph.getNode(id)!)
        .toList();
    final edgeList = <NavEdge>[];
    for (int i = 0; i < nodeList.length - 1; i++) {
      edgeList.add(prevEdge[nodeList[i + 1].id]!);
    }

    return AStarResult(
      path: NavPath(
        nodes: nodeList,
        edges: edgeList,
        totalDistance: gScore[toId] ?? 0,
      ),
      nodesExplored: explored,
      nodesExpanded: expanded,
    );
  }

  double _heuristic(NavNode a, NavNode b) {
    return a.position.distanceTo(b.position);
  }
}

class AStarResult {
  final NavPath? path;
  final int nodesExplored;
  final int nodesExpanded;

  AStarResult({
    required this.path,
    required this.nodesExplored,
    required this.nodesExpanded,
  });
}

// ─────────────────────────────────────────────────────────────
// PRIORITY QUEUE ENTRY
// ─────────────────────────────────────────────────────────────

class _PQEntry {
  final String nodeId;
  final double distance;
  _PQEntry(this.nodeId, this.distance);
}
