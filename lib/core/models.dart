import 'dart:math';

// ─────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────

enum NodeType {
  room,
  lab,
  office,
  corridor,
  junction,
  stairs,
  lift,
  washroom,
  entrance,
}

enum EdgeType {
  corridor,
  stairs,
  lift,
  door,
  outdoor,
}

enum EdgeStatus {
  active,
  blocked,
  maintenance,
}

// ─────────────────────────────────────────────────────────────
// POSITION 3D
// ─────────────────────────────────────────────────────────────

class Position3D {
  final double x;
  final double y;
  final double z;

  const Position3D({required this.x, required this.y, required this.z});

  double distanceTo(Position3D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  double distanceTo2D(Position3D other) {
    final dx = x - other.x;
    final dz = z - other.z;
    return sqrt(dx * dx + dz * dz);
  }

  Position3D operator +(Position3D other) =>
      Position3D(x: x + other.x, y: y + other.y, z: z + other.z);

  Position3D operator -(Position3D other) =>
      Position3D(x: x - other.x, y: y - other.y, z: z - other.z);

  @override
  String toString() => 'Position3D($x, $y, $z)';
}

// ─────────────────────────────────────────────────────────────
// NAV NODE
// ─────────────────────────────────────────────────────────────

class NavNode {
  final String id;
  final Position3D position;
  final int floor;
  final String building;
  final NodeType type;
  final String displayName;
  final Map<String, dynamic> metadata;

  const NavNode({
    required this.id,
    required this.position,
    required this.floor,
    required this.building,
    required this.type,
    String? displayName,
    this.metadata = const {},
  }) : displayName = displayName ?? id;

  bool get isDestination =>
      type == NodeType.room ||
      type == NodeType.lab ||
      type == NodeType.office ||
      type == NodeType.washroom ||
      type == NodeType.entrance;

  String get typeLabel {
    switch (type) {
      case NodeType.room:
        return 'Room';
      case NodeType.lab:
        return 'Lab';
      case NodeType.office:
        return 'Office';
      case NodeType.corridor:
        return 'Corridor';
      case NodeType.junction:
        return 'Junction';
      case NodeType.stairs:
        return 'Stairs';
      case NodeType.lift:
        return 'Lift';
      case NodeType.washroom:
        return 'Washroom';
      case NodeType.entrance:
        return 'Entrance';
    }
  }

  @override
  String toString() => 'NavNode($id, $type, floor=$floor)';
}

// ─────────────────────────────────────────────────────────────
// NAV EDGE
// ─────────────────────────────────────────────────────────────

class NavEdge {
  final String id;
  final String fromNode;
  final String toNode;
  final double weight;
  final EdgeType type;
  final bool bidirectional;
  EdgeStatus status;

  NavEdge({
    String? id,
    required this.fromNode,
    required this.toNode,
    required this.weight,
    this.type = EdgeType.corridor,
    this.bidirectional = true,
    this.status = EdgeStatus.active,
  }) : id = id ?? '${fromNode}_to_$toNode';

  bool get isActive => status == EdgeStatus.active;
  bool get isBlocked => status != EdgeStatus.active;

  @override
  String toString() => 'NavEdge($fromNode → $toNode, ${weight.toStringAsFixed(1)}m)';
}

// ─────────────────────────────────────────────────────────────
// NAV PATH
// ─────────────────────────────────────────────────────────────

class NavPath {
  final List<NavNode> nodes;
  final List<NavEdge> edges;
  final double totalDistance;

  NavPath({
    required this.nodes,
    required this.edges,
    double? totalDistance,
  }) : totalDistance = totalDistance ??
            edges.fold(0.0, (sum, e) => sum + e.weight);

  NavNode get source => nodes.first;
  NavNode get destination => nodes.last;

  double get estimatedTimeSeconds => totalDistance / 1.2;

  String get formattedDistance {
    if (totalDistance < 1000) {
      return '${totalDistance.toStringAsFixed(0)}m';
    }
    return '${(totalDistance / 1000).toStringAsFixed(1)}km';
  }

  String get formattedETA {
    final seconds = estimatedTimeSeconds;
    if (seconds < 60) return '${seconds.toStringAsFixed(0)}s';
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(0)} min';
  }

  Set<int> get floorsTraversed =>
      nodes.map((n) => n.floor).toSet();

  bool get isCrossFloor => floorsTraversed.length > 1;

  double remainingDistance(int fromSegment) {
    if (fromSegment >= edges.length) return 0;
    return edges
        .skip(fromSegment)
        .fold(0.0, (sum, e) => sum + e.weight);
  }

  bool containsEdge(String edgeId) =>
      edges.any((e) => e.id == edgeId);

  PathProjection nearestPoint(Position3D position) {
    double minDist = double.infinity;
    int bestSegment = 0;

    for (int i = 0; i < nodes.length; i++) {
      final d = position.distanceTo2D(nodes[i].position);
      if (d < minDist) {
        minDist = d;
        bestSegment = i.clamp(0, edges.length - 1);
      }
    }

    return PathProjection(
      segmentIndex: bestSegment,
      distance: minDist,
    );
  }

  @override
  String toString() =>
      'NavPath(${nodes.length} nodes, ${totalDistance.toStringAsFixed(1)}m, '
      'floors=${floorsTraversed})';
}

class PathProjection {
  final int segmentIndex;
  final double distance;

  const PathProjection({
    required this.segmentIndex,
    required this.distance,
  });
}
