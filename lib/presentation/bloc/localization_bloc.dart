/// LocalizationBloc — owns user position tracking and confidence.

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/navigation/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EVENTS
// ─────────────────────────────────────────────────────────────────────────────

sealed class LocalizationEvent {}

class QRCodeScanned extends LocalizationEvent {
  final String anchorId;
  final String buildingId;
  QRCodeScanned({required this.anchorId, required this.buildingId});
}

class VIOPositionUpdated extends LocalizationEvent {
  final double arX, arY, arZ;
  VIOPositionUpdated({required this.arX, required this.arY, required this.arZ});
}

class ManualPositionSet extends LocalizationEvent {
  final String nodeId;
  final String buildingId;
  ManualPositionSet({required this.nodeId, required this.buildingId});
}

class BuildingSelected extends LocalizationEvent {
  final String buildingId;
  BuildingSelected(this.buildingId);
}

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

sealed class LocalizationState {}

class LocalizationUninitialized extends LocalizationState {}

class LocalizationActive extends LocalizationState {
  final UserPosition position;

  LocalizationActive(this.position);

  /// Confidence band for UI display.
  String get confidenceBand {
    if (position.confidence >= 0.7) return 'good';
    if (position.confidence >= 0.5) return 'fair';
    if (position.confidence >= 0.3) return 'poor';
    return 'lost';
  }

  bool get needsRecalibration => position.confidence < 0.3;
}

class LocalizationLost extends LocalizationState {
  final String message;
  LocalizationLost(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOC
// ─────────────────────────────────────────────────────────────────────────────

class LocalizationBloc extends Bloc<LocalizationEvent, LocalizationState> {
  String? _currentBuildingId;
  String? _currentNodeId;
  double _confidence = 0.0;
  int _currentFloor = 1;

  /// Confidence decay factor per VIO tick.
  static const double _decayFactor = 0.9995;

  LocalizationBloc() : super(LocalizationUninitialized()) {
    on<QRCodeScanned>(_onQRScanned);
    on<VIOPositionUpdated>(_onVIOUpdate);
    on<ManualPositionSet>(_onManualSet);
    on<BuildingSelected>(_onBuildingSelected);
  }

  String? get currentBuilding => _currentBuildingId;
  String? get currentNodeId => _currentNodeId;
  int get currentFloor => _currentFloor;

  void _onQRScanned(
    QRCodeScanned event,
    Emitter<LocalizationState> emit,
  ) {
    _currentBuildingId = event.buildingId;
    _confidence = 1.0; // Ground truth

    emit(LocalizationActive(UserPosition(
      position: const Position3D(x: 0, y: 0, z: 0), // Will be resolved by graph lookup
      confidence: 1.0,
      nearestNodeId: null,
      floor: _currentFloor,
      building: event.buildingId,
      timestamp: DateTime.now(),
      source: PositionSource.qrScan,
    )));
  }

  void _onVIOUpdate(
    VIOPositionUpdated event,
    Emitter<LocalizationState> emit,
  ) {
    if (_currentBuildingId == null) return;

    // Decay confidence
    _confidence *= _decayFactor;

    if (_confidence < 0.1) {
      emit(LocalizationLost('Position confidence too low. Scan a QR code.'));
      return;
    }

    emit(LocalizationActive(UserPosition(
      position: Position3D(x: event.arX, y: event.arY, z: event.arZ),
      confidence: _confidence,
      nearestNodeId: _currentNodeId,
      floor: _currentFloor,
      building: _currentBuildingId!,
      timestamp: DateTime.now(),
      source: _confidence > 0.9 ? PositionSource.hybrid : PositionSource.vio,
    )));
  }

  void _onManualSet(
    ManualPositionSet event,
    Emitter<LocalizationState> emit,
  ) {
    _currentBuildingId = event.buildingId;
    _currentNodeId = event.nodeId;
    _confidence = 0.8;

    emit(LocalizationActive(UserPosition(
      position: const Position3D(x: 0, y: 0, z: 0),
      confidence: 0.8,
      nearestNodeId: event.nodeId,
      floor: _currentFloor,
      building: event.buildingId,
      timestamp: DateTime.now(),
      source: PositionSource.manual,
    )));
  }

  void _onBuildingSelected(
    BuildingSelected event,
    Emitter<LocalizationState> emit,
  ) {
    _currentBuildingId = event.buildingId;
    _confidence = 0;
    emit(LocalizationUninitialized());
  }
}
