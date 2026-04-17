/// Dynamic rerouting engine for real-time navigation path adaptation.
///
/// This engine handles three core responsibilities:
/// 1. **Off-path detection**: Determines when the user has deviated from
///    the calculated route and triggers automatic rerouting.
/// 2. **Edge invalidation**: Reacts to real-time edge status changes
///    (blocked corridors, maintenance) from Firebase listeners.
/// 3. **Smooth rerouting**: Computes a new path from the user's current
///    position to the original destination, with debouncing to prevent
///    excessive recalculations.
///
/// Time complexity:
/// - Off-path check: O(P) per tick, where P = path length (segment projection)
/// - Reroute computation: O((V + E) log V) — full A* recalculation
/// - Edge invalidation check: O(E_path) where E_path = edges in active path
///
/// This is a *stateful* engine. It must be created once per navigation session
/// and disposed when navigation ends.

import 'dart:async';

import 'models.dart';
import 'graph.dart';
import 'astar.dart';
import 'dijkstra.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REROUTE DECISION
// ─────────────────────────────────────────────────────────────────────────────

/// The reason a reroute was triggered.
enum RerouteReason {
  /// User deviated too far from the path for too long.
  offPath,

  /// An edge on the active path was blocked or disabled.
  edgeBlocked,

  /// User manually requested a reroute.
  userRequested,

  /// The user changed floors and the path needs adjustment.
  floorChanged,

  /// Congestion data changed, making a different path better.
  congestionUpdate,
}

/// Result of evaluating whether a reroute is needed.
sealed class RerouteDecision {
  const RerouteDecision();
}

/// User is on-track. No action needed.
class OnTrack extends RerouteDecision {
  /// Distance from user to nearest point on path (meters).
  final double distanceToPath;

  /// Current segment index on the path.
  final int currentSegmentIndex;

  /// Remaining distance to destination (meters).
  final double remainingDistance;

  const OnTrack({
    required this.distanceToPath,
    required this.currentSegmentIndex,
    required this.remainingDistance,
  });

  @override
  String toString() =>
      'OnTrack(distToPath=${distanceToPath.toStringAsFixed(1)}m, '
      'segment=$currentSegmentIndex, '
      'remaining=${remainingDistance.toStringAsFixed(1)}m)';
}

/// User is drifting off-path but hasn't triggered a reroute yet.
/// The UI should show a warning indicator.
class DriftWarning extends RerouteDecision {
  /// Distance from user to nearest point on path (meters).
  final double distanceToPath;

  /// How long the user has been off-path.
  final Duration offPathDuration;

  /// Time remaining before automatic reroute triggers.
  final Duration timeUntilReroute;

  const DriftWarning({
    required this.distanceToPath,
    required this.offPathDuration,
    required this.timeUntilReroute,
  });

  @override
  String toString() =>
      'DriftWarning(dist=${distanceToPath.toStringAsFixed(1)}m, '
      'offFor=${offPathDuration.inSeconds}s, '
      'rerouteIn=${timeUntilReroute.inSeconds}s)';
}

/// A reroute is needed. Contains the new path and the reason.
class RerouteNeeded extends RerouteDecision {
  /// The reason for rerouting.
  final RerouteReason reason;

  /// The newly calculated path.
  final NavPath newPath;

  /// Search statistics (only for A* reroutes).
  final AStarResult? searchResult;

  /// Description of what triggered the reroute (for UI display).
  final String description;

  const RerouteNeeded({
    required this.reason,
    required this.newPath,
    this.searchResult,
    required this.description,
  });

  @override
  String toString() =>
      'RerouteNeeded(reason=${reason.name}, '
      'newDist=${newPath.totalDistance.toStringAsFixed(1)}m, '
      '$description)';
}

/// Reroute failed—no alternative path exists.
class RerouteFailed extends RerouteDecision {
  /// The reason the original reroute was needed.
  final RerouteReason reason;

  /// Human-readable explanation.
  final String message;

  const RerouteFailed({
    required this.reason,
    required this.message,
  });

  @override
  String toString() => 'RerouteFailed(reason=${reason.name}, $message)';
}

// ─────────────────────────────────────────────────────────────────────────────
// DYNAMIC REROUTE ENGINE
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration parameters for the rerouting engine.
class RerouteConfig {
  /// Distance threshold (meters) beyond which user is considered off-path.
  final double offPathThresholdMeters;

  /// Duration the user must be off-path before automatic reroute triggers.
  final Duration offPathGracePeriod;

  /// Minimum time between reroute computations (debounce).
  final Duration rerouteCooldown;

  /// Whether to use A* (true) or Dijkstra (false) for reroute calculations.
  /// A* is recommended for cross-floor scenarios.
  final bool preferAStar;

  /// Whether wheelchair accessibility mode is active.
  final bool wheelchairMode;

  /// Distance (meters) ahead of user to check for blocked edges proactively.
  final double proactiveCheckDistance;

  const RerouteConfig({
    this.offPathThresholdMeters = 5.0,
    this.offPathGracePeriod = const Duration(seconds: 3),
    this.rerouteCooldown = const Duration(seconds: 2),
    this.preferAStar = true,
    this.wheelchairMode = false,
    this.proactiveCheckDistance = 20.0,
  });
}

/// Stateful engine that monitors user position against the active path
/// and triggers rerouting when needed.
///
/// Usage:
/// ```dart
/// final engine = DynamicRerouteEngine(
///   graph: navigationGraph,
///   config: RerouteConfig(),
/// );
///
/// // Set initial path
/// engine.setActivePath(path, destination: 'CS-101');
///
/// // Every position tick (100ms):
/// final decision = engine.evaluate(currentPosition);
/// switch (decision) {
///   case OnTrack():
///     updateProgress(decision.remainingDistance);
///   case DriftWarning():
///     showWarning(decision.distanceToPath);
///   case RerouteNeeded():
///     updatePath(decision.newPath);
///   case RerouteFailed():
///     showError(decision.message);
/// }
///
/// // When Firebase reports a blocked edge:
/// final decision = engine.handleEdgeBlocked('CS-CORR-1F-03_to_CS-CORR-1F-04');
///
/// // Cleanup
/// engine.dispose();
/// ```
class DynamicRerouteEngine {
  final NavigationGraph graph;
  final RerouteConfig config;

  // ───── Internal state ─────

  /// The currently active navigation path.
  NavPath? _activePath;

  /// The destination node ID.
  String? _destinationId;

  /// The user's most recently known position.
  Position3D? _lastKnownPosition;

  /// The user's current floor.
  int _currentFloor = 0;

  /// Timestamp when the user first went off-path (null if on-path).
  DateTime? _offPathSince;

  /// Timestamp of the last reroute computation.
  DateTime? _lastRerouteTime;

  /// Number of reroutes triggered in this session.
  int _rerouteCount = 0;

  /// History of blocked edges encountered.
  final Set<String> _blockedEdges = {};

  /// Stream controller for reroute events (for external listeners).
  final _rerouteController = StreamController<RerouteDecision>.broadcast();

  /// Stream of reroute decisions for external listeners.
  Stream<RerouteDecision> get rerouteStream => _rerouteController.stream;

  DynamicRerouteEngine({
    required this.graph,
    this.config = const RerouteConfig(),
  });

  // ─────────────────────────────────────────
  // Session Management
  // ─────────────────────────────────────────

  /// Set the active navigation path. Call this when navigation starts
  /// or when a new path is set from external sources.
  void setActivePath(NavPath path, {required String destination}) {
    _activePath = path;
    _destinationId = destination;
    _offPathSince = null;
    _lastRerouteTime = null;
  }

  /// Update the user's current floor (detected via barometer, stairs, or lift use).
  void setCurrentFloor(int floor) {
    _currentFloor = floor;
  }

  /// Get the current active path.
  NavPath? get activePath => _activePath;

  /// Number of reroutes in this session.
  int get rerouteCount => _rerouteCount;

  /// Dispose resources.
  void dispose() {
    _rerouteController.close();
  }

  // ─────────────────────────────────────────
  // Core: Position Evaluation
  // ─────────────────────────────────────────

  /// Evaluate the user's current position against the active path.
  ///
  /// This is the main method called every position tick (~100ms).
  /// It returns a [RerouteDecision] indicating whether the user is
  /// on-track, drifting, or needs a full reroute.
  ///
  /// Time complexity: O(P) for path projection + O((V+E) log V) if rerouting.
  RerouteDecision evaluate(Position3D currentPosition) {
    _lastKnownPosition = currentPosition;

    // No active path — nothing to evaluate
    if (_activePath == null || _destinationId == null) {
      return const RerouteFailed(
        reason: RerouteReason.offPath,
        message: 'No active navigation path',
      );
    }

    final path = _activePath!;

    // Check if destination reached
    final destDist = currentPosition.distanceTo(path.destination.position);
    if (destDist < 2.0) {
      return OnTrack(
        distanceToPath: 0,
        currentSegmentIndex: path.nodes.length - 1,
        remainingDistance: 0,
      );
    }

    // Project position onto path to find nearest segment
    final projection = path.nearestPoint(currentPosition);
    final distToPath = projection.distance;
    final segmentIdx = projection.segmentIndex;
    final remaining = path.remainingDistance(segmentIdx);

    // ─── ON-PATH ───
    if (distToPath <= config.offPathThresholdMeters) {
      _offPathSince = null; // Reset drift timer
      return OnTrack(
        distanceToPath: distToPath,
        currentSegmentIndex: segmentIdx,
        remainingDistance: remaining,
      );
    }

    // ─── OFF-PATH: Start or continue tracking drift ───
    final now = DateTime.now();
    _offPathSince ??= now;
    final offPathDuration = now.difference(_offPathSince!);
    final timeUntilReroute =
        config.offPathGracePeriod - offPathDuration;

    // Still within grace period → show warning
    if (timeUntilReroute > Duration.zero) {
      return DriftWarning(
        distanceToPath: distToPath,
        offPathDuration: offPathDuration,
        timeUntilReroute: timeUntilReroute,
      );
    }

    // ─── GRACE PERIOD EXPIRED: Trigger reroute ───
    return _computeReroute(currentPosition, RerouteReason.offPath);
  }

  // ─────────────────────────────────────────
  // Core: Edge Blocking
  // ─────────────────────────────────────────

  /// Handle a real-time notification that an edge has been blocked.
  ///
  /// This is called when the Firebase listener detects a new entry
  /// in the `realtime_status/{building}/blocked_edges` collection.
  ///
  /// If the blocked edge is on the active path, an immediate reroute
  /// is triggered. Otherwise, the graph is updated silently for future
  /// path calculations.
  ///
  /// Time complexity: O(E_path) for path check + O((V+E) log V) if rerouting.
  RerouteDecision handleEdgeBlocked(String edgeId) {
    // 1. Update graph state
    graph.disableEdge(edgeId);
    _blockedEdges.add(edgeId);

    // Also disable the reverse edge (for bidirectional edges)
    final parts = edgeId.split('_to_');
    if (parts.length == 2) {
      final reverseId = '${parts[1]}_to_${parts[0]}';
      graph.disableEdge(reverseId);
      _blockedEdges.add(reverseId);
    }

    // 2. Check if the active path is affected
    if (_activePath == null || _destinationId == null) {
      return const OnTrack(
        distanceToPath: 0,
        currentSegmentIndex: 0,
        remainingDistance: 0,
      );
    }

    final pathContainsEdge = _activePath!.containsEdge(edgeId) ||
        (parts.length == 2 &&
            _activePath!.containsEdge('${parts[1]}_to_${parts[0]}'));

    if (!pathContainsEdge) {
      // Path is not affected — graph updated for future queries
      return OnTrack(
        distanceToPath: 0,
        currentSegmentIndex: 0,
        remainingDistance: _activePath!.totalDistance,
      );
    }

    // 3. Path IS affected → immediate reroute
    if (_lastKnownPosition != null) {
      return _computeReroute(_lastKnownPosition!, RerouteReason.edgeBlocked);
    }

    return const RerouteFailed(
      reason: RerouteReason.edgeBlocked,
      message: 'Path blocked but current position unknown. Scan a QR code.',
    );
  }

  /// Handle an edge being restored (unblocked).
  ///
  /// Re-enables the edge in the graph. Does NOT trigger a reroute
  /// (the user may prefer the current path). The restored edge will
  /// be available for future path calculations.
  void handleEdgeRestored(String edgeId) {
    graph.enableEdge(edgeId);
    _blockedEdges.remove(edgeId);

    final parts = edgeId.split('_to_');
    if (parts.length == 2) {
      final reverseId = '${parts[1]}_to_${parts[0]}';
      graph.enableEdge(reverseId);
      _blockedEdges.remove(reverseId);
    }
  }

  // ─────────────────────────────────────────
  // Core: Manual & Floor-Change Reroute
  // ─────────────────────────────────────────

  /// Manually trigger a reroute (user tapped the "Reroute" button).
  RerouteDecision requestManualReroute(Position3D currentPosition) {
    _lastKnownPosition = currentPosition;
    return _computeReroute(currentPosition, RerouteReason.userRequested);
  }

  /// Handle a floor transition event.
  ///
  /// Called when the user takes stairs or a lift and arrives at a new floor.
  /// This adjusts the current floor and may recalculate the path if the
  /// user ended up on a different floor than expected.
  RerouteDecision handleFloorTransition(
      Position3D currentPosition, int newFloor) {
    final oldFloor = _currentFloor;
    _currentFloor = newFloor;
    _lastKnownPosition = currentPosition;

    if (_activePath == null || _destinationId == null) {
      return const RerouteFailed(
        reason: RerouteReason.floorChanged,
        message: 'No active navigation path',
      );
    }

    // Check if the floor transition was expected
    final expectedFloors = _activePath!.floorsTraversed;
    if (expectedFloors.contains(newFloor)) {
      // Expected floor — just re-evaluate position on path
      return evaluate(currentPosition);
    }

    // Unexpected floor — reroute
    return _computeReroute(currentPosition, RerouteReason.floorChanged);
  }

  // ─────────────────────────────────────────
  // Core: Proactive Blocked Edge Detection
  // ─────────────────────────────────────────

  /// Check if any edges in the upcoming path segment are blocked.
  ///
  /// This proactively detects problems *before* the user reaches them.
  /// Called periodically (e.g., every 5 seconds) during navigation.
  ///
  /// Returns a list of blocked edges that are within [proactiveCheckDistance]
  /// meters ahead of the user's current position on the path.
  List<NavEdge> checkUpcomingBlockedEdges(Position3D currentPosition) {
    if (_activePath == null) return [];

    final projection = _activePath!.nearestPoint(currentPosition);
    final currentSegment = projection.segmentIndex;
    final blockedEdges = <NavEdge>[];
    double cumulativeDist = 0;

    for (int i = currentSegment; i < _activePath!.edges.length; i++) {
      final edge = _activePath!.edges[i];
      cumulativeDist += edge.weight;

      if (cumulativeDist > config.proactiveCheckDistance) break;

      if (!edge.isActive || _blockedEdges.contains(edge.id)) {
        blockedEdges.add(edge);
      }
    }

    return blockedEdges;
  }

  // ─────────────────────────────────────────
  // Internal: Reroute Computation
  // ─────────────────────────────────────────

  /// Compute a new path from [currentPosition] to the destination.
  ///
  /// Applies debouncing to prevent excessive recalculations.
  /// Selects between Dijkstra and A* based on configuration and
  /// whether the route is cross-floor.
  RerouteDecision _computeReroute(
      Position3D currentPosition, RerouteReason reason) {
    // ─── Debounce check ───
    if (_lastRerouteTime != null &&
        reason != RerouteReason.userRequested && // Manual always allowed
        reason != RerouteReason.edgeBlocked) {
      // Edge blocks always reroute
      final elapsed = DateTime.now().difference(_lastRerouteTime!);
      if (elapsed < config.rerouteCooldown) {
        return DriftWarning(
          distanceToPath: config.offPathThresholdMeters + 1,
          offPathDuration: config.offPathGracePeriod,
          timeUntilReroute: config.rerouteCooldown - elapsed,
        );
      }
    }

    // ─── Find nearest graph node to current position ───
    final nearestNode = graph.findNearestNode(
      currentPosition,
      floor: _currentFloor,
    );

    if (nearestNode == null) {
      return RerouteFailed(
        reason: reason,
        message: 'Cannot determine current position on graph. '
            'Scan a QR code to recalibrate.',
      );
    }

    // ─── Determine algorithm ───
    final isCrossFloor =
        graph.requiresFloorTransition(nearestNode.id, _destinationId!);

    NavPath? newPath;
    AStarResult? astarResult;

    if (config.preferAStar || isCrossFloor) {
      // Use A* for cross-floor or when configured
      final astar = AStarPathfinder(
        graph,
        wheelchairMode: config.wheelchairMode,
      );
      astarResult = astar.findPath(nearestNode.id, _destinationId!);
      newPath = astarResult.path;
    } else {
      // Use Dijkstra for same-floor
      final dijkstra = DijkstraPathfinder(
        graph,
        wheelchairMode: config.wheelchairMode,
      );
      newPath = dijkstra.findPath(nearestNode.id, _destinationId!);
    }

    // ─── Handle result ───
    if (newPath == null) {
      return RerouteFailed(
        reason: reason,
        message: _buildFailureMessage(reason),
      );
    }

    // ─── Success: Update state ───
    _activePath = newPath;
    _offPathSince = null;
    _lastRerouteTime = DateTime.now();
    _rerouteCount++;

    final decision = RerouteNeeded(
      reason: reason,
      newPath: newPath,
      searchResult: astarResult,
      description: _buildRerouteDescription(reason, newPath),
    );

    // Emit to stream listeners
    _rerouteController.add(decision);

    return decision;
  }

  /// Build a human-readable failure message.
  String _buildFailureMessage(RerouteReason reason) {
    switch (reason) {
      case RerouteReason.edgeBlocked:
        return 'All paths to destination are currently blocked. '
            'Please wait or try a different destination.';
      case RerouteReason.offPath:
        return 'Cannot find a route from your current position. '
            'Try moving to a nearby corridor and scan a QR code.';
      case RerouteReason.floorChanged:
        return 'Cannot navigate from this floor to the destination. '
            'Please return to a connected floor.';
      default:
        return 'Unable to calculate a new route. '
            'Try scanning a QR code to update your position.';
    }
  }

  /// Build a human-readable reroute description.
  String _buildRerouteDescription(RerouteReason reason, NavPath newPath) {
    final dist = newPath.totalDistance.toStringAsFixed(0);
    final eta = newPath.estimatedTimeSeconds.toStringAsFixed(0);

    switch (reason) {
      case RerouteReason.offPath:
        return 'Rerouted: You went off the original path. '
            'New route: ${dist}m (~${eta}s)';
      case RerouteReason.edgeBlocked:
        return 'Rerouted: A corridor ahead is blocked. '
            'New route: ${dist}m (~${eta}s)';
      case RerouteReason.userRequested:
        return 'New route calculated: ${dist}m (~${eta}s)';
      case RerouteReason.floorChanged:
        return 'Route adjusted for floor change. '
            'New route: ${dist}m (~${eta}s)';
      case RerouteReason.congestionUpdate:
        return 'Better route found avoiding congestion. '
            'New route: ${dist}m (~${eta}s)';
    }
  }

  // ─────────────────────────────────────────
  // Diagnostics
  // ─────────────────────────────────────────

  /// Get engine diagnostics for debugging.
  Map<String, dynamic> get diagnostics => {
        'hasActivePath': _activePath != null,
        'destinationId': _destinationId,
        'currentFloor': _currentFloor,
        'isOffPath': _offPathSince != null,
        'offPathDuration': _offPathSince != null
            ? DateTime.now().difference(_offPathSince!).inMilliseconds
            : 0,
        'rerouteCount': _rerouteCount,
        'blockedEdgeCount': _blockedEdges.length,
        'blockedEdges': _blockedEdges.toList(),
        'lastRerouteTime': _lastRerouteTime?.toIso8601String(),
      };

  @override
  String toString() =>
      'DynamicRerouteEngine(reroutes=$_rerouteCount, '
      'blocked=${_blockedEdges.length}, '
      'offPath=${_offPathSince != null})';
}

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION ORCHESTRATOR
// ─────────────────────────────────────────────────────────────────────────────

/// High-level orchestrator that ties together the graph, pathfinders,
/// and rerouting engine into a single API for the BLoC layer.
///
/// This is the main entry point for all navigation logic.
///
/// Usage:
/// ```dart
/// final orchestrator = NavigationOrchestrator(graph: graph);
///
/// // Start navigation
/// final result = orchestrator.startNavigation(
///   fromNodeId: 'CS-CORR-1F-01',
///   toNodeId: 'CS-101',
/// );
///
/// // Position updates
/// final decision = orchestrator.onPositionUpdate(newPosition);
///
/// // Edge blocked (from Firebase)
/// final decision = orchestrator.onEdgeBlocked('CS-CORR-1F-03_to_CS-CORR-1F-04');
///
/// // Cleanup
/// orchestrator.dispose();
/// ```
class NavigationOrchestrator {
  final NavigationGraph graph;
  final RerouteConfig config;

  late final DynamicRerouteEngine _rerouteEngine;

  /// Currently active navigation path.
  NavPath? get activePath => _rerouteEngine.activePath;

  /// Stream of reroute decisions.
  Stream<RerouteDecision> get rerouteStream => _rerouteEngine.rerouteStream;

  NavigationOrchestrator({
    required this.graph,
    RerouteConfig? config,
  }) : config = config ?? const RerouteConfig() {
    _rerouteEngine = DynamicRerouteEngine(
      graph: graph,
      config: this.config,
    );
  }

  /// Start a new navigation session.
  ///
  /// Automatically selects the optimal algorithm:
  /// - Dijkstra for same-floor (≤100 nodes)
  /// - A* for cross-floor or large graphs
  ///
  /// Returns the computed path or null if no path exists.
  NavigationStartResult startNavigation({
    required String fromNodeId,
    required String toNodeId,
  }) {
    final fromNode = graph.getNode(fromNodeId);
    final toNode = graph.getNode(toNodeId);

    if (fromNode == null || toNode == null) {
      return NavigationStartResult(
        path: null,
        algorithm: 'none',
        computeTimeMs: 0,
        nodesExplored: 0,
        error: 'Invalid source or destination node ID.',
      );
    }

    final isCrossFloor = fromNode.floor != toNode.floor;
    final stopwatch = Stopwatch()..start();
    NavPath? path;
    String algorithm;
    int nodesExplored = 0;

    if (isCrossFloor || graph.nodeCount > 100) {
      // Use A* for cross-floor or large graphs
      algorithm = 'A*';
      final astar = AStarPathfinder(
        graph,
        wheelchairMode: config.wheelchairMode,
      );
      final result = astar.findPath(fromNodeId, toNodeId);
      path = result.path;
      nodesExplored = result.nodesExplored;
    } else {
      // Use Dijkstra for same-floor, small graphs
      algorithm = 'Dijkstra';
      final dijkstra = DijkstraPathfinder(
        graph,
        wheelchairMode: config.wheelchairMode,
      );
      path = dijkstra.findPath(fromNodeId, toNodeId);
    }

    stopwatch.stop();

    if (path != null) {
      _rerouteEngine.setActivePath(path, destination: toNodeId);
      _rerouteEngine.setCurrentFloor(fromNode.floor);
    }

    return NavigationStartResult(
      path: path,
      algorithm: algorithm,
      computeTimeMs: stopwatch.elapsedMilliseconds,
      nodesExplored: nodesExplored,
      error: path == null ? 'No path found between $fromNodeId and $toNodeId.' : null,
    );
  }

  /// Process a position update. Call every ~100ms during active navigation.
  RerouteDecision onPositionUpdate(Position3D position) {
    return _rerouteEngine.evaluate(position);
  }

  /// Handle a blocked edge notification from Firebase.
  RerouteDecision onEdgeBlocked(String edgeId) {
    return _rerouteEngine.handleEdgeBlocked(edgeId);
  }

  /// Handle an edge being unblocked.
  void onEdgeRestored(String edgeId) {
    _rerouteEngine.handleEdgeRestored(edgeId);
  }

  /// Handle user's manual reroute request.
  RerouteDecision onManualReroute(Position3D currentPosition) {
    return _rerouteEngine.requestManualReroute(currentPosition);
  }

  /// Handle floor transition.
  RerouteDecision onFloorChanged(Position3D position, int newFloor) {
    return _rerouteEngine.handleFloorTransition(position, newFloor);
  }

  /// Check for upcoming blocked edges (proactive).
  List<NavEdge> checkAhead(Position3D position) {
    return _rerouteEngine.checkUpcomingBlockedEdges(position);
  }

  /// Stop the current navigation session.
  void stopNavigation() {
    // Engine state resets implicitly when setActivePath is called next.
  }

  /// Dispose all resources.
  void dispose() {
    _rerouteEngine.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION START RESULT
// ─────────────────────────────────────────────────────────────────────────────

/// Result of starting a new navigation session.
class NavigationStartResult {
  /// The computed path, or null if no path exists.
  final NavPath? path;

  /// Algorithm used ('Dijkstra', 'A*', or 'none').
  final String algorithm;

  /// Computation time in milliseconds.
  final int computeTimeMs;

  /// Number of nodes explored during pathfinding.
  final int nodesExplored;

  /// Error message, or null if successful.
  final String? error;

  const NavigationStartResult({
    required this.path,
    required this.algorithm,
    required this.computeTimeMs,
    required this.nodesExplored,
    this.error,
  });

  bool get success => path != null;

  @override
  String toString() =>
      'NavigationStartResult(algorithm=$algorithm, '
      '${success ? 'dist=${path!.totalDistance.toStringAsFixed(1)}m' : 'error=$error'}, '
      '${computeTimeMs}ms, explored=$nodesExplored)';
}
