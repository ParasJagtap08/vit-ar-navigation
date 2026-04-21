import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../core/models.dart';
import '../core/graph.dart';
import '../core/campus_data.dart';
import '../core/gps_config.dart';
import '../core/gps_service.dart';

/// Central state manager for the entire navigation app.
///
/// Manages both the indoor graph-based navigation AND
/// GPS-based live tracking for the map navigation view.
class NavigationProvider extends ChangeNotifier {
  // ─── Graph ───
  late final NavigationGraph graph;

  // ─── Selected building / floor ───
  String? _selectedBuilding;
  int _selectedFloor = 1;

  // ─── Navigation state ───
  String? _startNodeId;
  String? _destNodeId;
  NavPath? _activePath;
  String? _algorithmUsed;
  int _computeTimeMs = 0;
  int _nodesExplored = 0;
  bool _isNavigating = false;
  bool _wheelchairMode = false;
  int _currentSegmentIndex = 0;

  // ─── Search ───
  List<NavNode> _searchResults = [];
  String _searchQuery = '';

  // ─── Blocked edges ───
  final Set<String> _blockedEdges = {};

  // ═══════════════════════════════════════════════════════════
  // GPS TRACKING STATE
  // ═══════════════════════════════════════════════════════════

  /// Current user GPS position.
  LatLng? _userGpsPosition;

  /// Whether live GPS tracking is active.
  bool _isLiveTracking = false;

  /// Compass bearing FROM user TO destination (degrees, 0=North).
  double _bearingToDest = 0.0;

  /// Distance FROM user TO destination (meters).
  double _distanceToDest = 0.0;

  /// Distance remaining along the path (meters).
  double _remainingPathDistance = 0.0;

  /// Device compass heading (degrees, 0=North).
  double _deviceHeading = 0.0;

  /// GPS stream subscription.
  StreamSubscription<GpsPosition>? _gpsStreamSub;

  /// Whether GPS is available.
  bool _gpsAvailable = false;

  /// Simulation mode index (for emulator testing).
  int _simulationIndex = 0;

  /// Arrival threshold in meters — user is "arrived" within this distance.
  static const double _arrivalThreshold = 8.0;

  /// Proximity threshold for segment advancement (meters).
  static const double _segmentProximity = 10.0;

  NavigationProvider() {
    graph = buildCampusGraph();
    _initGps();
  }

  /// Initialize GPS service on creation.
  Future<void> _initGps() async {
    _gpsAvailable = await GpsService.instance.initialize();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // GETTERS — Original
  // ═══════════════════════════════════════════════════════════

  String? get selectedBuilding => _selectedBuilding;
  int get selectedFloor => _selectedFloor;
  String? get startNodeId => _startNodeId;
  String? get destNodeId => _destNodeId;
  NavPath? get activePath => _activePath;
  String? get algorithmUsed => _algorithmUsed;
  int get computeTimeMs => _computeTimeMs;
  int get nodesExplored => _nodesExplored;
  bool get isNavigating => _isNavigating;
  bool get wheelchairMode => _wheelchairMode;
  int get currentSegmentIndex => _currentSegmentIndex;
  List<NavNode> get searchResults => _searchResults;
  String get searchQuery => _searchQuery;
  Set<String> get blockedEdges => _blockedEdges;

  List<NavNode> get floorNodes {
    if (_selectedBuilding == null) return [];
    return graph.getNodesByBuilding(_selectedBuilding!)
        .where((n) => n.floor == _selectedFloor)
        .toList();
  }

  List<NavNode> get buildingDestinations {
    if (_selectedBuilding == null) return [];
    return graph.getDestinations(building: _selectedBuilding!);
  }

  NavNode? get startNode => _startNodeId != null ? graph.getNode(_startNodeId!) : null;
  NavNode? get destNode => _destNodeId != null ? graph.getNode(_destNodeId!) : null;

  // ═══════════════════════════════════════════════════════════
  // GETTERS — GPS
  // ═══════════════════════════════════════════════════════════

  LatLng? get userGpsPosition => _userGpsPosition;
  bool get isLiveTracking => _isLiveTracking;
  double get bearingToDest => _bearingToDest;
  double get distanceToDest => _distanceToDest;
  double get remainingPathDistance => _remainingPathDistance;
  double get deviceHeading => _deviceHeading;
  bool get gpsAvailable => _gpsAvailable;
  int get simulationIndex => _simulationIndex;

  /// Convert the active path's nodes to GPS coordinates for map display.
  List<LatLng> get pathLatLngs {
    if (_activePath == null) return [];
    return _activePath!.nodes.map((node) {
      return localToLatLng(node.position, node.building);
    }).toList();
  }

  /// The user's current position as LatLng — either GPS or simulated.
  LatLng? get userLatLng => _userGpsPosition;

  /// The destination node converted to GPS.
  LatLng? get destinationLatLng {
    final dest = destNode;
    if (dest == null) return null;
    return localToLatLng(dest.position, dest.building);
  }

  /// The start node converted to GPS.
  LatLng? get startLatLng {
    final start = startNode;
    if (start == null) return null;
    return localToLatLng(start.position, start.building);
  }

  /// Formatted distance to destination.
  String get formattedDistance => formatDistance(_distanceToDest);

  /// Formatted remaining path distance.
  String get formattedRemainingDistance => formatDistance(_remainingPathDistance);

  /// Cardinal direction to destination (N, NE, E, etc.).
  String get directionToDestination => bearingToCardinal(_bearingToDest);

  /// The relative arrow rotation for the direction widget.
  /// This is the angle between device heading and bearing to destination.
  double get relativeArrowAngle {
    return ((_bearingToDest - _deviceHeading) % 360) * pi / 180.0;
  }

  /// Check if user has arrived at the destination.
  bool get hasArrived => _isNavigating && _distanceToDest < _arrivalThreshold;

  /// Current navigation instruction text.
  String get currentInstruction {
    if (_activePath == null) return 'Select a destination';
    if (hasArrived) return '🎉 You have arrived!';

    if (_currentSegmentIndex < _activePath!.nodes.length - 1) {
      final next = _activePath!.nodes[_currentSegmentIndex + 1];
      if (next.type == NodeType.stairs) return '🚶 Head to the staircase';
      if (next.type == NodeType.lift) return '🛗 Head to the elevator';
      if (next.type == NodeType.washroom) return '🚻 Washroom ahead';
      if (next.type == NodeType.entrance) return '🚪 Head to the entrance';
      if (next.isDestination) return '📍 ${next.displayName} ahead';
      return '→ Continue to ${next.displayName}';
    }
    return '📍 Arriving at ${_activePath!.destination.displayName}';
  }

  // ═══════════════════════════════════════════════════════════
  // BUILDING / FLOOR SELECTION
  // ═══════════════════════════════════════════════════════════

  void selectBuilding(String buildingId) {
    _selectedBuilding = buildingId;
    _selectedFloor = 1;
    _startNodeId = null;
    _destNodeId = null;
    _activePath = null;
    _isNavigating = false;
    notifyListeners();
  }

  void selectFloor(int floor) {
    _selectedFloor = floor;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════════

  void setStartNode(String nodeId) {
    _startNodeId = nodeId;
    final node = graph.getNode(nodeId);
    if (node != null) {
      _selectedBuilding = node.building;
      _selectedFloor = node.floor;
      // Set user GPS position to the start node's GPS coordinates
      _userGpsPosition = localToLatLng(node.position, node.building);
    }
    notifyListeners();
  }

  void setDestination(String nodeId) {
    _destNodeId = nodeId;
    notifyListeners();
  }

  void toggleWheelchairMode() {
    _wheelchairMode = !_wheelchairMode;
    if (_activePath != null) {
      computePath();
    }
    notifyListeners();
  }

  /// Compute the optimal path using auto-selected algorithm.
  bool computePath() {
    if (_startNodeId == null || _destNodeId == null) return false;

    final startNode = graph.getNode(_startNodeId!);
    final destNode = graph.getNode(_destNodeId!);
    if (startNode == null || destNode == null) return false;

    final stopwatch = Stopwatch()..start();

    final isCrossFloor = startNode.floor != destNode.floor;

    if (isCrossFloor || graph.nodeCount > 100) {
      // A* for cross-floor or large graphs
      _algorithmUsed = 'A*';
      final astar = AStarPathfinder(graph, wheelchairMode: _wheelchairMode);
      final result = astar.findPathWithStats(_startNodeId!, _destNodeId!);
      _activePath = result.path;
      _nodesExplored = result.nodesExplored;
    } else {
      // Dijkstra for same-floor, small graphs
      _algorithmUsed = 'Dijkstra';
      final dijkstra = DijkstraPathfinder(graph, wheelchairMode: _wheelchairMode);
      _activePath = dijkstra.findPath(_startNodeId!, _destNodeId!);
      _nodesExplored = 0;
    }

    stopwatch.stop();
    _computeTimeMs = stopwatch.elapsedMilliseconds;
    _isNavigating = _activePath != null;
    _currentSegmentIndex = 0;
    _simulationIndex = 0;

    if (_activePath != null) {
      _selectedFloor = startNode.floor;
      _remainingPathDistance = _activePath!.totalDistance;
      _updateDistanceAndBearing();
    }

    notifyListeners();
    return _activePath != null;
  }

  /// Find nearest amenity of a given type from start node.
  bool findNearestAmenity(NodeType type) {
    if (_startNodeId == null) return false;
    final dijkstra = DijkstraPathfinder(graph, wheelchairMode: _wheelchairMode);
    final path = dijkstra.findNearestOfType(_startNodeId!, type);
    if (path != null) {
      _destNodeId = path.destination.id;
      _activePath = path;
      _algorithmUsed = 'Dijkstra';
      _isNavigating = true;
      _currentSegmentIndex = 0;
      _simulationIndex = 0;
      _remainingPathDistance = path.totalDistance;
      _updateDistanceAndBearing();
      notifyListeners();
      return true;
    }
    return false;
  }

  void advanceSegment() {
    if (_activePath == null) return;
    if (_currentSegmentIndex < _activePath!.nodes.length - 2) {
      _currentSegmentIndex++;
      final node = _activePath!.nodes[_currentSegmentIndex];
      _selectedFloor = node.floor;
      _remainingPathDistance = _activePath!.remainingDistance(_currentSegmentIndex);
      _updateDistanceAndBearing();
      notifyListeners();
    }
  }

  void stopNavigation() {
    _activePath = null;
    _isNavigating = false;
    _currentSegmentIndex = 0;
    _destNodeId = null;
    _simulationIndex = 0;
    _distanceToDest = 0;
    _bearingToDest = 0;
    _remainingPathDistance = 0;
    stopGpsTracking();
    notifyListeners();
  }

  /// Swap start and destination.
  void swapStartDest() {
    final tmp = _startNodeId;
    _startNodeId = _destNodeId;
    _destNodeId = tmp;
    if (_isNavigating) computePath();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // GPS LIVE TRACKING
  // ═══════════════════════════════════════════════════════════

  /// Start GPS live tracking.
  Future<void> startGpsTracking() async {
    if (!_gpsAvailable) {
      debugPrint('GPS not available — using simulation mode');
      return;
    }

    // Get initial position
    final pos = await GpsService.instance.getCurrentPosition();
    if (pos != null) {
      _userGpsPosition = pos;
      _updateDistanceAndBearing();
      notifyListeners();
    }

    // Subscribe to position stream
    _gpsStreamSub?.cancel();
    _gpsStreamSub = GpsService.instance.getPositionStream(
      distanceFilter: 3,
    ).listen(_onGpsUpdate);

    _isLiveTracking = true;
    notifyListeners();
  }

  /// Stop GPS live tracking.
  void stopGpsTracking() {
    _gpsStreamSub?.cancel();
    _gpsStreamSub = null;
    _isLiveTracking = false;
    notifyListeners();
  }

  /// Called on each GPS position update.
  void _onGpsUpdate(GpsPosition pos) {
    _userGpsPosition = pos.latLng;

    // Update device heading from GPS if available
    if (pos.heading > 0 && pos.speed > 0.5) {
      _deviceHeading = pos.heading;
    }

    _updateDistanceAndBearing();
    _updateSegmentFromGps();
    notifyListeners();
  }

  /// Update device heading from compass.
  void updateDeviceHeading(double heading) {
    _deviceHeading = heading;
    notifyListeners();
  }

  /// Recalculate distance and bearing from user to destination.
  void _updateDistanceAndBearing() {
    final userPos = _userGpsPosition;
    final destPos = destinationLatLng;

    if (userPos != null && destPos != null) {
      _distanceToDest = calcDistance(userPos, destPos);
      _bearingToDest = calcBearing(userPos, destPos);
    }
  }

  /// Advance segment index based on GPS proximity to path nodes.
  void _updateSegmentFromGps() {
    if (_activePath == null || _userGpsPosition == null) return;

    final pathNodes = _activePath!.nodes;

    // Find the closest path node to the user's GPS position
    double minDist = double.infinity;
    int closestIdx = _currentSegmentIndex;

    for (int i = _currentSegmentIndex; i < pathNodes.length; i++) {
      final nodeLatLng = localToLatLng(pathNodes[i].position, pathNodes[i].building);
      final dist = calcDistance(_userGpsPosition!, nodeLatLng);
      if (dist < minDist) {
        minDist = dist;
        closestIdx = i;
      }
    }

    // Advance segment if we're close enough to the next node
    if (closestIdx > _currentSegmentIndex && minDist < _segmentProximity) {
      _currentSegmentIndex = closestIdx;
      _selectedFloor = pathNodes[closestIdx].floor;
      _remainingPathDistance = _activePath!.remainingDistance(closestIdx);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SIMULATION MODE (for emulator/desktop)
  // ═══════════════════════════════════════════════════════════

  /// Simulate walking along the path by interpolating GPS positions.
  void simulateStep() {
    if (_activePath == null) return;

    final pathLatlngs = pathLatLngs;
    if (pathLatlngs.isEmpty) return;

    // Advance simulation index
    _simulationIndex++;
    if (_simulationIndex >= pathLatlngs.length) {
      _simulationIndex = pathLatlngs.length - 1;
    }

    // Set user position to the interpolated point
    _userGpsPosition = pathLatlngs[_simulationIndex];

    // Update segment
    _currentSegmentIndex = _simulationIndex.clamp(0, _activePath!.nodes.length - 2);
    _selectedFloor = _activePath!.nodes[_currentSegmentIndex].floor;
    _remainingPathDistance = _activePath!.remainingDistance(_currentSegmentIndex);
    _updateDistanceAndBearing();

    notifyListeners();
  }

  /// Reset simulation to the start of the path.
  void resetSimulation() {
    _simulationIndex = 0;
    _currentSegmentIndex = 0;
    if (_activePath != null) {
      _userGpsPosition = pathLatLngs.isNotEmpty ? pathLatLngs.first : null;
      _remainingPathDistance = _activePath!.totalDistance;
      _selectedFloor = _activePath!.nodes.first.floor;
      _updateDistanceAndBearing();
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // REROUTING / EDGE BLOCKING
  // ═══════════════════════════════════════════════════════════

  void blockEdge(String edgeId) {
    graph.disableEdge(edgeId);
    _blockedEdges.add(edgeId);

    // If active path is affected, reroute
    if (_activePath != null && _activePath!.containsEdge(edgeId)) {
      computePath();
    }
    notifyListeners();
  }

  void unblockEdge(String edgeId) {
    graph.enableEdge(edgeId);
    _blockedEdges.remove(edgeId);
    notifyListeners();
  }

  void reroute() {
    if (_startNodeId == null || _destNodeId == null) return;
    // Use A* for reroute since we want the fastest path
    _algorithmUsed = 'A*';
    final astar = AStarPathfinder(graph, wheelchairMode: _wheelchairMode);
    final result = astar.findPathWithStats(_startNodeId!, _destNodeId!);
    _activePath = result.path;
    _nodesExplored = result.nodesExplored;
    _isNavigating = _activePath != null;
    _currentSegmentIndex = 0;
    _simulationIndex = 0;
    if (_activePath != null) {
      _remainingPathDistance = _activePath!.totalDistance;
      _updateDistanceAndBearing();
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // SEARCH
  // ═══════════════════════════════════════════════════════════

  void search(String query) {
    _searchQuery = query;
    if (query.trim().length < 2) {
      _searchResults = [];
    } else {
      _searchResults = graph.searchNodes(query);
    }
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════

  Map<String, dynamic> get diagnostics => {
    'totalNodes': graph.nodeCount,
    'totalEdges': graph.edgeCount,
    'buildings': graph.buildings.length,
    'selectedBuilding': _selectedBuilding,
    'selectedFloor': _selectedFloor,
    'startNode': _startNodeId,
    'destNode': _destNodeId,
    'hasPath': _activePath != null,
    'pathLength': _activePath?.nodes.length,
    'pathDistance': _activePath?.totalDistance,
    'algorithm': _algorithmUsed,
    'computeTimeMs': _computeTimeMs,
    'wheelchairMode': _wheelchairMode,
    'blockedEdges': _blockedEdges.length,
    'gpsAvailable': _gpsAvailable,
    'isLiveTracking': _isLiveTracking,
    'userGps': _userGpsPosition?.toString(),
    'distanceToDest': _distanceToDest,
    'bearingToDest': _bearingToDest,
  };

  @override
  void dispose() {
    _gpsStreamSub?.cancel();
    super.dispose();
  }
}
