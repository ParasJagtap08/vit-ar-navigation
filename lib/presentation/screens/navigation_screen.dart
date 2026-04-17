/// NavigationScreen — displays the active navigation path and status.
///
/// Connects to [NavigationBloc] to:
/// - Show a loading indicator while the path is computing
/// - Display the computed path (node IDs + distance + ETA)
/// - Show off-path warnings and reroute status
/// - Provide a "Navigate" button to trigger pathfinding
/// - Handle arrival and error states

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/navigation/models.dart';
import '../../core/navigation/navigation_controller.dart';
import '../bloc/navigation_bloc.dart';

class NavigationScreen extends StatefulWidget {
  /// Pre-selected start node (e.g. from QR scan).
  final String? initialStartNode;

  /// Pre-selected destination (e.g. from search screen).
  final String? initialDestination;

  const NavigationScreen({
    super.key,
    this.initialStartNode,
    this.initialDestination,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _startController = TextEditingController();
  final _destController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill from arguments
    if (widget.initialStartNode != null) {
      _startController.text = widget.initialStartNode!;
      context.read<NavigationBloc>().add(SetStartNode(widget.initialStartNode!));
    }
    if (widget.initialDestination != null) {
      _destController.text = widget.initialDestination!;
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _destController.dispose();
    super.dispose();
  }

  void _onNavigatePressed() {
    final start = _startController.text.trim();
    final dest = _destController.text.trim();

    if (start.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both start and destination node IDs')),
      );
      return;
    }

    final bloc = context.read<NavigationBloc>();
    bloc.add(SetStartNode(start));
    bloc.add(SetDestination(dest));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Navigation'),
        centerTitle: true,
        elevation: 0,
        actions: [
          // Stop navigation button
          BlocBuilder<NavigationBloc, NavigationBlocState>(
            builder: (context, state) {
              if (state is NavigationPathLoaded || state is NavigationLoading) {
                return IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Stop Navigation',
                  onPressed: () {
                    context.read<NavigationBloc>().add(StopNavigation());
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Input Section ───
          _buildInputSection(),

          const Divider(height: 1),

          // ─── State-Driven Content ───
          Expanded(
            child: BlocConsumer<NavigationBloc, NavigationBlocState>(
              listener: _onStateChange,
              builder: (context, state) => switch (state) {
                NavigationInitial() => _buildIdleView(),
                NavigationLoading(:final destinationId) => _buildLoadingView(destinationId),
                NavigationPathLoaded() => _buildPathView(state),
                NavigationArrived(:final destinationName) => _buildArrivedView(destinationName),
                NavigationError(:final message) => _buildErrorView(message),
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Start node
          TextField(
            controller: _startController,
            decoration: InputDecoration(
              labelText: 'Start Node',
              hintText: 'e.g. CS-ENT-1F',
              prefixIcon: const Icon(Icons.my_location, color: Colors.green),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),

          // Destination node
          TextField(
            controller: _destController,
            decoration: InputDecoration(
              labelText: 'Destination',
              hintText: 'e.g. CS-103',
              prefixIcon: const Icon(Icons.flag, color: Colors.red),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
            ),
          ),
          const SizedBox(height: 12),

          // Navigate button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _onNavigatePressed,
              icon: const Icon(Icons.navigation),
              label: const Text('Navigate', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE VIEWS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Idle — no active navigation.
  Widget _buildIdleView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Enter start and destination to begin',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// Loading — path is being computed.
  Widget _buildLoadingView(String destinationId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(strokeWidth: 3),
          const SizedBox(height: 24),
          Text(
            'Computing path to $destinationId...',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Selecting optimal algorithm',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// PathLoaded — display the computed path.
  Widget _buildPathView(NavigationPathLoaded state) {
    return Column(
      children: [
        // ── Progress header ──
        _buildProgressHeader(state),

        // ── Off-path warning ──
        if (state.isOffPath)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.orange.shade100,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are off the path. Rerouting...',
                    style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

        // ── Rerouting indicator ──
        if (state.isRerouting)
          const LinearProgressIndicator(),

        // ── Path node list ──
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: state.path.length,
            itemBuilder: (context, index) => _buildPathNodeTile(state, index),
          ),
        ),

        // ── Action buttons ──
        _buildActionBar(state),
      ],
    );
  }

  /// Progress header with distance, ETA, and algorithm.
  Widget _buildProgressHeader(NavigationPathLoaded state) {
    final totalDist = state.navPath.totalDistance.toStringAsFixed(1);
    final remaining = state.remainingDistance.toStringAsFixed(1);
    final eta = state.navPath.estimatedTimeSeconds.toStringAsFixed(0);
    final progress = 1.0 - (state.remainingDistance / state.navPath.totalDistance).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Distance and ETA
          Row(
            children: [
              _buildInfoChip(Icons.straighten, '${remaining}m left'),
              const SizedBox(width: 12),
              _buildInfoChip(Icons.timer_outlined, '~${eta}s'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  state.algorithm,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 6),

          // Instruction
          if (state.instruction != null)
            Text(
              state.instruction!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  /// Single node tile in the path list.
  Widget _buildPathNodeTile(NavigationPathLoaded state, int index) {
    final nodeId = state.path[index];
    final node = state.navPath.nodes[index];
    final isCurrentSegment = index == state.currentSegmentIndex;
    final isPast = index < state.currentSegmentIndex;
    final isDestination = index == state.path.length - 1;
    final isStart = index == 0;

    // Icon based on node type
    IconData icon;
    Color iconColor;
    if (isStart) {
      icon = Icons.my_location;
      iconColor = Colors.green;
    } else if (isDestination) {
      icon = Icons.flag;
      iconColor = Colors.red;
    } else {
      switch (node.type) {
        case NodeType.room:
        case NodeType.lab:
        case NodeType.office:
          icon = Icons.door_front_door;
          iconColor = Colors.blue;
        case NodeType.stairs:
          icon = Icons.stairs;
          iconColor = Colors.orange;
        case NodeType.lift:
          icon = Icons.elevator;
          iconColor = Colors.purple;
        case NodeType.washroom:
          icon = Icons.wc;
          iconColor = Colors.teal;
        case NodeType.corridor:
        case NodeType.junction:
          icon = Icons.timeline;
          iconColor = Colors.grey;
        default:
          icon = Icons.circle;
          iconColor = Colors.grey;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isCurrentSegment
            ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
            : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: isPast ? iconColor.withOpacity(0.4) : iconColor),
        title: Text(
          node.displayName,
          style: TextStyle(
            fontWeight: isCurrentSegment ? FontWeight.bold : FontWeight.normal,
            color: isPast ? Colors.grey : null,
          ),
        ),
        subtitle: Text(
          nodeId,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: isPast
            ? Icon(Icons.check_circle, color: Colors.green.shade400, size: 20)
            : isCurrentSegment
                ? const Icon(Icons.navigation, color: Colors.blue, size: 20)
                : null,
        dense: true,
      ),
    );
  }

  /// Bottom action bar with reroute and stop buttons.
  Widget _buildActionBar(NavigationPathLoaded state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          // Reroute button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                context.read<NavigationBloc>().add(RequestReroute());
              },
              icon: const Icon(Icons.alt_route),
              label: const Text('Reroute'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Stop button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                context.read<NavigationBloc>().add(StopNavigation());
              },
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Arrived — user reached the destination.
  Widget _buildArrivedView(String destinationName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 16),
          const Text('You have arrived!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(destinationName, style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              context.read<NavigationBloc>().add(StopNavigation());
            },
            icon: const Icon(Icons.home),
            label: const Text('Back to Home'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  /// Error — display error message with retry.
  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _onNavigatePressed,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Info chip (icon + label).
  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade800)),
      ],
    );
  }

  /// React to state changes for side-effects (snackbar, etc).
  void _onStateChange(BuildContext context, NavigationBlocState state) {
    switch (state) {
      case NavigationArrived(:final destinationName):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Arrived at $destinationName!'),
            backgroundColor: Colors.green,
          ),
        );
      case NavigationError(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red.shade400),
        );
      case NavigationPathLoaded(isRerouting: false, isOffPath: false):
        // Path loaded or reroute complete — no action needed
        break;
      default:
        break;
    }
  }
}
