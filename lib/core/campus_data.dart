import 'models.dart';
import 'graph.dart';

/// Building metadata used by the UI
class BuildingInfo {
  final String id;
  final String name;
  final String code;
  final int floors;
  final String department;
  final int totalRooms;
  final int totalLabs;

  const BuildingInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.floors,
    required this.department,
    required this.totalRooms,
    required this.totalLabs,
  });
}

/// All campus buildings
const List<BuildingInfo> campusBuildings = [
  BuildingInfo(
    id: 'cs',
    name: 'Computer Science',
    code: 'CS',
    floors: 4,
    department: 'Computer Science & Engineering',
    totalRooms: 40,
    totalLabs: 16,
  ),
  BuildingInfo(
    id: 'aiml',
    name: 'AI & ML',
    code: 'AIML',
    floors: 4,
    department: 'Artificial Intelligence & Machine Learning',
    totalRooms: 40,
    totalLabs: 16,
  ),
  BuildingInfo(
    id: 'aids',
    name: 'AI & Data Science',
    code: 'AIDS',
    floors: 4,
    department: 'AI & Data Science',
    totalRooms: 40,
    totalLabs: 16,
  ),
  BuildingInfo(
    id: 'ai',
    name: 'Artificial Intelligence',
    code: 'AI',
    floors: 4,
    department: 'Artificial Intelligence',
    totalRooms: 40,
    totalLabs: 16,
  ),
];

/// Generate the full campus navigation graph.
///
/// Each building has 4 floors with a realistic layout:
/// - Main corridor running east (left-to-right)
/// - Rooms on both sides of the corridor
/// - Labs at the east end
/// - Stairs and lift in the center
/// - Washroom near the stairs
/// - Entrance on ground floor at the west end
/// - HOD office on 3rd floor
///
/// Coordinate system: X=East, Y=Up, Z=North. Origin at SW corner.
/// Each floor is at Y = (floor - 1) * 4.0 meters.
NavigationGraph buildCampusGraph() {
  final graph = NavigationGraph();

  // Building offsets on campus (spread buildings apart)
  const buildingOffsets = {
    'cs': Position3D(x: 0, y: 0, z: 0),
    'aiml': Position3D(x: 80, y: 0, z: 0),
    'aids': Position3D(x: 0, y: 0, z: 80),
    'ai': Position3D(x: 80, y: 0, z: 80),
  };

  final labNames = {
    'cs': ['Programming Lab', 'Network Lab', 'OS Lab', 'Database Lab'],
    'aiml': ['ML Lab', 'Deep Learning Lab', 'NLP Lab', 'Computer Vision Lab'],
    'aids': ['Data Science Lab', 'Big Data Lab', 'Analytics Lab', 'Statistics Lab'],
    'ai': ['AI Research Lab', 'Robotics Lab', 'Neural Network Lab', 'Cognitive Lab'],
  };

  for (final building in campusBuildings) {
    final bid = building.id;
    final code = building.code;
    final offset = buildingOffsets[bid]!;

    for (int floor = 1; floor <= building.floors; floor++) {
      final floorY = (floor - 1) * 4.0 + offset.y;
      final fStr = '${floor}F';

      // ─── Corridor nodes (main hallway running east) ───
      // 6 corridor nodes spaced 8m apart along X axis
      for (int c = 0; c < 6; c++) {
        final corrX = 4.0 + c * 8.0 + offset.x;
        final corrZ = 15.0 + offset.z;
        graph.addNode(NavNode(
          id: '$code-CORR-$fStr-${(c + 1).toString().padLeft(2, '0')}',
          position: Position3D(x: corrX, y: floorY, z: corrZ),
          floor: floor,
          building: bid,
          type: c == 2 || c == 4 ? NodeType.junction : NodeType.corridor,
          displayName: 'Corridor ${floor}F-${c + 1}',
        ));
      }

      // Connect corridor nodes sequentially
      for (int c = 0; c < 5; c++) {
        final from = '$code-CORR-$fStr-${(c + 1).toString().padLeft(2, '0')}';
        final to = '$code-CORR-$fStr-${(c + 2).toString().padLeft(2, '0')}';
        graph.addEdge(NavEdge(
          fromNode: from,
          toNode: to,
          weight: 8.0,
          type: EdgeType.corridor,
        ));
      }

      // ─── Rooms (5 per side of corridor, 10 total per floor) ───
      for (int r = 0; r < 10; r++) {
        final roomNum = (floor - 1) * 10 + r + 1;
        final roomId = '$code-${roomNum.toString().padLeft(3, '0')}';
        final corrIdx = (r < 5) ? r : r - 5; // Which corridor node
        final corrX = 4.0 + corrIdx * 8.0 + offset.x;
        final side = r < 5 ? -1.0 : 1.0; // north or south side
        final roomZ = 15.0 + side * 5.0 + offset.z;

        graph.addNode(NavNode(
          id: roomId,
          position: Position3D(x: corrX + 2.0, y: floorY, z: roomZ),
          floor: floor,
          building: bid,
          type: NodeType.room,
          displayName: 'Room $code-$roomNum',
        ));

        // Connect room to corridor
        final corrNode = '$code-CORR-$fStr-${(corrIdx + 1).toString().padLeft(2, '0')}';
        graph.addEdge(NavEdge(
          fromNode: corrNode,
          toNode: roomId,
          weight: 5.5,
          type: EdgeType.door,
        ));
      }

      // ─── Labs (4 per floor, at the east end) ───
      for (int l = 0; l < 4; l++) {
        final labNum = (floor - 1) * 4 + l + 1;
        final labId = '$code-LAB-$fStr-${(l + 1).toString().padLeft(2, '0')}';
        final side = l < 2 ? -1.0 : 1.0;
        final labX = 36.0 + (l % 2) * 8.0 + offset.x;
        final labZ = 15.0 + side * 6.0 + offset.z;

        final names = labNames[bid]!;
        graph.addNode(NavNode(
          id: labId,
          position: Position3D(x: labX, y: floorY, z: labZ),
          floor: floor,
          building: bid,
          type: NodeType.lab,
          displayName: '${names[l]} (${floor}F)',
        ));

        // Connect lab to nearest corridor
        final corrIdx = l < 2 ? 4 : 5;
        final corrNode = '$code-CORR-$fStr-${(corrIdx + 1).toString().padLeft(2, '0')}';
        graph.addEdge(NavEdge(
          fromNode: corrNode,
          toNode: labId,
          weight: 7.0,
          type: EdgeType.door,
        ));
      }

      // ─── Washroom ───
      final wcId = '$code-WC-$fStr';
      graph.addNode(NavNode(
        id: wcId,
        position: Position3D(x: 20.0 + offset.x, y: floorY, z: 22.0 + offset.z),
        floor: floor,
        building: bid,
        type: NodeType.washroom,
        displayName: 'Washroom (${floor}F)',
      ));
      graph.addEdge(NavEdge(
        fromNode: '$code-CORR-$fStr-03',
        toNode: wcId,
        weight: 7.5,
        type: EdgeType.corridor,
      ));

      // ─── Stairs ───
      final stairsId = '$code-STAIRS-$fStr';
      graph.addNode(NavNode(
        id: stairsId,
        position: Position3D(x: 18.0 + offset.x, y: floorY, z: 8.0 + offset.z),
        floor: floor,
        building: bid,
        type: NodeType.stairs,
        displayName: 'Staircase (${floor}F)',
      ));
      graph.addEdge(NavEdge(
        fromNode: '$code-CORR-$fStr-03',
        toNode: stairsId,
        weight: 8.0,
        type: EdgeType.corridor,
      ));

      // ─── Lift ───
      final liftId = '$code-LIFT-$fStr';
      graph.addNode(NavNode(
        id: liftId,
        position: Position3D(x: 22.0 + offset.x, y: floorY, z: 8.0 + offset.z),
        floor: floor,
        building: bid,
        type: NodeType.lift,
        displayName: 'Elevator (${floor}F)',
      ));
      graph.addEdge(NavEdge(
        fromNode: '$code-CORR-$fStr-03',
        toNode: liftId,
        weight: 8.5,
        type: EdgeType.corridor,
      ));

      // ─── Entrance (ground floor only) ───
      if (floor == 1) {
        final entId = '$code-ENT-1F';
        graph.addNode(NavNode(
          id: entId,
          position: Position3D(x: 0.0 + offset.x, y: floorY, z: 15.0 + offset.z),
          floor: 1,
          building: bid,
          type: NodeType.entrance,
          displayName: '$code Main Entrance',
        ));
        graph.addEdge(NavEdge(
          fromNode: entId,
          toNode: '$code-CORR-1F-01',
          weight: 4.0,
          type: EdgeType.door,
        ));
      }

      // ─── HOD Office (3rd floor only) ───
      if (floor == 3) {
        final hodId = '$code-HOD';
        graph.addNode(NavNode(
          id: hodId,
          position: Position3D(x: 8.0 + offset.x, y: floorY, z: 22.0 + offset.z),
          floor: 3,
          building: bid,
          type: NodeType.office,
          displayName: '$code HOD Office',
        ));
        graph.addEdge(NavEdge(
          fromNode: '$code-CORR-3F-01',
          toNode: hodId,
          weight: 7.5,
          type: EdgeType.door,
        ));
      }
    }

    // ─── Cross-floor connections (stairs & lift) ───
    for (int floor = 1; floor < building.floors; floor++) {
      final fStrLo = '${floor}F';
      final fStrHi = '${floor + 1}F';

      // Stairs connect
      graph.addEdge(NavEdge(
        fromNode: '$code-STAIRS-$fStrLo',
        toNode: '$code-STAIRS-$fStrHi',
        weight: 6.0,
        type: EdgeType.stairs,
      ));

      // Lift connect
      graph.addEdge(NavEdge(
        fromNode: '$code-LIFT-$fStrLo',
        toNode: '$code-LIFT-$fStrHi',
        weight: 4.0,
        type: EdgeType.lift,
      ));
    }
  }

  // ─── Cross-Campus Connections (Outdoor) ───
  // Create edges between main entrances to allow cross-building routing
  graph.addEdge(NavEdge(
    fromNode: 'CS-ENT-1F',
    toNode: 'AIML-ENT-1F',
    weight: 80.0,
    type: EdgeType.outdoor,
  ));
  graph.addEdge(NavEdge(
    fromNode: 'CS-ENT-1F',
    toNode: 'AIDS-ENT-1F',
    weight: 80.0,
    type: EdgeType.outdoor,
  ));
  graph.addEdge(NavEdge(
    fromNode: 'AIML-ENT-1F',
    toNode: 'AI-ENT-1F',
    weight: 80.0,
    type: EdgeType.outdoor,
  ));
  graph.addEdge(NavEdge(
    fromNode: 'AIDS-ENT-1F',
    toNode: 'AI-ENT-1F',
    weight: 80.0,
    type: EdgeType.outdoor,
  ));

  return graph;
}
