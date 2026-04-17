/// Navigation Controller — unified API for the navigation engine.
///
/// This controller ties together the graph, A* pathfinder, and dynamic
/// rerouting engine into a single stateful API. It maintains the active
/// navigation session and handles all position updates, off-path detection,
/// and automatic rerouting.
///
/// ```dart
/// final controller = NavigationController(graph: graph);
///
/// controller.setStartNode('CS-CORR-1F-01');
/// controller.setDestination('CS-103');
/// final path = controller.computePath();
///
/// // Every position tick (~100ms):
/// controller.updatePosition(Position3D(x: 10, y: 0, z: 15));
///
/// // When Firebase reports a blocked edge:
/// controller.onEdgeBlocked('CS-CORR-1F-02_to_CS-CORR-1F-03');
///
/// // Cleanup:
/// controller.dispose();
/// ```

import 'dart:async';
import 'dart:math';

import 'models.dart';
import 'graph.dart';
import 'astar.dart';
import 'dijkstra.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION STATE
// ─────────────────────────────────────────────────────────────────────────────

/// Current state of the navigation session.
enum NavigationState {
  /// No active navigation — waiting for destination.
  idle,

  /// Computing the path (async graph load).
  computing,

  /// Actively navigating — path is set and position is being tracked.
  navigating,

  /// Rerouting in progress due to off-path or blocked edge.
  rerouting,

  /// User has arrived at the destination.
  arrived,

  /// Navigation failed — no path found or critical error.
  error,
}

/// Reason why a reroute was triggered.
enum RerouteReason {
  /// User deviated too far from the path.
  offPath,

  /// An edge on the active path was blocked.
  edgeBlocked,

  /// User manually requested a new route.
  userRequested,

  /// Floor transition detected.
  floorChanged,
}

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION EVENT
// ─────────────────────────────────────────────────────────────────────────────

/// Events emitted by the controller for the UI layer to react to.
sealed class NavigationEvent {}

/// Path was successfully computed.
class PathComputed extends NavigationEvent {
  final NavPath path;
  final String algorithm;
  final int computeTimeMs;
  PathComputed({required this.path, required this.algorithm, required this.computeTimeMs});
}

/// User position was updated — includes progress info.
class PositionUpdated extends NavigationEvent {
  final double distanceToPath;
  final double remainingDistance;
  final int currentSegmentIndex;
  final String? nextInstruction;
  PositionUpdated({
    required this.distanceToPath,
    required this.remainingDistance,
    required this.currentSegmentIndex,
    this.nextInstruction,
  });
}

/// User is drifting off the path — warning state.
class OffPathWarning extends NavigationEvent {
  final double distanceToPath;
  final Duration offPathDuration;
  final Duration timeUntilReroute;
  OffPathWarning({
    required this.distanceToPath,
    required this.offPathDuration,
    required this.timeUntilReroute,
  });
}

/// Path was rerouted — new path available.
class PathRerouted extends NavigationEvent {
  final NavPath newPath;
  final RerouteReason reason;
  final String description;
  PathRerouted({required this.newPath, required this.reason, required this.description});
}

/// User has arrived at the destination.
class ArrivalDetected extends NavigationEvent {
  final NavNode destination;
  ArrivalDetected({required this.destination});
}

/// Navigation failed — display error to user.
class NavigationFailed extends NavigationEvent {
  final String message;
  NavigationFailed({required this.message});
}

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────

/// Stateful controller for an active navigation session.
///
/// Responsibilities:
/// - Maintains currentNode, destinationNode, and activePath
/// - Computes optimal paths using A* (cross-floor) or Dijkstra (same-floor)
/// - Tracks user position and detects off-path drift
/// - Triggers automatic rerouting when drift exceeds threshold
/// - Handles real-time edge blocking from Firebase
/// - Emits [NavigationEvent]s for the UI layer
class NavigationController {
  final NavigationGraph graph;

  // ─── Configuration ───

  /// Distance threshold (meters) for off-path detection.
  final double offPathThreshold;

  /// Grace period before auto-reroute triggers.
  final Duration offPathGracePeriod;

  /// Minimum time between reroute computations.
  final Duration rerouteCooldown;

  /// Distance (meters) at which arrival is detected.
  final double arrivalDistance;

  /// Whether to exclude stairs for wheelchair users.
  final bool wheelchairMode;

  // ─── Session State ───

  /// Current navigation state.
  NavigationState _state = NavigationState.idle;
  NavigationState get state => _state;

  /// Current user node (nearest graph node to position).
  String? _currentNode;
  String? get currentNode => _currentNode;

  /// Destination node ID.
  String? _destinationNode;
  String? get destinationNode => _destinationNode;

  /// Active computed path.
  NavPath? _activePath;
  NavPath? get activePath => _activePath;

  /// Last known user position.
  Position3D? _lastPosition;
  Position3D? get lastPosition => _lastPosition;

  /// Current floor.
  int _currentFloor = 1;
  int get currentFloor => _currentFloor;

  // ─── Internal Tracking ───

  /// When the user first went off-path (null = on-path).
  DateTime? _offPathSince;

  /// Timestamp of last reroute computation.
  DateTime? _lastRerouteTime;

  /// Total reroute count in this session.
  int _rerouteCount = 0;
  int get rerouteCount => _rerouteCount;

  /// Set of blocked edge IDs.
  final Set<String> _blockedEdges = {};

  /// Event stream for the UI layer.
  final _eventController = StreamController<NavigationEvent>.broadcast();
  Stream<NavigationEvent> get events => _eventController.stream;

  // ─── Constructor ───

  NavigationController({
    required this.graph,
    this.offPathThreshold = 5.0,
    this.offPathGracePeriod = const Duration(seconds: 3),
    this.rerouteCooldown = const Duration(seconds: 2),
    this.arrivalDistance = 2.0,
    this.wheelchairMode = false,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set the user's starting node.
  ///
  /// Call this after a QR code scan or VIO position fix.
  void setStartNode(String nodeId) {
    final node = graph.getNode(nodeId);
    if (node == null) {
      _emit(NavigationFailed(message: 'Start node "$nodeId" not found in graph.'));
      return;
    }

    _currentNode = nodeId;
    _currentFloor = node.floor;
    _lastPosition = node.position;
  }

  /// Set the navigation destination.
  ///
  /// Does NOT compute the path — call [computePath] after this.
  void setDestination(String nodeId) {
    final node = graph.getNode(nodeId);
    if (node == null) {
      _emit(NavigationFailed(message: 'Destination "$nodeId" not found in graph.'));
      return;
    }

    _destinationNode = nodeId;
  }

  /// Compute the optimal path from [currentNode] to [destinationNode].
  ///
  /// Auto-selects the algorithm:
  /// - **Dijkstra** for same-floor, small graphs (≤ 100 nodes)
  /// - **A*** for cross-floor or large graphs
  ///
  /// Returns the computed [NavPath] or null if no path exists.
  NavPath? computePath() {
    if (_currentNode == null) {
      _emit(NavigationFailed(message: 'Start node not set. Scan a QR code first.'));
      return null;
    }
    if (_destinationNode == null) {
      _emit(NavigationFailed(message: 'Destination not set.'));
      return null;
    }

    _state = NavigationState.computing;
    final stopwatch = Stopwatch()..start();

    // ── Algorithm selection ──
    final isCrossFloor = graph.requiresFloorTransition(_currentNode!, _destinationNode!);
    NavPath? path;
    String algorithm;

    if (isCrossFloor || graph.nodeCount > 100) {
      // A* for cross-floor or large graphs
      algorithm = 'A*';
      final astar = AStarPathfinder(graph, wheelchairMode: wheelchairMode);
      final result = astar.findPathWithStats(_currentNode!, _destinationNode!);
      path = result.path;
    } else {
      // Dijkstra for same-floor, small graphs
      algorithm = 'Dijkstra';
      final dijkstra = DijkstraPathfinder(graph, wheelchairMode: wheelchairMode);
      path = dijkstra.findPath(_currentNode!, _destinationNode!);
    }

    stopwatch.stop();

    // ── Handle result ──
    if (path == null) {
      _state = NavigationState.error;
      _emit(NavigationFailed(
        message: 'No path found to destination. '
            '${wheelchairMode ? "Try disabling wheelchair mode." : "Some corridors may be blocked."}',
      ));
      return null;
    }

    _activePath = path;
    _state = NavigationState.navigating;
    _offPathSince = null;

    _emit(PathComputed(
      path: path,
      algorithm: algorithm,
      computeTimeMs: stopwatch.elapsedMilliseconds,
    ));

    return path;
  }

  /// Update the user's current position.
  ///
  /// Call this every position tick (~100ms) during active navigation.
  /// Handles: progress tracking, off-path detection, arrival detection.
  void updatePosition(Position3D position) {
    _lastPosition = position;

    // Update nearest node
    final nearest = graph.findNearestNode(position, floor: _currentFloor);
    if (nearest != null) {
      _currentNode = nearest.id;
    }

    // No active navigation — nothing else to do
    if (_state != NavigationState.navigating || _activePath == null) return;

    final path = _activePath!;

    // ── Check arrival ──
    final destDist = position.distanceTo(path.destination.position);
    if (destDist < arrivalDistance) {
      _state = NavigationState.arrived;
      _emit(ArrivalDetected(destination: path.destination));
      return;
    }

    // ── Project position onto path ──
    final projection = path.nearestPoint(position);
    final distToPath = projection.distance;
    final segmentIdx = projection.segmentIndex;
    final remaining = path.remainingDistance(segmentIdx);

    // ── On-path: emit progress ──
    if (distToPath <= offPathThreshold) {
      _offPathSince = null; // Reset drift timer

      _emit(PositionUpdated(
        distanceToPath: distToPath,
        remainingDistance: remaining,
        currentSegmentIndex: segmentIdx,
        nextInstruction: _buildInstruction(segmentIdx),
      ));
      return;
    }

    // ── Off-path: detect drift ──
    detectOffPath(position, distToPath);
  }

  /// Detect if the user has deviated from the active path.
  ///
  /// Called internally by [updatePosition], but can also be called
  /// manually for testing.
  ///
  /// Logic:
  /// 1. If within threshold → on-track (reset timer)
  /// 2. If beyond threshold but within grace period → emit warning
  /// 3. If grace period expired → trigger reroute
  void detectOffPath(Position3D position, [double? distToPath]) {
    if (_activePath == null) return;

    distToPath ??= _activePath!.nearestPoint(position).distance;

    if (distToPath <= offPathThreshold) {
      _offPathSince = null;
      return;
    }

    // Start or continue drift tracking
    final now = DateTime.now();
    _offPathSince ??= now;
    final offDuration = now.difference(_offPathSince!);
    final timeUntilReroute = offPathGracePeriod - offDuration;

    if (timeUntilReroute > Duration.zero) {
      // Still within grace period — emit warning
      _emit(OffPathWarning(
        distanceToPath: distToPath,
        offPathDuration: offDuration,
        timeUntilReroute: timeUntilReroute,
      ));
    } else {
      // Grace period expired — reroute
      triggerReroute(RerouteReason.offPath);
    }
  }

  /// Trigger a reroute from the user's current position.
  ///
  /// Can be called:
  /// - Automatically when off-path grace period expires
  /// - Automatically when a path edge is blocked
  /// - Manually when the user taps "Reroute"
  void triggerReroute(RerouteReason reason) {
    if (_destinationNode == null || _lastPosition == null) {
      _emit(NavigationFailed(message: 'Cannot reroute — position or destination unknown.'));
      return;
    }

    // ── Debounce (skip if cooldown hasn't elapsed) ──
    if (reason != RerouteReason.userRequested &&
        reason != RerouteReason.edgeBlocked &&
        _lastRerouteTime != null) {
      final elapsed = DateTime.now().difference(_lastRerouteTime!);
      if (elapsed < rerouteCooldown) return;
    }

    _state = NavigationState.rerouting;

    // ── Find nearest graph node to current position ──
    final nearestNode = graph.findNearestNode(
      _lastPosition!,
      floor: _currentFloor,
    );

    if (nearestNode == null) {
      _state = NavigationState.error;
      _emit(NavigationFailed(
        message: 'Cannot determine position on graph. Scan a QR code.',
      ));
      return;
    }

    _currentNode = nearestNode.id;

    // ── Compute new path using A* ──
    final astar = AStarPathfinder(graph, wheelchairMode: wheelchairMode);
    final result = astar.findPathWithStats(nearestNode.id, _destinationNode!);

    if (result.path == null) {
      _state = NavigationState.error;
      _emit(NavigationFailed(message: _buildFailureMessage(reason)));
      return;
    }

    // ── Success: update state ──
    _activePath = result.path;
    _state = NavigationState.navigating;
    _offPathSince = null;
    _lastRerouteTime = DateTime.now();
    _rerouteCount++;

    _emit(PathRerouted(
      newPath: result.path!,
      reason: reason,
      description: _buildRerouteDescription(reason, result.path!),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDGE BLOCKING (Firebase Integration)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle a real-time edge-blocked notification.
  ///
  /// Called when Firebase reports a corridor is blocked.
  /// If the blocked edge is on the active path → immediate reroute.
  /// Otherwise → graph is updated silently.
  void onEdgeBlocked(String edgeId) {
    // Disable in graph
    graph.disableEdge(edgeId);
    _blockedEdges.add(edgeId);

    // Also disable reverse edge
    final parts = edgeId.split('_to_');
    if (parts.length == 2) {
      final reverseId = '${parts[1]}_to_${parts[0]}';
      graph.disableEdge(reverseId);
      _blockedEdges.add(reverseId);
    }

    // Check if active path is affected
    if (_activePath == null) return;

    final pathAffected = _activePath!.containsEdge(edgeId) ||
        (parts.length == 2 && _activePath!.containsEdge('${parts[1]}_to_${parts[0]}'));

    if (pathAffected) {
      triggerReroute(RerouteReason.edgeBlocked);
    }
  }

  /// Handle an edge being restored (unblocked).
  ///
  /// Re-enables the edge for future path calculations.
  /// Does NOT trigger a reroute (user keeps current path).
  void onEdgeRestored(String edgeId) {
    graph.enableEdge(edgeId);
    _blockedEdges.remove(edgeId);

    final parts = edgeId.split('_to_');
    if (parts.length == 2) {
      final reverseId = '${parts[1]}_to_${parts[0]}';
      graph.enableEdge(reverseId);
      _blockedEdges.remove(reverseId);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLOOR TRANSITIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle a floor change (detected via stairs/lift/barometer).
  void onFloorChanged(int newFloor) {
    _currentFloor = newFloor;

    // Check if this floor was expected
    if (_activePath != null) {
      final expectedFloors = _activePath!.floorsTraversed;
      if (!expectedFloors.contains(newFloor) && _lastPosition != null) {
        triggerReroute(RerouteReason.floorChanged);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stop the current navigation session and reset state.
  void stopNavigation() {
    _state = NavigationState.idle;
    _destinationNode = null;
    _activePath = null;
    _offPathSince = null;
    _lastRerouteTime = null;
    _rerouteCount = 0;
  }

  /// Reset everything including current position.
  void reset() {
    stopNavigation();
    _currentNode = null;
    _lastPosition = null;
    _currentFloor = 1;
    _blockedEdges.clear();
  }

  /// Dispose the controller and close streams.
  void dispose() {
    _eventController.close();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get a snapshot of the controller's state for debugging.
  Map<String, dynamic> get diagnostics => {
        'state': _state.name,
        'currentNode': _currentNode,
        'destinationNode': _destinationNode,
        'hasActivePath': _activePath != null,
        'currentFloor': _currentFloor,
        'rerouteCount': _rerouteCount,
        'isOffPath': _offPathSince != null,
        'blockedEdges': _blockedEdges.length,
        'pathDistance': _activePath?.totalDistance,
      };

  @override
  String toString() =>
      'NavigationController(state=${_state.name}, '
      'from=$_currentNode, to=$_destinationNode, '
      'reroutes=$_rerouteCount)';

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Emit an event to listeners.
  void _emit(NavigationEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Build a turn-by-turn instruction for the current segment.
  String? _buildInstruction(int segmentIndex) {
    if (_activePath == null || segmentIndex >= _activePath!.nodes.length - 1) {
      return null;
    }

    final current = _activePath!.nodes[segmentIndex];
    final next = _activePath!.nodes[segmentIndex + 1];

    // Determine direction based on node types
    if (next.type == NodeType.stairs) {
      return 'Head to the staircase';
    } else if (next.type == NodeType.lift) {
      return 'Head to the elevator';
    } else if (next.type == NodeType.room || next.type == NodeType.lab || next.type == NodeType.office) {
      return '${next.displayName} is ahead';
    } else if (next.type == NodeType.junction) {
      return 'Continue to ${next.displayName}';
    }

    // Default: distance-based
    final edge = _activePath!.edges[segmentIndex];
    return 'Continue ${edge.weight.toStringAsFixed(0)}m';
  }

  /// Build a failure message based on reroute reason.
  String _buildFailureMessage(RerouteReason reason) {
    switch (reason) {
      case RerouteReason.edgeBlocked:
        return 'All paths to destination are blocked. Try a different destination.';
      case RerouteReason.offPath:
        return 'Cannot find a route from current position. Scan a QR code.';
      case RerouteReason.floorChanged:
        return 'Cannot navigate from this floor. Return to a connected floor.';
      case RerouteReason.userRequested:
        return 'Unable to calculate a new route.';
    }
  }

  /// Build a human-readable reroute description.
  String _buildRerouteDescription(RerouteReason reason, NavPath path) {
    final dist = path.totalDistance.toStringAsFixed(0);
    final eta = path.estimatedTimeSeconds.toStringAsFixed(0);

    switch (reason) {
      case RerouteReason.offPath:
        return 'Rerouted: You went off path. New route: ${dist}m (~${eta}s)';
      case RerouteReason.edgeBlocked:
        return 'Rerouted: Corridor blocked. New route: ${dist}m (~${eta}s)';
      case RerouteReason.userRequested:
        return 'New route: ${dist}m (~${eta}s)';
      case RerouteReason.floorChanged:
        return 'Route adjusted for floor change: ${dist}m (~${eta}s)';
    }
  }
}
