/// NavigationBloc — owns the full navigation lifecycle.
///
/// State machine:
///   Idle → Loading → Active ↔ Rerouting → Arrived
///                  ↓
///                Error

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/navigation/models.dart';
import '../../core/navigation/graph.dart';
import '../../core/navigation/dynamic_reroute.dart';
import '../../domain/usecases/navigation_usecases.dart';
import '../../domain/repositories/navigation_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EVENTS
// ─────────────────────────────────────────────────────────────────────────────

sealed class NavigationEvent {}

/// User taps "Navigate" to a destination.
class StartNavigation extends NavigationEvent {
  final String fromNodeId;
  final String toNodeId;
  final String buildingId;
  final bool wheelchairMode;

  StartNavigation({
    required this.fromNodeId,
    required this.toNodeId,
    required this.buildingId,
    this.wheelchairMode = false,
  });
}

/// User taps "Stop Navigation".
class StopNavigation extends NavigationEvent {}

/// Real-time position update from localization engine.
class PositionUpdated extends NavigationEvent {
  final UserPosition position;
  PositionUpdated(this.position);
}

/// Firebase reports a blocked edge.
class EdgeBlocked extends NavigationEvent {
  final String edgeId;
  EdgeBlocked(this.edgeId);
}

/// Firebase reports an edge is restored.
class EdgeRestored extends NavigationEvent {
  final String edgeId;
  EdgeRestored(this.edgeId);
}

/// User requests manual reroute.
class RequestReroute extends NavigationEvent {}

/// User changes floor (stairs/lift event).
class FloorTransitionDetected extends NavigationEvent {
  final int newFloor;
  FloorTransitionDetected(this.newFloor);
}

/// Find nearest amenity (washroom, stairs, etc.).
class FindNearestAmenity extends NavigationEvent {
  final NodeType amenityType;
  FindNearestAmenity(this.amenityType);
}

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

sealed class NavigationState {}

class NavigationIdle extends NavigationState {}

class NavigationLoading extends NavigationState {
  final String destinationName;
  NavigationLoading(this.destinationName);
}

class NavigationActive extends NavigationState {
  final NavPath path;
  final NavigationGraph graph;
  final int currentWaypointIndex;
  final double remainingDistance;
  final double estimatedTimeSeconds;
  final String? currentInstruction;
  final double distanceToPath;

  NavigationActive({
    required this.path,
    required this.graph,
    this.currentWaypointIndex = 0,
    required this.remainingDistance,
    required this.estimatedTimeSeconds,
    this.currentInstruction,
    this.distanceToPath = 0,
  });

  NavigationActive copyWith({
    NavPath? path,
    int? currentWaypointIndex,
    double? remainingDistance,
    double? estimatedTimeSeconds,
    String? currentInstruction,
    double? distanceToPath,
  }) {
    return NavigationActive(
      path: path ?? this.path,
      graph: graph,
      currentWaypointIndex: currentWaypointIndex ?? this.currentWaypointIndex,
      remainingDistance: remainingDistance ?? this.remainingDistance,
      estimatedTimeSeconds: estimatedTimeSeconds ?? this.estimatedTimeSeconds,
      currentInstruction: currentInstruction ?? this.currentInstruction,
      distanceToPath: distanceToPath ?? this.distanceToPath,
    );
  }
}

class NavigationRerouting extends NavigationState {
  final NavPath oldPath;
  final String reason;
  NavigationRerouting({required this.oldPath, required this.reason});
}

class NavigationArrived extends NavigationState {
  final String destinationName;
  final double totalDistance;
  final double totalTimeSeconds;
  NavigationArrived({
    required this.destinationName,
    required this.totalDistance,
    required this.totalTimeSeconds,
  });
}

class NavigationError extends NavigationState {
  final String message;
  NavigationError(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOC
// ─────────────────────────────────────────────────────────────────────────────

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  final NavigateToDestinationUseCase _navigateUseCase;
  final FindNearestAmenityUseCase _amenityUseCase;
  final WatchBlockedEdgesUseCase _watchEdgesUseCase;

  NavigationOrchestrator? _orchestrator;
  StreamSubscription? _edgeSubscription;
  StreamSubscription? _rerouteSubscription;
  String? _currentBuildingId;
  DateTime? _navigationStartTime;

  NavigationBloc({
    required NavigateToDestinationUseCase navigateUseCase,
    required FindNearestAmenityUseCase amenityUseCase,
    required WatchBlockedEdgesUseCase watchEdgesUseCase,
  })  : _navigateUseCase = navigateUseCase,
        _amenityUseCase = amenityUseCase,
        _watchEdgesUseCase = watchEdgesUseCase,
        super(NavigationIdle()) {
    on<StartNavigation>(_onStartNavigation);
    on<StopNavigation>(_onStopNavigation);
    on<PositionUpdated>(_onPositionUpdated);
    on<EdgeBlocked>(_onEdgeBlocked);
    on<EdgeRestored>(_onEdgeRestored);
    on<RequestReroute>(_onRequestReroute);
    on<FloorTransitionDetected>(_onFloorTransition);
    on<FindNearestAmenity>(_onFindNearestAmenity);
  }

  // ─────────────────────────────────────────
  // Event Handlers
  // ─────────────────────────────────────────

  Future<void> _onStartNavigation(
    StartNavigation event,
    Emitter<NavigationState> emit,
  ) async {
    emit(NavigationLoading(event.toNodeId));

    try {
      final result = await _navigateUseCase.execute(
        fromNodeId: event.fromNodeId,
        toNodeId: event.toNodeId,
        buildingId: event.buildingId,
        wheelchairMode: event.wheelchairMode,
      );

      if (!result.isSuccess || result.path == null) {
        emit(NavigationError(result.errorMessage ?? 'Navigation failed'));
        return;
      }

      _currentBuildingId = event.buildingId;
      _navigationStartTime = DateTime.now();

      // Create orchestrator
      _orchestrator = NavigationOrchestrator(
        graph: result.graph!,
        config: RerouteConfig(wheelchairMode: event.wheelchairMode),
      );
      _orchestrator!.startNavigation(
        fromNodeId: event.fromNodeId,
        toNodeId: event.toNodeId,
      );

      // Start watching blocked edges
      _startEdgeWatcher(event.buildingId);

      // Listen to reroute stream
      _rerouteSubscription = _orchestrator!.rerouteStream.listen((decision) {
        if (decision is RerouteNeeded) {
          add(PositionUpdated(UserPosition(
            position: Position3D(x: 0, y: 0, z: 0),
            confidence: 0,
            floor: 0,
            building: '',
            timestamp: DateTime.now(),
            source: PositionSource.manual,
          )));
        }
      });

      emit(NavigationActive(
        path: result.path!,
        graph: result.graph!,
        remainingDistance: result.path!.totalDistance,
        estimatedTimeSeconds: result.path!.estimatedTimeSeconds,
        currentInstruction: 'Start walking toward ${result.path!.nodes[1].displayName}',
      ));
    } catch (e) {
      emit(NavigationError('Navigation failed: $e'));
    }
  }

  void _onStopNavigation(
    StopNavigation event,
    Emitter<NavigationState> emit,
  ) {
    _cleanup();
    emit(NavigationIdle());
  }

  void _onPositionUpdated(
    PositionUpdated event,
    Emitter<NavigationState> emit,
  ) {
    if (_orchestrator == null || state is! NavigationActive) return;
    final currentState = state as NavigationActive;

    final decision = _orchestrator!.onPositionUpdate(event.position.position);

    switch (decision) {
      case OnTrack(:final remainingDistance, :final currentSegmentIndex, :final distanceToPath):
        // Check if arrived
        if (remainingDistance < 2.0) {
          final elapsed = DateTime.now().difference(_navigationStartTime!);
          emit(NavigationArrived(
            destinationName: currentState.path.destination.displayName,
            totalDistance: currentState.path.totalDistance,
            totalTimeSeconds: elapsed.inSeconds.toDouble(),
          ));
          _cleanup();
          return;
        }
        emit(currentState.copyWith(
          currentWaypointIndex: currentSegmentIndex,
          remainingDistance: remainingDistance,
          estimatedTimeSeconds: remainingDistance / 1.2,
          distanceToPath: distanceToPath,
        ));

      case DriftWarning(:final distanceToPath, :final timeUntilReroute):
        emit(currentState.copyWith(
          distanceToPath: distanceToPath,
          currentInstruction: 'You\'re off path. Rerouting in ${timeUntilReroute.inSeconds}s...',
        ));

      case RerouteNeeded(:final newPath, :final description):
        emit(NavigationActive(
          path: newPath,
          graph: currentState.graph,
          remainingDistance: newPath.totalDistance,
          estimatedTimeSeconds: newPath.estimatedTimeSeconds,
          currentInstruction: description,
        ));

      case RerouteFailed(:final message):
        emit(NavigationError(message));
    }
  }

  void _onEdgeBlocked(EdgeBlocked event, Emitter<NavigationState> emit) {
    if (_orchestrator == null) return;
    final decision = _orchestrator!.onEdgeBlocked(event.edgeId);
    _handleRerouteDecision(decision, emit);
  }

  void _onEdgeRestored(EdgeRestored event, Emitter<NavigationState> emit) {
    _orchestrator?.onEdgeRestored(event.edgeId);
  }

  void _onRequestReroute(RequestReroute event, Emitter<NavigationState> emit) {
    if (_orchestrator == null || state is! NavigationActive) return;
    final currentState = state as NavigationActive;
    final decision = _orchestrator!.onManualReroute(
      currentState.path.nodes[currentState.currentWaypointIndex].position,
    );
    _handleRerouteDecision(decision, emit);
  }

  void _onFloorTransition(
    FloorTransitionDetected event,
    Emitter<NavigationState> emit,
  ) {
    if (_orchestrator == null || state is! NavigationActive) return;
    final currentState = state as NavigationActive;
    final decision = _orchestrator!.onFloorChanged(
      currentState.path.nodes[currentState.currentWaypointIndex].position,
      event.newFloor,
    );
    _handleRerouteDecision(decision, emit);
  }

  Future<void> _onFindNearestAmenity(
    FindNearestAmenity event,
    Emitter<NavigationState> emit,
  ) async {
    if (state is! NavigationActive || _currentBuildingId == null) return;
    final currentState = state as NavigationActive;
    final currentNodeId =
        currentState.path.nodes[currentState.currentWaypointIndex].id;

    final path = await _amenityUseCase.execute(
      fromNodeId: currentNodeId,
      buildingId: _currentBuildingId!,
      amenityType: event.amenityType,
    );

    if (path != null) {
      emit(NavigationActive(
        path: path,
        graph: currentState.graph,
        remainingDistance: path.totalDistance,
        estimatedTimeSeconds: path.estimatedTimeSeconds,
        currentInstruction: 'Nearest ${event.amenityType.name}: ${path.destination.displayName}',
      ));
    }
  }

  // ─────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────

  void _handleRerouteDecision(RerouteDecision decision, Emitter<NavigationState> emit) {
    if (state is! NavigationActive) return;
    final currentState = state as NavigationActive;

    switch (decision) {
      case RerouteNeeded(:final newPath, :final description):
        emit(NavigationActive(
          path: newPath,
          graph: currentState.graph,
          remainingDistance: newPath.totalDistance,
          estimatedTimeSeconds: newPath.estimatedTimeSeconds,
          currentInstruction: description,
        ));
      case RerouteFailed(:final message):
        emit(NavigationError(message));
      default:
        break;
    }
  }

  void _startEdgeWatcher(String buildingId) {
    _edgeSubscription?.cancel();
    _edgeSubscription = _watchEdgesUseCase.execute(buildingId).listen((update) {
      if (update.newStatus == EdgeStatus.active) {
        add(EdgeRestored(update.edgeId));
      } else {
        add(EdgeBlocked(update.edgeId));
      }
    });
  }

  void _cleanup() {
    _edgeSubscription?.cancel();
    _rerouteSubscription?.cancel();
    _orchestrator?.dispose();
    _orchestrator = null;
    _currentBuildingId = null;
    _navigationStartTime = null;
  }

  @override
  Future<void> close() {
    _cleanup();
    return super.close();
  }
}
