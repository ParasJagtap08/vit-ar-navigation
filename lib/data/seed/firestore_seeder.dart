/// Firestore seeder — populates the CS Building Floor 1 dataset.
///
/// Run this script once to seed your Firebase project with the sample
/// navigation graph. After seeding, the app can fetch and navigate.
///
/// Usage:
///   1. Connect your Firebase project (firebase_options.dart)
///   2. Run: flutter run -t lib/data/seed/firestore_seeder.dart
///   3. Check Firestore console to verify data

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  await Firebase.initializeApp();
  final db = FirebaseFirestore.instance;

  print('🏗️  Seeding Firestore with CS Building Floor 1 dataset...\n');

  // ─────────────────────────────────────────
  // 1. Building Document
  // ─────────────────────────────────────────
  await db.collection('buildings').doc('cs').set({
    'name': 'Computer Science Building',
    'code': 'CS',
    'floors': 4,
    'graph_version': 1,
    'campus_offset': {'x': 100.0, 'y': 0.0, 'z': 50.0},
    'metadata': {
      'department': 'CSE',
      'built_year': 2012,
      'total_rooms': 40,
      'total_labs': 16,
    },
  });
  print('✅ Building "cs" created');

  // ─────────────────────────────────────────
  // 2. Nodes (15 nodes)
  // ─────────────────────────────────────────
  final nodes = <String, Map<String, dynamic>>{
    'CS-ENT-1F': {
      'x': 0.0, 'y': 0.0, 'z': 15.0,
      'floor': 1, 'building': 'cs',
      'type': 'entrance',
      'display_name': 'CS Main Entrance',
      'metadata': {'direction': 'south'},
    },
    'CS-CORR-1F-01': {
      'x': 5.0, 'y': 0.0, 'z': 15.0,
      'floor': 1, 'building': 'cs',
      'type': 'corridor',
      'display_name': 'Ground Corridor A',
      'metadata': {'width_meters': 3.0},
    },
    'CS-CORR-1F-02': {
      'x': 15.0, 'y': 0.0, 'z': 15.0,
      'floor': 1, 'building': 'cs',
      'type': 'junction',
      'display_name': 'T-Junction Central',
      'metadata': {'width_meters': 3.5},
    },
    'CS-CORR-1F-03': {
      'x': 25.0, 'y': 0.0, 'z': 15.0,
      'floor': 1, 'building': 'cs',
      'type': 'corridor',
      'display_name': 'Ground Corridor B',
      'metadata': {'width_meters': 3.0},
    },
    'CS-CORR-1F-N01': {
      'x': 15.0, 'y': 0.0, 'z': 25.0,
      'floor': 1, 'building': 'cs',
      'type': 'corridor',
      'display_name': 'North Wing Corridor',
      'metadata': {'width_meters': 2.5},
    },
    'CS-101': {
      'x': 5.0, 'y': 0.0, 'z': 20.0,
      'floor': 1, 'building': 'cs',
      'type': 'room',
      'display_name': 'Room CS-101',
      'metadata': {'capacity': 60, 'department': 'CSE', 'has_projector': true},
    },
    'CS-102': {
      'x': 5.0, 'y': 0.0, 'z': 10.0,
      'floor': 1, 'building': 'cs',
      'type': 'room',
      'display_name': 'Room CS-102',
      'metadata': {'capacity': 45, 'department': 'CSE', 'has_projector': true},
    },
    'CS-103': {
      'x': 25.0, 'y': 0.0, 'z': 20.0,
      'floor': 1, 'building': 'cs',
      'type': 'room',
      'display_name': 'Room CS-103',
      'metadata': {'capacity': 55, 'department': 'CSE'},
    },
    'CS-104': {
      'x': 25.0, 'y': 0.0, 'z': 10.0,
      'floor': 1, 'building': 'cs',
      'type': 'room',
      'display_name': 'Room CS-104',
      'metadata': {'capacity': 40, 'department': 'CSE'},
    },
    'CS-LAB-101': {
      'x': 15.0, 'y': 0.0, 'z': 30.0,
      'floor': 1, 'building': 'cs',
      'type': 'lab',
      'display_name': 'Programming Lab 1',
      'metadata': {'capacity': 35, 'systems': 30, 'department': 'CSE'},
    },
    'CS-LAB-102': {
      'x': 25.0, 'y': 0.0, 'z': 25.0,
      'floor': 1, 'building': 'cs',
      'type': 'lab',
      'display_name': 'Networks Lab',
      'metadata': {'capacity': 30, 'systems': 25, 'department': 'CSE'},
    },
    'CS-WC-1F': {
      'x': 30.0, 'y': 0.0, 'z': 15.0,
      'floor': 1, 'building': 'cs',
      'type': 'washroom',
      'display_name': 'Ground Floor Washroom',
      'metadata': {'gender': 'unisex'},
    },
    'CS-STAIRS-1F': {
      'x': 15.0, 'y': 0.0, 'z': 5.0,
      'floor': 1, 'building': 'cs',
      'type': 'stairs',
      'display_name': 'Central Staircase (Floor 1)',
      'metadata': {'connects_floors': [1, 2, 3, 4]},
    },
    'CS-LIFT-1F': {
      'x': 20.0, 'y': 0.0, 'z': 5.0,
      'floor': 1, 'building': 'cs',
      'type': 'lift',
      'display_name': 'Elevator (Floor 1)',
      'metadata': {'connects_floors': [1, 2, 3, 4], 'wheelchair_accessible': true},
    },
    'CS-HOD-1F': {
      'x': 30.0, 'y': 0.0, 'z': 25.0,
      'floor': 1, 'building': 'cs',
      'type': 'office',
      'display_name': 'HOD Office (CSE)',
      'metadata': {'occupant': 'Dr. Sharma', 'department': 'CSE'},
    },
  };

  final nodesRef = db.collection('buildings').doc('cs').collection('nodes');
  for (final entry in nodes.entries) {
    await nodesRef.doc(entry.key).set(entry.value);
  }
  print('✅ ${nodes.length} nodes created');

  // ─────────────────────────────────────────
  // 3. Edges (20 edges)
  // ─────────────────────────────────────────
  final edges = <String, Map<String, dynamic>>{
    'e01': {
      'from': 'CS-ENT-1F', 'to': 'CS-CORR-1F-01',
      'weight': 5.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e02': {
      'from': 'CS-CORR-1F-01', 'to': 'CS-CORR-1F-02',
      'weight': 10.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e03': {
      'from': 'CS-CORR-1F-02', 'to': 'CS-CORR-1F-03',
      'weight': 10.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e04': {
      'from': 'CS-CORR-1F-02', 'to': 'CS-CORR-1F-N01',
      'weight': 10.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e05': {
      'from': 'CS-CORR-1F-01', 'to': 'CS-101',
      'weight': 5.1, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e06': {
      'from': 'CS-CORR-1F-01', 'to': 'CS-102',
      'weight': 5.1, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e07': {
      'from': 'CS-CORR-1F-03', 'to': 'CS-103',
      'weight': 5.1, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e08': {
      'from': 'CS-CORR-1F-03', 'to': 'CS-104',
      'weight': 5.1, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e09': {
      'from': 'CS-CORR-1F-N01', 'to': 'CS-LAB-101',
      'weight': 5.1, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e10': {
      'from': 'CS-CORR-1F-03', 'to': 'CS-LAB-102',
      'weight': 10.2, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e11': {
      'from': 'CS-CORR-1F-03', 'to': 'CS-WC-1F',
      'weight': 5.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e12': {
      'from': 'CS-CORR-1F-02', 'to': 'CS-STAIRS-1F',
      'weight': 10.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e13': {
      'from': 'CS-STAIRS-1F', 'to': 'CS-LIFT-1F',
      'weight': 5.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e14': {
      'from': 'CS-CORR-1F-N01', 'to': 'CS-LAB-102',
      'weight': 10.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e15': {
      'from': 'CS-LAB-102', 'to': 'CS-HOD-1F',
      'weight': 5.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e16': {
      'from': 'CS-CORR-1F-03', 'to': 'CS-HOD-1F',
      'weight': 11.2, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e17': {
      'from': 'CS-WC-1F', 'to': 'CS-HOD-1F',
      'weight': 10.0, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
    },
    'e18': {
      'from': 'CS-STAIRS-1F', 'to': 'CS-STAIRS-2F',
      'weight': 8.0, 'type': 'stairs',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': false,
      'metadata': {'floor_transition': true, 'from_floor': 1, 'to_floor': 2},
    },
    'e19': {
      'from': 'CS-LIFT-1F', 'to': 'CS-LIFT-2F',
      'weight': 3.0, 'type': 'lift',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
      'metadata': {'floor_transition': true, 'from_floor': 1, 'to_floor': 2},
    },
    'e20': {
      'from': 'CS-ENT-1F', 'to': 'CS-CORR-1F-02',
      'weight': 15.8, 'type': 'walk',
      'bidirectional': true, 'status': 'active',
      'wheelchair_accessible': true,
      'metadata': {'congestion_level': 0.6, 'notes': 'Lobby shortcut, often crowded'},
    },
  };

  final edgesRef = db.collection('buildings').doc('cs').collection('edges');
  for (final entry in edges.entries) {
    await edgesRef.doc(entry.key).set(entry.value);
  }
  print('✅ ${edges.length} edges created');

  // ─────────────────────────────────────────
  // 4. QR Anchors (3 anchors)
  // ─────────────────────────────────────────
  final qrAnchors = <String, Map<String, dynamic>>{
    'CS-QR-001': {
      'mapped_node': 'CS-ENT-1F',
      'building': 'cs',
      'floor': 1,
      'offset': {'x': 0.0, 'y': 1.5, 'z': 0.0},
      'orientation': {'yaw': 0.0},
      'metadata': {
        'location_description': 'Left wall next to entrance doors',
        'qr_size_cm': 20,
      },
    },
    'CS-QR-002': {
      'mapped_node': 'CS-CORR-1F-02',
      'building': 'cs',
      'floor': 1,
      'offset': {'x': 0.0, 'y': 1.5, 'z': 0.0},
      'orientation': {'yaw': 90.0},
      'metadata': {
        'location_description': 'North wall at T-junction',
        'qr_size_cm': 20,
      },
    },
    'CS-QR-003': {
      'mapped_node': 'CS-CORR-1F-03',
      'building': 'cs',
      'floor': 1,
      'offset': {'x': 0.0, 'y': 1.5, 'z': 0.0},
      'orientation': {'yaw': 180.0},
      'metadata': {
        'location_description': 'Right wall near Room CS-103',
        'qr_size_cm': 20,
      },
    },
  };

  final qrRef = db.collection('buildings').doc('cs').collection('qr_anchors');
  for (final entry in qrAnchors.entries) {
    await qrRef.doc(entry.key).set(entry.value);
  }
  print('✅ ${qrAnchors.length} QR anchors created');

  // ─────────────────────────────────────────
  // 5. Initialize realtime_status (empty)
  // ─────────────────────────────────────────
  await db.collection('realtime_status').doc('cs').set({
    'building': 'cs',
    'last_updated': FieldValue.serverTimestamp(),
  });
  print('✅ realtime_status/cs initialized');

  print('\n🎉 Seeding complete!');
  print('   15 nodes, 20 edges, 3 QR anchors');
  print('   Building: CS (Computer Science)');
  print('   Floor: 1 (Ground Floor)');
}
