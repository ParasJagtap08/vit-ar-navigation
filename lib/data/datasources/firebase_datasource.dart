/// Firebase Firestore data source — handles all Firebase communication.
///
/// Firestore Schema:
///
/// buildings/{buildingId}
///   ├── name: "Computer Science Building"
///   ├── code: "CS"
///   ├── floors: 4
///   ├── campus_offset: {x: 100, y: 0, z: 50}
///   ├── metadata: {...}
///   └── graph_version: 3            ← incremented on graph changes
///
/// buildings/{buildingId}/nodes/{nodeId}
///   ├── x, y, z: float
///   ├── floor: int
///   ├── building: string
///   ├── type: string
///   └── metadata: {...}
///
/// buildings/{buildingId}/edges/{edgeId}
///   ├── from_node, to_node: string
///   ├── weight: float
///   ├── type: string
///   ├── bidirectional: bool
///   ├── status: string
///   └── metadata: {...}
///
/// buildings/{buildingId}/qr_anchors/{anchorId}
///   ├── mapped_node: string
///   ├── offset: {x, y, z}
///   ├── orientation: {yaw: float}
///   └── metadata: {...}
///
/// realtime_status/{buildingId}/blocked_edges/{edgeId}
///   ├── status: "blocked" | "maintenance"
///   ├── reason: string
///   ├── reported_by: string
///   ├── reported_at: timestamp
///   └── expires_at: timestamp (optional)

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/navigation/models.dart';
import '../../core/navigation/graph.dart';
import '../../domain/repositories/navigation_repository.dart';

class FirebaseNavigationDatasource {
  final FirebaseFirestore _firestore;

  FirebaseNavigationDatasource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────
  // Building Metadata
  // ─────────────────────────────────────────────────────

  /// Fetch all buildings on campus.
  Future<List<BuildingInfo>> getAllBuildings() async {
    final snapshot = await _firestore
        .collection('buildings')
        .get(const GetOptions(source: Source.serverAndCache));

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return BuildingInfo.fromJson(data);
    }).toList();
  }

  /// Fetch a single building's metadata.
  Future<BuildingInfo?> getBuilding(String buildingId) async {
    final doc = await _firestore.collection('buildings').doc(buildingId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return BuildingInfo.fromJson(data);
  }

  /// Get the graph version for a building (for cache invalidation).
  Future<int> getGraphVersion(String buildingId) async {
    final doc = await _firestore.collection('buildings').doc(buildingId).get();
    return (doc.data()?['graph_version'] as int?) ?? 0;
  }

  // ─────────────────────────────────────────────────────
  // Navigation Graph — Full Fetch
  // ─────────────────────────────────────────────────────

  /// Fetch the complete navigation graph for a building.
  /// This fetches ALL nodes and edges in two parallel queries.
  Future<NavigationGraph> fetchBuildingGraph(String buildingId) async {
    // Parallel fetch nodes and edges
    final results = await Future.wait([
      _firestore
          .collection('buildings')
          .doc(buildingId)
          .collection('nodes')
          .get(),
      _firestore
          .collection('buildings')
          .doc(buildingId)
          .collection('edges')
          .get(),
    ]);

    final nodeSnapshot = results[0];
    final edgeSnapshot = results[1];

    // Parse nodes
    final nodes = nodeSnapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return NavNode.fromJson(data);
    }).toList();

    // Parse edges
    final edges = edgeSnapshot.docs.map((doc) {
      return NavEdge.fromJson(doc.data());
    }).toList();

    return NavigationGraph.fromData(nodes: nodes, edges: edges);
  }

  // ─────────────────────────────────────────────────────
  // QR Anchors
  // ─────────────────────────────────────────────────────

  /// Fetch all QR anchors for a building.
  Future<List<QRAnchor>> getQRAnchors(String buildingId) async {
    final snapshot = await _firestore
        .collection('buildings')
        .doc(buildingId)
        .collection('qr_anchors')
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return QRAnchor.fromJson(data);
    }).toList();
  }

  /// Fetch a single QR anchor by its ID.
  Future<QRAnchor?> getQRAnchor(String buildingId, String anchorId) async {
    final doc = await _firestore
        .collection('buildings')
        .doc(buildingId)
        .collection('qr_anchors')
        .doc(anchorId)
        .get();

    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return QRAnchor.fromJson(data);
  }

  // ─────────────────────────────────────────────────────
  // Search
  // ─────────────────────────────────────────────────────

  /// Search for destination nodes across all buildings.
  ///
  /// Note: Firestore doesn't support full-text search natively.
  /// For production, use Algolia or a Cloud Function with a search index.
  /// This implementation fetches all destination nodes and filters client-side.
  Future<List<NavNode>> searchDestinations(String query) async {
    final buildings = await getAllBuildings();
    final allNodes = <NavNode>[];

    for (final building in buildings) {
      final snapshot = await _firestore
          .collection('buildings')
          .doc(building.id)
          .collection('nodes')
          .where('type', whereIn: ['room', 'lab', 'office', 'washroom', 'entrance'])
          .get();

      allNodes.addAll(snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return NavNode.fromJson(data);
      }));
    }

    // Client-side filter
    final lowerQuery = query.toLowerCase();
    return allNodes.where((node) {
      return node.id.toLowerCase().contains(lowerQuery) ||
          node.displayName.toLowerCase().contains(lowerQuery) ||
          (node.metadata['department'] as String?)
                  ?.toLowerCase()
                  .contains(lowerQuery) ==
              true;
    }).toList();
  }

  // ─────────────────────────────────────────────────────
  // Real-Time Blocked Edges
  // ─────────────────────────────────────────────────────

  /// Stream of real-time blocked edge updates.
  /// Listens to the realtime_status collection for a building.
  Stream<EdgeStatusUpdate> watchBlockedEdges(String buildingId) {
    return _firestore
        .collection('realtime_status')
        .doc(buildingId)
        .collection('blocked_edges')
        .snapshots()
        .expand((snapshot) {
      return snapshot.docChanges.map((change) {
        final data = change.doc.data() ?? {};
        final edgeId = change.doc.id;

        EdgeStatus status;
        if (change.type == DocumentChangeType.removed) {
          status = EdgeStatus.active; // Edge unblocked
        } else {
          final statusStr = data['status'] as String? ?? 'blocked';
          status = statusStr == 'maintenance'
              ? EdgeStatus.maintenance
              : EdgeStatus.blocked;
        }

        return EdgeStatusUpdate(
          edgeId: edgeId,
          newStatus: status,
          reason: data['reason'] as String?,
          timestamp: (data['reported_at'] as Timestamp?)?.toDate() ??
              DateTime.now(),
        );
      });
    });
  }

  /// Report a blocked path (user feedback).
  Future<void> reportBlockedPath(
    String buildingId,
    String edgeId,
    String reason,
  ) async {
    await _firestore
        .collection('realtime_status')
        .doc(buildingId)
        .collection('blocked_edges')
        .doc(edgeId)
        .set({
      'status': 'blocked',
      'reason': reason,
      'reported_by': 'user',
      'reported_at': FieldValue.serverTimestamp(),
    });
  }
}
