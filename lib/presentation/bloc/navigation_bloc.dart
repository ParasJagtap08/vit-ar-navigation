/// NavigationBloc — connects the NavigationController to the Flutter UI.
///
/// This BLoC translates user interactions (events) into navigation state
/// changes, using [NavigationController] for all pathfinding logic.
///
/// ```dart
/// BlocProvider(
///   create: (_) => NavigationBloc(controller: navigationController),
///   child: NavigationScreen(),
/// )
///
/// // Dispatch events:
/// bloc.add(SetStartNode('CS-CORR-1F-01'));
/// bloc.add(SetDestination('CS-103'));
/// bloc.add(UpdatePosition(Position3D(x: 10, y: 0, z: 15)));
///
/// // React to states:
/// BlocBuilder<NavigationBloc, NavigationBlocState>(
///   builder: (context, state) => switch (state) {
///     NavigationInitial()   => _buildIdle(),
///     NavigationLoading()   => _buildLoading(),
///     NavigationPathLoaded() => _buildPath(state.path),
///     NavigationError()     => _buildError(state.message),
///   },
/// )
/// ```

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigation/models.dart';
import '../../core/navigation/navigation_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EVENTS
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all navigation events.
sealed class NavigationBlocEvent {}

/// User's current position was identified (via QR scan or manual selection).
class SetStartNode extends NavigationBlocEvent {
  final String nodeId;
  SetStartNode(this.nodeId);
}

/// User selected a destination to navigate to.
///
/// This triggers path computation automatically.
class SetDestination extends NavigationBlocEvent {
  final String nodeId;
  SetDestination(this.nodeId);
}

/// User's position was updated (from AR tracking / VIO).
///
/// Called every ~100ms during active navigation.
class UpdatePosition extends NavigationBlocEvent {
  final Position3D position;
  UpdatePosition(this.position);
}

/// A corridor edge was blocked (from Firebase real-time listener).
class EdgeBlocked extends NavigationBlocEvent {
  final String edgeId;
  EdgeBlocked(this.edgeId);
}

/// A previously blocked edge was restored.
class EdgeRestored extends NavigationBlocEvent {
  final String edgeId;
  EdgeRestored(this.edgeId);
}

/// User manually requests a reroute.
class RequestReroute extends NavigationBlocEvent {}

/// User changed floors (detected via stairs/lift).
class FloorChanged extends NavigationBlocEvent {
  final int newFloor;
  FloorChanged(this.newFloor);
}

/// User wants to stop navigation and return to idle.
class StopNavigation extends NavigationBlocEvent {}

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for all navigation states.
sealed class NavigationBlocState {}

/// No active navigation — waiting for start node and destination.
class NavigationInitial extends NavigationBlocState {}

/// Path is being computed.
class NavigationLoading extends NavigationBlocState {
  final String destinationId;
  NavigationLoading(this.destinationId);
}

/// Path has been computed and navigation is active.
class NavigationPathLoaded extends NavigationBlocState {
  /// Ordered list of node IDs from source to destination.
  final List<String> path;

  /// Full NavPath object with nodes, edges, distance, and ETA.
  final NavPath navPath;

  /// Algorithm used ('A*' or 'Dijkstra').
  final String algorithm;

  /// Computation time in milliseconds.
  final int computeTimeMs;

  /// Distance remaining to destination (meters).
  final double remainingDistance;

  /// Current segment index on the path.
  final int currentSegmentIndex;

  /// Turn-by-turn instruction for the user.
  final String? instruction;

  /// Whether the user is currently off-path.
  final bool isOffPath;

  /// Whether a reroute is in progress.
  final bool isRerouting;

  NavigationPathLoaded({
    required this.path,
    required this.navPath,
    required this.algorithm,
    this.computeTimeMs = 0,
    double? remainingDistance,
    this.currentSegmentIndex = 0,
    this.instruction,
    this.isOffPath = false,
    this.isRerouting = false,
  }) : remainingDistance = remainingDistance ?? navPath.totalDistance;

  /// Create a copy with updated progress fields.
  NavigationPathLoaded copyWith({
    double? remainingDistance,
    int? currentSegmentIndex,
    String? instruction,
    bool? isOffPath,
    bool? isRerouting,
    NavPath? navPath,
    List<String>? path,
  }) {
    return NavigationPathLoaded(
      path: path ?? this.path,
      navPath: navPath ?? this.navPath,
      algorithm: algorithm,
      computeTimeMs: computeTimeMs,
      remainingDistance: remainingDistance ?? this.remainingDistance,
      currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
      instruction: instruction ?? this.instruction,
      isOffPath: isOffPath ?? this.isOffPath,
      isRerouting: isRerouting ?? this.isRerouting,
    );
  }
}

/// User has arrived at the destination.
class NavigationArrived extends NavigationBlocState {
  final String destinationName;
  NavigationArrived(this.destinationName);
}

/// Navigation error — display message to user.
class NavigationError extends NavigationBlocState {
  final String message;
  NavigationError(this.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// BLOC
// ─────────────────────────────────────────────────────────────────────────────

/// BLoC that bridges [NavigationController] with the Flutter UI layer.
///
/// The BLoC:
/// 1. Receives user events (SetStartNode, SetDestination, UpdatePosition)
/// 2. Delegates to [NavigationController] for pathfinding and rerouting
/// 3. Listens to controller events for async updates (reroutes, arrivals)
/// 4. Emits states for the UI to render
class NavigationBloc extends Bloc<NavigationBlocEvent, NavigationBlocState> {
  final NavigationController controller;

  /// Subscription to controller's event stream.
  StreamSubscription<NavigationEvent>? _controllerSub;

  /// Last known algorithm used (for UI display).
  String _lastAlgorithm = '';

  NavigationBloc({required this.controller}) : super(NavigationInitial()) {
    // ── Register public event handlers ──
    on<SetStartNode>(_onSetStartNode);
    on<SetDestination>(_onSetDestination);
    on<UpdatePosition>(_onUpdatePosition);
    on<EdgeBlocked>(_onEdgeBlocked);
    on<EdgeRestored>(_onEdgeRestored);
    on<RequestReroute>(_onRequestReroute);
    on<FloorChanged>(_onFloorChanged);
    on<StopNavigation>(_onStopNavigation);

    // ── Register internal sync event handlers ──
    on<_SyncPathLoaded>((event, emit) {
      final pathIds = event.path.nodes.map((n) => n.id).toList();
      emit(NavigationPathLoaded(
        path: pathIds,
        navPath: event.path,
        algorithm: event.algorithm,
        computeTimeMs: event.computeTimeMs,
      ));
    });

    on<_SyncPathRerouted>((event, emit) {
      final pathIds = event.newPath.nodes.map((n) => n.id).toList();
      emit(NavigationPathLoaded(
        path: pathIds,
        navPath: event.newPath,
        algorithm: _lastAlgorithm,
        isRerouting: false,
      ));
    });

    on<_SyncArrival>((event, emit) {
      emit(NavigationArrived(event.destinationName));
    });

    on<_SyncError>((event, emit) {
      emit(NavigationError(event.message));
    });

    on<_SyncPositionUpdate>((event, emit) {
      final currentState = state;
      if (currentState is NavigationPathLoaded) {
        emit(currentState.copyWith(
          remainingDistance: event.remainingDistance,
          currentSegmentIndex: event.currentSegmentIndex,
          instruction: event.instruction,
          isOffPath: false,
        ));
      }
    });

    on<_SyncOffPathWarning>((event, emit) {
      final currentState = state;
      if (currentState is NavigationPathLoaded) {
        emit(currentState.copyWith(isOffPath: true));
      }
    });

    // ── Listen to controller's async event stream ──
    _controllerSub = controller.events.listen(_onControllerEvent);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Handle: user's starting position identified.
  void _onSetStartNode(SetStartNode event, Emitter<NavigationBlocState> emit) {
    controller.setStartNode(event.nodeId);
    // Stay in current state — waiting for destination
  }

  /// Handle: user selected a destination → compute path.
  void _onSetDestination(SetDestination event, Emitter<NavigationBlocState> emit) {
    controller.setDestination(event.nodeId);

    // Emit loading state
    emit(NavigationLoading(event.nodeId));

    // Compute path
    final navPath = controller.computePath();

    if (navPath == null) {
      // Error was already emitted by controller via event stream
      emit(NavigationError('No path found to destination.'));
      return;
    }

    // Extract node IDs for the simple List<String> path
    final pathIds = navPath.nodes.map((n) => n.id).toList();
    _lastAlgorithm = controller.state == NavigationState.navigating ? 'A*' : 'Dijkstra';

    emit(NavigationPathLoaded(
      path: pathIds,
      navPath: navPath,
      algorithm: _lastAlgorithm,
    ));
  }

  /// Handle: position update during active navigation.
  void _onUpdatePosition(UpdatePosition event, Emitter<NavigationBlocState> emit) {
    controller.updatePosition(event.position);

    // The controller emits events via stream → handled in _onControllerEvent.
    // But we also update state directly for immediate progress tracking:
    final currentState = state;
    if (currentState is NavigationPathLoaded && controller.activePath != null) {
      final path = controller.activePath!;
      final projection = path.nearestPoint(event.position);

      emit(currentState.copyWith(
        remainingDistance: path.remainingDistance(projection.segmentIndex),
        currentSegmentIndex: projection.segmentIndex,
        isOffPath: projection.distance > controller.offPathThreshold,
      ));
    }
  }

  /// Handle: edge blocked from Firebase.
  void _onEdgeBlocked(EdgeBlocked event, Emitter<NavigationBlocState> emit) {
    controller.onEdgeBlocked(event.edgeId);
    // Reroute is triggered automatically by controller if path is affected.
    // UI update happens via _onControllerEvent.
  }

  /// Handle: edge restored.
  void _onEdgeRestored(EdgeRestored event, Emitter<NavigationBlocState> emit) {
    controller.onEdgeRestored(event.edgeId);
  }

  /// Handle: user tapped "Reroute".
  void _onRequestReroute(RequestReroute event, Emitter<NavigationBlocState> emit) {
    final currentState = state;
    if (currentState is NavigationPathLoaded) {
      emit(currentState.copyWith(isRerouting: true));
    }
    controller.triggerReroute(RerouteReason.userRequested);
  }

  /// Handle: floor change detected.
  void _onFloorChanged(FloorChanged event, Emitter<NavigationBlocState> emit) {
    controller.onFloorChanged(event.newFloor);
  }

  /// Handle: user stops navigation.
  void _onStopNavigation(StopNavigation event, Emitter<NavigationBlocState> emit) {
    controller.stopNavigation();
    emit(NavigationInitial());
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTROLLER EVENT LISTENER
  // ═══════════════════════════════════════════════════════════════════════════

  /// React to async events from [NavigationController].
  ///
  /// These events arrive via the controller's broadcast stream and
  /// represent state changes triggered by position updates, edge
  /// blocking, or rerouting — not directly by user events.
  void _onControllerEvent(NavigationEvent event) {
    switch (event) {
      case PathComputed(:final path, :final algorithm, :final computeTimeMs):
        _lastAlgorithm = algorithm;
        add(_SyncPathLoaded(path: path, algorithm: algorithm, computeTimeMs: computeTimeMs));

      case PathRerouted(:final newPath, :final reason, :final description):
        add(_SyncPathRerouted(newPath: newPath, reason: reason, description: description));

      case ArrivalDetected(:final destination):
        add(_SyncArrival(destinationName: destination.displayName));

      case NavigationFailed(:final message):
        add(_SyncError(message: message));

      case PositionUpdated(:final remainingDistance, :final currentSegmentIndex, :final nextInstruction):
        add(_SyncPositionUpdate(
          remainingDistance: remainingDistance,
          currentSegmentIndex: currentSegmentIndex,
          instruction: nextInstruction,
        ));

      case OffPathWarning(:final distanceToPath, :final offPathDuration, :final timeUntilReroute):
        add(_SyncOffPathWarning(distanceToPath: distanceToPath));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> close() {
    _controllerSub?.cancel();
    controller.dispose();
    return super.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL SYNC EVENTS (controller → bloc bridge)
// ─────────────────────────────────────────────────────────────────────────────
// These events are dispatched internally to translate controller stream
// events into bloc state transitions. They are NOT part of the public API.

class _SyncPathLoaded extends NavigationBlocEvent {
  final NavPath path;
  final String algorithm;
  final int computeTimeMs;
  _SyncPathLoaded({required this.path, required this.algorithm, required this.computeTimeMs});
}

class _SyncPathRerouted extends NavigationBlocEvent {
  final NavPath newPath;
  final RerouteReason reason;
  final String description;
  _SyncPathRerouted({required this.newPath, required this.reason, required this.description});
}

class _SyncArrival extends NavigationBlocEvent {
  final String destinationName;
  _SyncArrival({required this.destinationName});
}

class _SyncError extends NavigationBlocEvent {
  final String message;
  _SyncError({required this.message});
}

class _SyncPositionUpdate extends NavigationBlocEvent {
  final double remainingDistance;
  final int currentSegmentIndex;
  final String? instruction;
  _SyncPositionUpdate({required this.remainingDistance, required this.currentSegmentIndex, this.instruction});
}

class _SyncOffPathWarning extends NavigationBlocEvent {
  final double distanceToPath;
  _SyncOffPathWarning({required this.distanceToPath});
}


