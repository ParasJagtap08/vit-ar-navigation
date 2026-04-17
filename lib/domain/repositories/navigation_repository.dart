/// Abstract contracts for the navigation data layer.
/// These interfaces define WHAT data operations the app needs,
/// not HOW they are implemented (Firebase, Hive, mock, etc.).

import '../../core/navigation/models.dart';
import '../../core/navigation/graph.dart';

/// Contract for accessing building & navigation graph data.
abstract class NavigationRepository {
  /// Fetch the full navigation graph for a building.
  /// Returns cached data if fresh, otherwise fetches from server.
  Future<NavigationGraph> getBuildingGraph(String buildingId);

  /// Fetch metadata for all buildings on campus.
  Future<List<BuildingInfo>> getAllBuildings();

  /// Search for destination nodes across all buildings.
  Future<List<NavNode>> searchDestinations(String query);

  /// Fetch QR anchors for a specific building.
  Future<List<QRAnchor>> getQRAnchors(String buildingId);

  /// Get real-time stream of blocked edges for a building.
  Stream<EdgeStatusUpdate> watchBlockedEdges(String buildingId);

  /// Report a blocked path (user feedback).
  Future<void> reportBlockedPath(String edgeId, String reason);

  /// Invalidate cached graph for a building.
  Future<void> invalidateCache(String buildingId);
}

/// Building metadata (not a graph node — campus-level info).
class BuildingInfo {
  final String id;
  final String name;
  final String code;
  final int floors;
  final double campusX;
  final double campusY;
  final double campusZ;
  final Map<String, dynamic> metadata;

  const BuildingInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.floors,
    this.campusX = 0,
    this.campusY = 0,
    this.campusZ = 0,
    this.metadata = const {},
  });

  factory BuildingInfo.fromJson(Map<String, dynamic> json) {
    return BuildingInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      floors: json['floors'] as int,
      campusX: (json['campus_offset']?['x'] as num?)?.toDouble() ?? 0,
      campusY: (json['campus_offset']?['y'] as num?)?.toDouble() ?? 0,
      campusZ: (json['campus_offset']?['z'] as num?)?.toDouble() ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// Real-time edge status update from Firebase.
class EdgeStatusUpdate {
  final String edgeId;
  final EdgeStatus newStatus;
  final String? reason;
  final DateTime timestamp;

  const EdgeStatusUpdate({
    required this.edgeId,
    required this.newStatus,
    this.reason,
    required this.timestamp,
  });
}
