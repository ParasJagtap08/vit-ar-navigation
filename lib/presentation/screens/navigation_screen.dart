/// NavigationScreen — Active AR navigation with HUD overlay.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/navigation_bloc.dart';
import '../bloc/localization_bloc.dart';
import '../widgets/confidence_indicator.dart';

class NavigationScreen extends StatefulWidget {
  final String destinationNodeId;
  final String destinationName;
  final String buildingId;

  const NavigationScreen({
    super.key,
    required this.destinationNodeId,
    required this.destinationName,
    required this.buildingId,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Start navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNavigation();
    });
  }

  void _startNavigation() {
    final locState = context.read<LocalizationBloc>().state;
    String fromNodeId = 'CS-ENT-1F'; // Default fallback

    if (locState is LocalizationActive && locState.position.nearestNodeId != null) {
      fromNodeId = locState.position.nearestNodeId!;
    }

    context.read<NavigationBloc>().add(StartNavigation(
      fromNodeId: fromNodeId,
      toNodeId: widget.destinationNodeId,
      buildingId: widget.buildingId,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    context.read<NavigationBloc>().add(StopNavigation());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // AR Camera View placeholder
          // In production: flutter_unity_widget UnityWidget goes here
          _buildARPlaceholder(),

          // Navigation HUD overlay
          _buildHUDOverlay(),

          // Bottom panel
          _buildBottomPanel(),

          // Top bar
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildARPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF0A0E21)],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar, size: 80, color: Color(0xFF00BCD4)),
            SizedBox(height: 16),
            Text(
              'AR Camera View',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Unity AR module renders here',
              style: TextStyle(color: Colors.white30, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white70, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Navigating to',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      widget.destinationName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              BlocBuilder<LocalizationBloc, LocalizationState>(
                builder: (context, state) {
                  if (state is LocalizationActive) {
                    return ConfidenceIndicator(confidence: state.position.confidence);
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHUDOverlay() {
    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, state) {
        return switch (state) {
          NavigationLoading(:final destinationName) =>
            _buildLoadingOverlay(destinationName),
          NavigationActive() => _buildActiveHUD(state),
          NavigationRerouting(:final reason) => _buildReroutingOverlay(reason),
          NavigationArrived(:final destinationName) =>
            _buildArrivedOverlay(destinationName),
          NavigationError(:final message) => _buildErrorOverlay(message),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  Widget _buildLoadingOverlay(String destination) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF00BCD4),
              strokeWidth: 3,
            ),
            const SizedBox(height: 20),
            const Text(
              'Computing route...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              destination,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveHUD(NavigationActive state) {
    return Positioned(
      top: 120,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF00BCD4).withOpacity(0.3 + _pulseController.value * 0.2),
              ),
            ),
            child: Row(
              children: [
                // Direction icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BCD4).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.navigation,
                    color: Color(0xFF00BCD4),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.currentInstruction ?? 'Follow the AR arrows',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${state.remainingDistance.toStringAsFixed(0)}m • ${(state.estimatedTimeSeconds / 60).toStringAsFixed(1)} min remaining',
                        style: const TextStyle(
                          color: Color(0xFF00BCD4),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildReroutingOverlay(String reason) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            const SizedBox(height: 16),
            const Text(
              'Rerouting...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reason,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivedOverlay(String destination) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B5E20), Color(0xFF4CAF50)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF50).withOpacity(0.4),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 64),
            const SizedBox(height: 16),
            const Text(
              'You Have Arrived!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              destination,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B5E20),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: const Color(0xFFB71C1C).withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _startNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB71C1C),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: BlocBuilder<NavigationBloc, NavigationState>(
        builder: (context, state) {
          if (state is! NavigationActive) return const SizedBox.shrink();

          return Container(
            padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0),
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.95),
                ],
              ),
            ),
            child: Row(
              children: [
                // Progress info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 1.0 -
                              (state.remainingDistance / state.path.totalDistance)
                                  .clamp(0.0, 1.0),
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF00BCD4)),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.straighten,
                            value: '${state.remainingDistance.toStringAsFixed(0)}m',
                          ),
                          const SizedBox(width: 16),
                          _InfoChip(
                            icon: Icons.timer,
                            value: '${(state.estimatedTimeSeconds / 60).toStringAsFixed(1)} min',
                          ),
                          if (state.path.hasFloorTransition) ...[
                            const SizedBox(width: 16),
                            _InfoChip(
                              icon: Icons.layers,
                              value: 'Floors: ${state.path.floorsTraversed.join(",")}',
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Stop button
                GestureDetector(
                  onTap: () {
                    context.read<NavigationBloc>().add(StopNavigation());
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFD32F2F).withOpacity(0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.stop, color: Colors.white, size: 28),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white38, size: 16),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
