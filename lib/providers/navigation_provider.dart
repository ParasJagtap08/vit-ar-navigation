import 'package:flutter/foundation.dart';
import '../core/models.dart';
import '../core/graph.dart';
import '../core/campus_data.dart';

/// Central state manager for the entire navigation app.
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

  NavigationProvider() {
    graph = buildCampusGraph();
  }

  // ═══════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════
  // BUILDING / FLOOR SELECTION
  // ═══════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════

  void setStartNode(String nodeId) {
    _startNodeId = nodeId;
    final node = graph.getNode(nodeId);
    if (node != null) {
      _selectedBuilding = node.building;
      _selectedFloor = node.floor;
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

    if (_activePath != null) {
      _selectedFloor = startNode.floor;
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
      notifyListeners();
    }
  }

  void stopNavigation() {
    _activePath = null;
    _isNavigating = false;
    _currentSegmentIndex = 0;
    _destNodeId = null;
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

  // ═══════════════════════════════════════════════════════
  // REROUTING / EDGE BLOCKING
  // ═══════════════════════════════════════════════════════

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
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════
  // SEARCH
  // ═══════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════

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
  };
}
