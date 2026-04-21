import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:pedometer/pedometer.dart';
import '../core/models.dart';
import '../core/graph.dart';
import '../core/campus_data.dart';
import '../core/gps_config.dart';
import '../core/gps_service.dart';

/// Central state manager for the entire navigation app.
///
/// Manages indoor graph-based navigation AND GPS-based live tracking,
/// with smooth movement, turn-by-turn instructions, auto node switching,
/// and pedometer-based distance tracking.
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

  LatLng? _userGpsPosition;
  bool _isLiveTracking = false;
  double _bearingToDest = 0.0;
  double _distanceToDest = 0.0;
  double _remainingPathDistance = 0.0;
  double _deviceHeading = 0.0;
  StreamSubscription<GpsPosition>? _gpsStreamSub;
  bool _gpsAvailable = false;
  int _simulationIndex = 0;

  // ═══════════════════════════════════════════════════════════
  // FEATURE 1: GPS SMOOTHING
  // ═══════════════════════════════════════════════════════════

  /// Previous smoothed GPS position for low-pass filter.
  LatLng? _previousSmoothedPosition;

  /// Smoothing factor: 0 = full smooth (no movement), 1 = no smooth (raw GPS).
  /// 0.2 gives a nice balance for indoor use.
  static const double _smoothingAlpha = 0.25;

  /// Apply exponential low-pass filter to reduce GPS jitter.
  LatLng _smoothPosition(LatLng newPos) {
    if (_previousSmoothedPosition == null) {
      _previousSmoothedPosition = newPos;
      return newPos;
    }

    final smoothed = LatLng(
      _previousSmoothedPosition!.latitude +
          _smoothingAlpha * (newPos.latitude - _previousSmoothedPosition!.latitude),
      _previousSmoothedPosition!.longitude +
          _smoothingAlpha * (newPos.longitude - _previousSmoothedPosition!.longitude),
    );

    _previousSmoothedPosition = smoothed;
    return smoothed;
  }

  // ═══════════════════════════════════════════════════════════
  // FEATURE 3: AUTO NODE SWITCHING
  // ═══════════════════════════════════════════════════════════

  /// Arrival threshold — user is "arrived" within this distance (meters).
  static const double _arrivalThreshold = 8.0;

  /// Auto-advance threshold — switch to next node when within this (meters).
  static const double _autoAdvanceThreshold = 5.0;

  // ═══════════════════════════════════════════════════════════
  // FEATURE 4: PEDOMETER
  // ═══════════════════════════════════════════════════════════

  /// Step count when navigation started.
  int _stepCountAtStart = -1;

  /// Current step count from sensor.
  int _currentStepCount = 0;

  /// Steps walked during this navigation session.
  int _stepsWalked = 0;

  /// Average step length in meters (configurable).
  double _stepLength = 0.7;

  /// Distance walked based on pedometer (meters).
  double _walkedDistance = 0.0;

  /// Whether pedometer is available on this device.
  bool _pedometerAvailable = false;

  /// Pedometer stream subscription.
  StreamSubscription<StepCount>? _pedometerSub;

  NavigationProvider() {
    graph = buildCampusGraph();
    _initGps();
  }

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

  List<LatLng> get pathLatLngs {
    if (_activePath == null) return [];
    return _activePath!.nodes.map((node) {
      return localToLatLng(node.position, node.building);
    }).toList();
  }

  LatLng? get userLatLng => _userGpsPosition;

  LatLng? get destinationLatLng {
    final dest = destNode;
    if (dest == null) return null;
    return localToLatLng(dest.position, dest.building);
  }

  LatLng? get startLatLng {
    final start = startNode;
    if (start == null) return null;
    return localToLatLng(start.position, start.building);
  }

  String get formattedDistance => formatDistance(_distanceToDest);
  String get formattedRemainingDistance => formatDistance(_remainingPathDistance);
  String get directionToDestination => bearingToCardinal(_bearingToDest);

  double get relativeArrowAngle {
    return ((_bearingToDest - _deviceHeading) % 360) * pi / 180.0;
  }

  bool get hasArrived => _isNavigating && _distanceToDest < _arrivalThreshold;

  // ═══════════════════════════════════════════════════════════
  // GETTERS — Pedometer
  // ═══════════════════════════════════════════════════════════

  int get stepsWalked => _stepsWalked;
  double get walkedDistance => _walkedDistance;
  bool get pedometerAvailable => _pedometerAvailable;
  double get stepLength => _stepLength;

  /// Remaining distance = path total distance (in local units * ~1m each) - walked distance.
  /// We estimate remaining using GPS distance when walked < path distance.
  double get estimatedRemainingDistance {
    if (_activePath == null) return 0;
    // Use GPS straight-line distance as remaining
    return _distanceToDest;
  }

  String get formattedWalkedDistance => formatDistance(_walkedDistance);
  String get formattedEstimatedRemaining => formatDistance(estimatedRemainingDistance);

  // ═══════════════════════════════════════════════════════════
  // FEATURE 2: TURN-BY-TURN INSTRUCTIONS
  // ═══════════════════════════════════════════════════════════

  /// Generate smart turn-by-turn navigation instruction.
  String get currentInstruction {
    if (_activePath == null) return 'Select a destination';
    if (hasArrived) return '🎉 You have arrived!';

    final nodes = _activePath!.nodes;
    if (_currentSegmentIndex >= nodes.length - 1) {
      return '📍 Arriving at ${_activePath!.destination.displayName}';
    }

    final currentNode = nodes[_currentSegmentIndex];
    final nextNode = nodes[_currentSegmentIndex + 1];

    // Check for special node types first
    if (nextNode.type == NodeType.stairs) return '🚶 Head to the staircase';
    if (nextNode.type == NodeType.lift) return '🛗 Head to the elevator';
    if (nextNode.type == NodeType.washroom) return '🚻 Washroom ahead';
    if (nextNode.type == NodeType.entrance) return '🚪 Head to the entrance';

    // Calculate turn direction
    final turnInstruction = _getTurnInstruction(currentNode, nextNode);

    // Calculate distance to next node
    final distToNext = _distanceToNextNode();
    final distText = distToNext > 0 ? ' (${formatDistance(distToNext)})' : '';

    if (nextNode.isDestination) {
      return '📍 ${nextNode.displayName} ahead$distText';
    }

    return '$turnInstruction$distText';
  }

  /// Detailed instruction for the HUD showing next action.
  String get nextTurnInstruction {
    if (_activePath == null) return '';
    final nodes = _activePath!.nodes;
    if (_currentSegmentIndex + 2 >= nodes.length) return '';

    final nextNode = nodes[_currentSegmentIndex + 1];
    final afterNext = nodes[_currentSegmentIndex + 2];

    if (afterNext.type == NodeType.stairs) return 'Then: stairs ahead';
    if (afterNext.type == NodeType.lift) return 'Then: elevator ahead';

    final bearing1 = _bearingBetweenNodes(nextNode, afterNext);
    final bearing0 = _bearingBetweenNodes(
      nodes[_currentSegmentIndex], nextNode,
    );
    final turn = _classifyTurn(bearing0, bearing1);
    return 'Then: $turn';
  }

  /// Calculate bearing between two nav nodes (degrees, 0=North).
  double _bearingBetweenNodes(NavNode from, NavNode to) {
    final fromLatLng = localToLatLng(from.position, from.building);
    final toLatLng = localToLatLng(to.position, to.building);
    return calcBearing(fromLatLng, toLatLng);
  }

  /// Get turn instruction based on previous→current→next bearing change.
  String _getTurnInstruction(NavNode current, NavNode next) {
    final nodes = _activePath!.nodes;

    if (_currentSegmentIndex == 0) {
      // First segment — no previous bearing to compare
      return '→ Head toward ${next.displayName}';
    }

    final prev = nodes[_currentSegmentIndex - 1];
    final bearingPrevToCurrent = _bearingBetweenNodes(prev, current);
    final bearingCurrentToNext = _bearingBetweenNodes(current, next);

    return _classifyTurn(bearingPrevToCurrent, bearingCurrentToNext);
  }

  /// Classify turn direction from bearing change.
  String _classifyTurn(double fromBearing, double toBearing) {
    double angleDiff = (toBearing - fromBearing + 360) % 360;

    if (angleDiff > 180) angleDiff -= 360;

    if (angleDiff.abs() < 20) {
      return '⬆️ Continue straight';
    } else if (angleDiff >= 20 && angleDiff < 70) {
      return '↗️ Bear right slightly';
    } else if (angleDiff >= 70 && angleDiff < 120) {
      return '➡️ Turn right';
    } else if (angleDiff >= 120 && angleDiff < 160) {
      return '↘️ Sharp right turn';
    } else if (angleDiff <= -20 && angleDiff > -70) {
      return '↖️ Bear left slightly';
    } else if (angleDiff <= -70 && angleDiff > -120) {
      return '⬅️ Turn left';
    } else if (angleDiff <= -120 && angleDiff > -160) {
      return '↙️ Sharp left turn';
    } else {
      return '🔄 U-turn';
    }
  }

  /// Distance from user to the next node on the path (meters).
  double _distanceToNextNode() {
    if (_activePath == null || _userGpsPosition == null) return 0;
    if (_currentSegmentIndex + 1 >= _activePath!.nodes.length) return 0;

    final nextNode = _activePath!.nodes[_currentSegmentIndex + 1];
    final nextLatLng = localToLatLng(nextNode.position, nextNode.building);
    return calcDistance(_userGpsPosition!, nextLatLng);
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
      _userGpsPosition = localToLatLng(node.position, node.building);
      _previousSmoothedPosition = _userGpsPosition;
    }
    notifyListeners();
  }

  void setDestination(String nodeId) {
    _destNodeId = nodeId;
    notifyListeners();
  }

  void toggleWheelchairMode() {
    _wheelchairMode = !_wheelchairMode;
    if (_activePath != null) computePath();
    notifyListeners();
  }

  bool computePath() {
    if (_startNodeId == null || _destNodeId == null) return false;

    final startNode = graph.getNode(_startNodeId!);
    final destNode = graph.getNode(_destNodeId!);
    if (startNode == null || destNode == null) return false;

    final stopwatch = Stopwatch()..start();
    final isCrossFloor = startNode.floor != destNode.floor;

    if (isCrossFloor || graph.nodeCount > 100) {
      _algorithmUsed = 'A*';
      final astar = AStarPathfinder(graph, wheelchairMode: _wheelchairMode);
      final result = astar.findPathWithStats(_startNodeId!, _destNodeId!);
      _activePath = result.path;
      _nodesExplored = result.nodesExplored;
    } else {
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
    _previousSmoothedPosition = null;
    _resetPedometer();
    stopGpsTracking();
    notifyListeners();
  }

  void swapStartDest() {
    final tmp = _startNodeId;
    _startNodeId = _destNodeId;
    _destNodeId = tmp;
    if (_isNavigating) computePath();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // GPS LIVE TRACKING (with smoothing)
  // ═══════════════════════════════════════════════════════════

  Future<void> startGpsTracking() async {
    if (!_gpsAvailable) {
      debugPrint('GPS not available — using simulation mode');
      return;
    }

    // Get initial position
    final pos = await GpsService.instance.getCurrentPosition();
    if (pos != null) {
      _userGpsPosition = _smoothPosition(pos);
      _updateDistanceAndBearing();
      notifyListeners();
    }

    // Subscribe to position stream
    _gpsStreamSub?.cancel();
    _gpsStreamSub = GpsService.instance.getPositionStream(
      distanceFilter: 2, // More responsive: 2m instead of 3m
    ).listen(_onGpsUpdate);

    _isLiveTracking = true;

    // Start pedometer
    _startPedometer();

    notifyListeners();
  }

  void stopGpsTracking() {
    _gpsStreamSub?.cancel();
    _gpsStreamSub = null;
    _isLiveTracking = false;
    _stopPedometer();
    notifyListeners();
  }

  /// Called on each GPS position update — applies smoothing + auto-advance.
  void _onGpsUpdate(GpsPosition pos) {
    // ── Feature 1: Smooth the position ──
    _userGpsPosition = _smoothPosition(pos.latLng);

    // Update device heading from GPS if moving
    if (pos.heading > 0 && pos.speed > 0.5) {
      _deviceHeading = pos.heading;
    }

    _updateDistanceAndBearing();

    // ── Feature 3: Auto node switching ──
    _autoAdvanceNode();

    notifyListeners();
  }

  void updateDeviceHeading(double heading) {
    _deviceHeading = heading;
    notifyListeners();
  }

  void _updateDistanceAndBearing() {
    final userPos = _userGpsPosition;
    final destPos = destinationLatLng;

    if (userPos != null && destPos != null) {
      _distanceToDest = calcDistance(userPos, destPos);
      _bearingToDest = calcBearing(userPos, destPos);
    }
  }

  /// Feature 3: Auto-advance to next node when user is close enough.
  void _autoAdvanceNode() {
    if (_activePath == null || _userGpsPosition == null) return;

    final pathNodes = _activePath!.nodes;

    // Check nodes ahead (not behind) to avoid going backwards
    for (int i = _currentSegmentIndex; i < pathNodes.length; i++) {
      final nodeLatLng = localToLatLng(pathNodes[i].position, pathNodes[i].building);
      final dist = calcDistance(_userGpsPosition!, nodeLatLng);

      if (dist < _autoAdvanceThreshold && i > _currentSegmentIndex) {
        _currentSegmentIndex = i;
        _selectedFloor = pathNodes[i].floor;
        _remainingPathDistance = _activePath!.remainingDistance(i);
        debugPrint('📍 Auto-advanced to node $i: ${pathNodes[i].displayName}');
        break;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // PEDOMETER (Feature 4)
  // ═══════════════════════════════════════════════════════════

  void _startPedometer() {
    _stepCountAtStart = -1;
    _stepsWalked = 0;
    _walkedDistance = 0.0;

    try {
      _pedometerSub?.cancel();
      _pedometerSub = Pedometer.stepCountStream.listen(
        (StepCount event) {
          if (_stepCountAtStart < 0) {
            _stepCountAtStart = event.steps;
          }
          _currentStepCount = event.steps;
          _stepsWalked = _currentStepCount - _stepCountAtStart;
          _walkedDistance = _stepsWalked * _stepLength;
          _pedometerAvailable = true;
          notifyListeners();
        },
        onError: (error) {
          debugPrint('Pedometer error: $error');
          _pedometerAvailable = false;
        },
      );
    } catch (e) {
      debugPrint('Pedometer not available: $e');
      _pedometerAvailable = false;
    }
  }

  void _stopPedometer() {
    _pedometerSub?.cancel();
    _pedometerSub = null;
  }

  void _resetPedometer() {
    _stepCountAtStart = -1;
    _stepsWalked = 0;
    _walkedDistance = 0.0;
    _stopPedometer();
  }

  /// Configure step length (meters per step).
  void setStepLength(double length) {
    _stepLength = length.clamp(0.4, 1.2);
    _walkedDistance = _stepsWalked * _stepLength;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════
  // SIMULATION MODE (for emulator/desktop)
  // ═══════════════════════════════════════════════════════════

  void simulateStep() {
    if (_activePath == null) return;

    final pathLatlngs = pathLatLngs;
    if (pathLatlngs.isEmpty) return;

    _simulationIndex++;
    if (_simulationIndex >= pathLatlngs.length) {
      _simulationIndex = pathLatlngs.length - 1;
    }

    _userGpsPosition = pathLatlngs[_simulationIndex];
    _previousSmoothedPosition = _userGpsPosition;
    _currentSegmentIndex = _simulationIndex.clamp(0, _activePath!.nodes.length - 2);
    _selectedFloor = _activePath!.nodes[_currentSegmentIndex].floor;
    _remainingPathDistance = _activePath!.remainingDistance(_currentSegmentIndex);

    // Simulate pedometer steps
    _stepsWalked += 2;
    _walkedDistance = _stepsWalked * _stepLength;

    _updateDistanceAndBearing();
    notifyListeners();
  }

  void resetSimulation() {
    _simulationIndex = 0;
    _currentSegmentIndex = 0;
    _stepsWalked = 0;
    _walkedDistance = 0;
    if (_activePath != null) {
      _userGpsPosition = pathLatLngs.isNotEmpty ? pathLatLngs.first : null;
      _previousSmoothedPosition = _userGpsPosition;
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
    'stepsWalked': _stepsWalked,
    'walkedDistance': _walkedDistance,
    'pedometerAvailable': _pedometerAvailable,
  };

  @override
  void dispose() {
    _gpsStreamSub?.cancel();
    _pedometerSub?.cancel();
    super.dispose();
  }
}
