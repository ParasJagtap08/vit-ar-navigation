/// Core navigation data models for VIT Pune AR Indoor Navigation System.
///
/// Defines the fundamental graph entities:
/// - [NavNode]  — a physical location (room, corridor, stairs, lift)
/// - [NavEdge]  — a traversable connection between two nodes
/// - [NavPath]  — a computed route through the graph
/// - [Position3D] — a 3D coordinate in building-local space
///
/// All models include [fromJson] / [toJson] for Firestore serialization.

import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

/// Type classification for navigation graph nodes.
///
/// Each physical location in a building maps to exactly one [NodeType].
enum NodeType {
  /// Classroom or lecture hall.
  room,

  /// Hallway segment connecting other nodes.
  corridor,

  /// Staircase connecting floors (not wheelchair-accessible).
  stairs,

  /// Elevator connecting floors (wheelchair-accessible).
  lift,

  /// Computer or research laboratory.
  lab,

  /// Restroom facility.
  washroom,

  /// Faculty or administrative office.
  office,

  /// Building entrance/exit point.
  entrance,

  /// Intersection where multiple corridors meet.
  junction,
}

/// Type classification for navigation graph edges.
///
/// Determines traversal characteristics and accessibility filtering.
enum EdgeType {
  /// Standard walkable corridor or doorway.
  walk,

  /// Staircase traversal between floors.
  stairs,

  /// Elevator traversal between floors.
  lift,
}

/// Real-time operational status of an edge.
enum EdgeStatus {
  /// Edge is open and traversable.
  active,

  /// Edge is blocked (cleaning, obstruction, emergency).
  blocked,

  /// Edge is under maintenance (scheduled closure).
  maintenance,
}

// ─────────────────────────────────────────────────────────────────────────────
// POSITION 3D
// ─────────────────────────────────────────────────────────────────────────────

/// A point in the building's local Cartesian coordinate system.
///
/// Axes:
/// - **x** → East–West (meters)
/// - **y** → Vertical / Up (meters, typically `floor × 4.0`)
/// - **z** → North–South (meters)
///
/// Origin is placed at each building's south-west corner at ground level.
class Position3D {
  final double x;
  final double y;
  final double z;

  const Position3D({required this.x, required this.y, required this.z});

  /// 3D Euclidean distance to [other].
  double distanceTo(Position3D other) {
    return sqrt(
      pow(x - other.x, 2) + pow(y - other.y, 2) + pow(z - other.z, 2),
    );
  }

  /// 2D horizontal distance (ignores vertical component).
  double distanceTo2D(Position3D other) {
    return sqrt(pow(x - other.x, 2) + pow(z - other.z, 2));
  }

  Position3D operator +(Position3D other) =>
      Position3D(x: x + other.x, y: y + other.y, z: z + other.z);

  Position3D operator -(Position3D other) =>
      Position3D(x: x - other.x, y: y - other.y, z: z - other.z);

  /// Linear interpolation toward [other] by factor [t] ∈ [0, 1].
  Position3D lerp(Position3D other, double t) {
    return Position3D(
      x: x + (other.x - x) * t,
      y: y + (other.y - y) * t,
      z: z + (other.z - z) * t,
    );
  }

  // ── Serialization ──

  factory Position3D.fromJson(Map<String, dynamic> json) {
    return Position3D(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};

  // ── Object overrides ──

  @override
  String toString() => 'Position3D($x, $y, $z)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position3D && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV NODE
// ─────────────────────────────────────────────────────────────────────────────

/// A node in the navigation graph — represents one physical location.
///
/// Examples: Room CS-101, Corridor segment, Staircase landing, Elevator door.
///
/// ```dart
/// final node = NavNode(
///   id: 'CS-101',
///   x: 5.0, y: 0.0, z: 20.0,
///   floor: 1,
///   building: 'cs',
///   type: NodeType.room,
/// );
/// ```
class NavNode {
  /// Unique identifier (e.g. `"CS-101"`, `"CS-STAIRS-1F"`).
  final String id;

  /// East–West coordinate in meters.
  final double x;

  /// Vertical coordinate in meters.
  final double y;

  /// North–South coordinate in meters.
  final double z;

  /// Floor number (1-indexed: 1 = ground floor).
  final int floor;

  /// Building identifier (e.g. `"cs"`, `"aiml"`).
  final String building;

  /// Location type classification.
  final NodeType type;

  /// Optional key-value metadata (display name, capacity, department, etc.).
  final Map<String, dynamic> metadata;

  const NavNode({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    required this.floor,
    required this.building,
    required this.type,
    this.metadata = const {},
  });

  /// Convenience: 3D position as a [Position3D] object.
  Position3D get position => Position3D(x: x, y: y, z: z);

  /// Human-readable name (falls back to [id] if not set in metadata).
  String get displayName => metadata['display_name'] as String? ?? id;

  // ── Serialization ──

  factory NavNode.fromJson(Map<String, dynamic> json) {
    return NavNode(
      id: json['id'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      floor: json['floor'] as int,
      building: json['building'] as String,
      type: NodeType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NodeType.corridor,
      ),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'z': z,
        'floor': floor,
        'building': building,
        'type': type.name,
        'metadata': metadata,
      };

  // ── Object overrides ──

  @override
  String toString() => 'NavNode($id, floor=$floor, type=${type.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NavNode && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV EDGE
// ─────────────────────────────────────────────────────────────────────────────

/// A directed edge connecting two [NavNode]s in the navigation graph.
///
/// Edges carry a traversal cost ([weight] in meters) and can be
/// dynamically blocked at runtime via [isBlocked].
///
/// ```dart
/// final edge = NavEdge(
///   from: 'CS-CORR-1F-01',
///   to: 'CS-CORR-1F-02',
///   weight: 10.0,
///   type: EdgeType.walk,
/// );
/// ```
class NavEdge {
  /// Source node ID.
  final String from;

  /// Destination node ID.
  final String to;

  /// Traversal cost in meters (physical distance).
  final double weight;

  /// Edge type — determines accessibility filtering.
  final EdgeType type;

  /// Whether this edge is currently blocked (real-time status).
  ///
  /// Set to `true` when a Firebase blocked-edge event arrives.
  /// The pathfinder skips edges where `isBlocked == true`.
  bool isBlocked;

  /// Whether this edge can be traversed in both directions.
  final bool bidirectional;

  /// Whether this edge is wheelchair-accessible.
  ///
  /// `false` for [EdgeType.stairs], `true` for everything else by default.
  final bool wheelchairAccessible;

  /// Operational status for display purposes.
  EdgeStatus status;

  /// Optional key-value metadata (congestion level, door width, etc.).
  final Map<String, dynamic> metadata;

  NavEdge({
    required this.from,
    required this.to,
    required this.weight,
    required this.type,
    this.isBlocked = false,
    this.bidirectional = true,
    bool? wheelchairAccessible,
    this.status = EdgeStatus.active,
    this.metadata = const {},
  }) : wheelchairAccessible = wheelchairAccessible ?? (type != EdgeType.stairs);

  /// Derived unique identifier for this edge.
  String get id => '${from}_to_$to';

  /// Whether this edge is currently traversable.
  bool get isActive => !isBlocked && status == EdgeStatus.active;

  /// Effective traversal cost considering congestion and accessibility.
  ///
  /// - Returns `double.infinity` for stairs when [wheelchairMode] is true.
  /// - Multiplies base weight by `1 + α × congestion` if congestion data exists.
  double effectiveWeight({bool wheelchairMode = false}) {
    if (wheelchairMode && type == EdgeType.stairs) {
      return double.infinity;
    }

    final congestion = (metadata['congestion_level'] as num?)?.toDouble() ?? 0.0;
    const alpha = 2.0;
    return weight * (1.0 + alpha * congestion);
  }

  // ── Serialization ──

  factory NavEdge.fromJson(Map<String, dynamic> json) {
    // Support both 'from'/'to' and 'from_node'/'to_node' keys
    final fromId = (json['from'] ?? json['from_node']) as String;
    final toId = (json['to'] ?? json['to_node']) as String;

    final typeStr = json['type'] as String? ?? 'walk';
    // Map edge type strings: 'corridor'/'door' → walk, 'stairs' → stairs, 'lift' → lift
    final edgeType = switch (typeStr) {
      'stairs' => EdgeType.stairs,
      'lift'   => EdgeType.lift,
      _        => EdgeType.walk,
    };

    final statusStr = json['status'] as String? ?? 'active';
    final edgeStatus = EdgeStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => EdgeStatus.active,
    );

    return NavEdge(
      from: fromId,
      to: toId,
      weight: (json['weight'] as num).toDouble(),
      type: edgeType,
      isBlocked: edgeStatus == EdgeStatus.blocked,
      bidirectional: json['bidirectional'] as bool? ?? true,
      wheelchairAccessible: json['wheelchair_accessible'] as bool?,
      status: edgeStatus,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'weight': weight,
        'type': type.name,
        'is_blocked': isBlocked,
        'bidirectional': bidirectional,
        'wheelchair_accessible': wheelchairAccessible,
        'status': status.name,
        'metadata': metadata,
      };

  // ── Object overrides ──

  @override
  String toString() =>
      'NavEdge($from → $to, ${weight}m, ${type.name}${isBlocked ? " BLOCKED" : ""})';
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV PATH
// ─────────────────────────────────────────────────────────────────────────────

/// A computed route through the navigation graph from source to destination.
///
/// Contains the full sequence of nodes and edges with distance/time metrics.
class NavPath {
  /// Ordered nodes from source to destination.
  final List<NavNode> nodes;

  /// Ordered edges traversed (length = nodes.length - 1).
  final List<NavEdge> edges;

  /// Total path distance in meters.
  final double totalDistance;

  const NavPath({
    required this.nodes,
    required this.edges,
    required this.totalDistance,
  });

  /// Estimated walking time in seconds (at 1.2 m/s average speed).
  double get estimatedTimeSeconds => totalDistance / 1.2;

  /// First node on the path.
  NavNode get source => nodes.first;

  /// Last node on the path.
  NavNode get destination => nodes.last;

  /// Whether this path involves a floor transition.
  bool get hasFloorTransition =>
      nodes.map((n) => n.floor).toSet().length > 1;

  /// Sorted list of distinct floors traversed.
  List<int> get floorsTraversed =>
      nodes.map((n) => n.floor).toSet().toList()..sort();

  /// Number of floor changes.
  int get floorTransitionCount {
    int count = 0;
    for (int i = 1; i < nodes.length; i++) {
      if (nodes[i].floor != nodes[i - 1].floor) count++;
    }
    return count;
  }

  /// Check if [edgeId] is part of this path.
  bool containsEdge(String edgeId) {
    return edges.any((e) => e.id == edgeId);
  }

  /// Find the closest point on this path to [pos].
  ///
  /// Returns the projected point, the perpendicular distance,
  /// and the segment index closest to the user.
  ({Position3D point, double distance, int segmentIndex}) nearestPoint(
      Position3D pos) {
    double minDist = double.infinity;
    Position3D nearest = nodes.first.position;
    int segment = 0;

    for (int i = 0; i < nodes.length - 1; i++) {
      final a = nodes[i].position;
      final b = nodes[i + 1].position;
      final projected = _projectOntoSegment(pos, a, b);
      final dist = pos.distanceTo(projected);

      if (dist < minDist) {
        minDist = dist;
        nearest = projected;
        segment = i;
      }
    }

    return (point: nearest, distance: minDist, segmentIndex: segment);
  }

  /// Remaining path distance from segment [fromIndex] to the destination.
  double remainingDistance(int fromIndex) {
    double dist = 0;
    for (int i = fromIndex; i < edges.length; i++) {
      dist += edges[i].weight;
    }
    return dist;
  }

  /// Project point [p] onto line segment [a]→[b], clamped to endpoints.
  static Position3D _projectOntoSegment(
      Position3D p, Position3D a, Position3D b) {
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z;
    if (lenSq == 0) return a;

    final t = ((ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / lenSq).clamp(0.0, 1.0);
    return a.lerp(b, t);
  }

  @override
  String toString() =>
      'NavPath(${nodes.length} nodes, ${totalDistance.toStringAsFixed(1)}m, '
      '~${estimatedTimeSeconds.toStringAsFixed(0)}s)';
}

// ─────────────────────────────────────────────────────────────────────────────
// QR ANCHOR
// ─────────────────────────────────────────────────────────────────────────────

/// A QR code placed at a known building location for AR calibration.
///
/// Scanning a QR anchor resets the user's position to ground truth
/// and establishes the building→AR coordinate transform.
class QRAnchor {
  /// Unique anchor ID (e.g. `"CS-QR-001"`).
  final String id;

  /// ID of the graph node this anchor maps to.
  final String mappedNode;

  /// Position offset from the mapped node (e.g. wall mount height).
  final Position3D offset;

  /// Facing direction of the QR code in building space (degrees).
  final double orientationYaw;

  const QRAnchor({
    required this.id,
    required this.mappedNode,
    this.offset = const Position3D(x: 0, y: 0, z: 0),
    this.orientationYaw = 0.0,
  });

  factory QRAnchor.fromJson(Map<String, dynamic> json) {
    return QRAnchor(
      id: json['id'] as String,
      mappedNode: json['mapped_node'] as String,
      offset: Position3D.fromJson(
        (json['offset'] as Map<String, dynamic>?) ?? {'x': 0, 'y': 0, 'z': 0},
      ),
      orientationYaw:
          (json['orientation']?['yaw'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mapped_node': mappedNode,
        'offset': offset.toJson(),
        'orientation': {'yaw': orientationYaw},
      };

  @override
  String toString() => 'QRAnchor($id → $mappedNode)';
}

// ─────────────────────────────────────────────────────────────────────────────
// USER POSITION
// ─────────────────────────────────────────────────────────────────────────────

/// Source of a user position estimate.
enum PositionSource {
  /// Ground-truth position from scanning a QR code.
  qrScan,

  /// Visual-inertial odometry tracking (ARCore / ARKit).
  vio,

  /// Combined QR + VIO estimate.
  hybrid,

  /// Manually set (debug / testing).
  manual,
}

/// The user's estimated position with confidence and source metadata.
///
/// Confidence bands:
/// - `1.0`       → just scanned a QR code (ground truth)
/// - `0.7 – 0.9` → recent QR + VIO tracking (reliable)
/// - `0.3 – 0.6` → VIO-only, drift accumulating (show warning)
/// - `< 0.3`     → high drift, needs recalibration (prompt QR scan)
class UserPosition {
  final Position3D position;
  final double confidence;
  final String? nearestNodeId;
  final int floor;
  final String building;
  final DateTime timestamp;
  final PositionSource source;

  const UserPosition({
    required this.position,
    required this.confidence,
    this.nearestNodeId,
    required this.floor,
    required this.building,
    required this.timestamp,
    required this.source,
  });

  /// Whether position is reliable enough for navigation decisions.
  bool get isReliable => confidence >= 0.5;

  /// Whether recalibration is urgently needed.
  bool get needsRecalibration => confidence < 0.3;

  @override
  String toString() =>
      'UserPosition($position, ${(confidence * 100).toStringAsFixed(0)}%, '
      'floor=$floor, ${source.name})';
}
