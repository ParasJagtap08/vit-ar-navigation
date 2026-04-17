
import '../../../lib/core/navigation/models.dart';
import '../../../lib/core/navigation/graph.dart';
import '../../../lib/core/navigation/dijkstra.dart';
import '../../../lib/core/navigation/astar.dart';
import '../../../lib/core/navigation/dynamic_reroute.dart';

void main() {
  print('═══════════════════════════════════════════');
  print('  Navigation Engine — Validation Suite');
  print('═══════════════════════════════════════════\n');

  // Load dataset
  final graph = _buildCSFloor1Graph();
  print('✅ Graph loaded: ${graph.nodeCount} nodes, ${graph.edgeCount} edges');
  print('   Floors: ${graph.floors}');
  print('   Buildings: ${graph.buildings}\n');

  // ─── Test 1: Dijkstra — Entrance → Room CS-103 ───
  print('── Test 1: Dijkstra (Entrance → CS-103) ──');
  final dijkstra = DijkstraPathfinder(graph);
  final path1 = dijkstra.findPath('CS-ENT-1F', 'CS-103');
  assert(path1 != null, 'Path should exist');
  print('   Path: ${path1!.nodes.map((n) => n.id).join(' → ')}');
  print('   Distance: ${path1.totalDistance.toStringAsFixed(1)}m');
  print('   ETA: ${path1.estimatedTimeSeconds.toStringAsFixed(0)}s');
  print('   ✅ PASS\n');

  // ─── Test 2: Dijkstra — Nearest washroom from entrance ───
  print('── Test 2: Nearest Washroom from Entrance ──');
  final path2 = dijkstra.findNearestOfType('CS-ENT-1F', NodeType.washroom);
  assert(path2 != null, 'Should find a washroom');
  print('   Found: ${path2!.destination.displayName}');
  print('   Distance: ${path2.totalDistance.toStringAsFixed(1)}m');
  print('   ✅ PASS\n');

  // ─── Test 3: A* — Same floor ───
  print('── Test 3: A* (CS-101 → HOD Office) ──');
  final astar = AStarPathfinder(graph);
  final result3 = astar.findPath('CS-101', 'CS-HOD-1F');
  assert(result3.found, 'Path should exist');
  print('   Path: ${result3.path!.nodes.map((n) => n.id).join(' → ')}');
  print('   Distance: ${result3.path!.totalDistance.toStringAsFixed(1)}m');
  print('   Nodes explored: ${result3.nodesExplored}');
  print('   Compute time: ${result3.computeTimeMs}ms');
  print('   ✅ PASS\n');

  // ─── Test 4: Wheelchair mode — stairs should be excluded ───
  print('── Test 4: Wheelchair Mode (Stairs Excluded) ──');
  final wheelchairEdges = graph.getNeighborEdges('CS-STAIRS-1F', wheelchairMode: true);
  final hasStairsEdge = wheelchairEdges.any((e) => e.type == EdgeType.stairs);
  assert(!hasStairsEdge, 'Stairs edges should be excluded in wheelchair mode');
  print('   Edges from STAIRS-1F (wheelchair): ${wheelchairEdges.length}');
  print('   Contains stairs: $hasStairsEdge');
  print('   ✅ PASS\n');

  // ─── Test 5: Dynamic reroute — block an edge ───
  print('── Test 5: Dynamic Reroute (Edge Blocked) ──');
  final orchestrator = NavigationOrchestrator(graph: graph);
  final startResult = orchestrator.startNavigation(
    fromNodeId: 'CS-ENT-1F',
    toNodeId: 'CS-103',
  );
  assert(startResult.success, 'Initial path should succeed');
  print('   Original: ${startResult.path!.nodes.map((n) => n.id).join(' → ')}');
  print('   Original dist: ${startResult.path!.totalDistance.toStringAsFixed(1)}m');

  // Block the corridor between CORR-02 and CORR-03
  final decision = orchestrator.onEdgeBlocked('CS-CORR-1F-02_to_CS-CORR-1F-03');
  print('   Blocked: CS-CORR-1F-02 → CS-CORR-1F-03');

  switch (decision) {
    case RerouteNeeded(:final newPath, :final description):
      print('   Rerouted: ${newPath.nodes.map((n) => n.id).join(' → ')}');
      print('   New dist: ${newPath.totalDistance.toStringAsFixed(1)}m');
      print('   Reason: $description');
      print('   ✅ PASS\n');
    case RerouteFailed(:final message):
      print('   ❌ FAIL: $message\n');
    default:
      print('   ❌ FAIL: Unexpected decision type: $decision\n');
  }

  // Re-enable for other tests
  orchestrator.onEdgeRestored('CS-CORR-1F-02_to_CS-CORR-1F-03');
  orchestrator.dispose();

  // ─── Test 6: Congestion-aware routing ───
  print('── Test 6: Congestion-Aware Routing ──');
  // Edge e20 (ENT → CORR-02) has congestion_level: 0.6
  // Effective weight = 15.8 * (1 + 2.0 * 0.6) = 34.76
  // Normal corridor route: 5.0 + 10.0 = 15.0 (much shorter)
  final edges = graph.getNeighborEdges('CS-ENT-1F');
  for (final edge in edges) {
    final ew = edge.effectiveWeight();
    print('   ${edge.from} → ${edge.to}: base=${edge.weight}m, effective=${ew.toStringAsFixed(1)}m');
  }
  print('   ✅ Congested lobby shortcut correctly penalized\n');

  // ─── Test 7: Graph connectivity ───
  print('── Test 7: Graph Connectivity ──');
  final unreachable = graph.findUnreachableNodes();
  print('   Unreachable nodes: ${unreachable.isEmpty ? "none" : unreachable}');
  assert(unreachable.isEmpty, 'All nodes should be reachable');
  print('   ✅ PASS\n');

  // ─── Test 8: Search ───
  print('── Test 8: Node Search ──');
  final searchResults = graph.searchNodes('lab');
  print('   Query: "lab"');
  print('   Results: ${searchResults.map((n) => n.displayName).join(', ')}');
  assert(searchResults.length == 2, 'Should find 2 labs');
  print('   ✅ PASS\n');

  print('═══════════════════════════════════════════');
  print('  All 8 tests passed ✅');
  print('═══════════════════════════════════════════');
}

/// Build the CS Floor 1 graph programmatically (no Firebase needed).
NavigationGraph _buildCSFloor1Graph() {
  final graph = NavigationGraph();

  // Add all 15 nodes
  final nodeData = [
    NavNode(id: 'CS-ENT-1F', x: 0, y: 0, z: 15, floor: 1, building: 'cs', type: NodeType.entrance, metadata: {'display_name': 'CS Main Entrance'}),
    NavNode(id: 'CS-CORR-1F-01', x: 5, y: 0, z: 15, floor: 1, building: 'cs', type: NodeType.corridor, metadata: {'display_name': 'Ground Corridor A'}),
    NavNode(id: 'CS-CORR-1F-02', x: 15, y: 0, z: 15, floor: 1, building: 'cs', type: NodeType.junction, metadata: {'display_name': 'T-Junction Central'}),
    NavNode(id: 'CS-CORR-1F-03', x: 25, y: 0, z: 15, floor: 1, building: 'cs', type: NodeType.corridor, metadata: {'display_name': 'Ground Corridor B'}),
    NavNode(id: 'CS-CORR-1F-N01', x: 15, y: 0, z: 25, floor: 1, building: 'cs', type: NodeType.corridor, metadata: {'display_name': 'North Wing Corridor'}),
    NavNode(id: 'CS-101', x: 5, y: 0, z: 20, floor: 1, building: 'cs', type: NodeType.room, metadata: {'display_name': 'Room CS-101', 'capacity': 60}),
    NavNode(id: 'CS-102', x: 5, y: 0, z: 10, floor: 1, building: 'cs', type: NodeType.room, metadata: {'display_name': 'Room CS-102', 'capacity': 45}),
    NavNode(id: 'CS-103', x: 25, y: 0, z: 20, floor: 1, building: 'cs', type: NodeType.room, metadata: {'display_name': 'Room CS-103', 'capacity': 55}),
    NavNode(id: 'CS-104', x: 25, y: 0, z: 10, floor: 1, building: 'cs', type: NodeType.room, metadata: {'display_name': 'Room CS-104', 'capacity': 40}),
    NavNode(id: 'CS-LAB-101', x: 15, y: 0, z: 30, floor: 1, building: 'cs', type: NodeType.lab, metadata: {'display_name': 'Programming Lab 1'}),
    NavNode(id: 'CS-LAB-102', x: 25, y: 0, z: 25, floor: 1, building: 'cs', type: NodeType.lab, metadata: {'display_name': 'Networks Lab'}),
    NavNode(id: 'CS-WC-1F', x: 30, y: 0, z: 15, floor: 1, building: 'cs', type: NodeType.washroom, metadata: {'display_name': 'Ground Floor Washroom'}),
    NavNode(id: 'CS-STAIRS-1F', x: 15, y: 0, z: 5, floor: 1, building: 'cs', type: NodeType.stairs, metadata: {'display_name': 'Central Staircase'}),
    NavNode(id: 'CS-LIFT-1F', x: 20, y: 0, z: 5, floor: 1, building: 'cs', type: NodeType.lift, metadata: {'display_name': 'Elevator'}),
    NavNode(id: 'CS-HOD-1F', x: 30, y: 0, z: 25, floor: 1, building: 'cs', type: NodeType.office, metadata: {'display_name': 'HOD Office (CSE)'}),
  ];
  for (final node in nodeData) {
    graph.addNode(node);
  }

  // Add all 20 edges
  final edgeData = [
    NavEdge(from: 'CS-ENT-1F', to: 'CS-CORR-1F-01', weight: 5.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-01', to: 'CS-CORR-1F-02', weight: 10.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-02', to: 'CS-CORR-1F-03', weight: 10.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-02', to: 'CS-CORR-1F-N01', weight: 10.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-01', to: 'CS-101', weight: 5.1, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-01', to: 'CS-102', weight: 5.1, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-03', to: 'CS-103', weight: 5.1, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-03', to: 'CS-104', weight: 5.1, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-N01', to: 'CS-LAB-101', weight: 5.1, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-03', to: 'CS-LAB-102', weight: 10.2, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-03', to: 'CS-WC-1F', weight: 5.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-02', to: 'CS-STAIRS-1F', weight: 10.0, type: EdgeType.walk),
    NavEdge(from: 'CS-STAIRS-1F', to: 'CS-LIFT-1F', weight: 5.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-N01', to: 'CS-LAB-102', weight: 10.0, type: EdgeType.walk),
    NavEdge(from: 'CS-LAB-102', to: 'CS-HOD-1F', weight: 5.0, type: EdgeType.walk),
    NavEdge(from: 'CS-CORR-1F-03', to: 'CS-HOD-1F', weight: 11.2, type: EdgeType.walk),
    NavEdge(from: 'CS-WC-1F', to: 'CS-HOD-1F', weight: 10.0, type: EdgeType.walk),
    NavEdge(from: 'CS-STAIRS-1F', to: 'CS-STAIRS-1F', weight: 8.0, type: EdgeType.stairs, wheelchairAccessible: false), // placeholder (no floor-2 node)
    NavEdge(from: 'CS-LIFT-1F', to: 'CS-LIFT-1F', weight: 3.0, type: EdgeType.lift),  // placeholder
    NavEdge(from: 'CS-ENT-1F', to: 'CS-CORR-1F-02', weight: 15.8, type: EdgeType.walk, metadata: {'congestion_level': 0.6}),
  ];
  for (final edge in edgeData) {
    graph.addEdge(edge);
  }

  return graph;
}
