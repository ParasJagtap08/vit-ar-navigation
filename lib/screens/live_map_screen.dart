/// LiveMapScreen — Full-screen OpenStreetMap navigation view.
///
/// Features:
/// - Interactive flutter_map with OSM tiles
/// - User position marker (animated blue dot)
/// - Destination marker (red pin)
/// - Route polyline between start and destination
/// - HUD overlay with distance, ETA, direction arrow
/// - Start Navigation / Stop / Simulate controls
/// - AR View toggle

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/gps_config.dart';
import '../providers/navigation_provider.dart';
import '../widgets/direction_arrow.dart';
import 'ar_navigation_screen.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  late AnimationController _pulseController;
  late AnimationController _dashController;
  bool _followUser = true;
  bool _isNavigationStarted = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _dashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dashController.dispose();
    super.dispose();
  }

  void _centerOnUser() {
    final nav = context.read<NavigationProvider>();
    final userPos = nav.userLatLng;
    if (userPos != null) {
      _mapController.move(userPos, _mapController.camera.zoom);
      setState(() => _followUser = true);
    }
  }

  void _fitPathBounds() {
    final nav = context.read<NavigationProvider>();
    final points = nav.pathLatLngs;
    final userPos = nav.userLatLng;

    if (points.isEmpty) return;

    final allPoints = [...points];
    if (userPos != null) allPoints.add(userPos);

    if (allPoints.length < 2) {
      _mapController.move(allPoints.first, 18);
      return;
    }

    final bounds = LatLngBounds.fromPoints(allPoints);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
        maxZoom: 19,
      ),
    );
  }

  void _startNavigation() {
    final nav = context.read<NavigationProvider>();
    nav.startGpsTracking();
    setState(() => _isNavigationStarted = true);

    // Fit the path bounds after a small delay for map to settle
    Future.delayed(const Duration(milliseconds: 300), _fitPathBounds);
  }

  void _stopNavigation() {
    final nav = context.read<NavigationProvider>();
    nav.stopNavigation();
    setState(() => _isNavigationStarted = false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Consumer<NavigationProvider>(
        builder: (context, nav, _) {
          // Auto-follow user when tracking
          if (_followUser && nav.isLiveTracking && nav.userLatLng != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _mapController.move(
                  nav.userLatLng!,
                  _mapController.camera.zoom,
                );
              }
            });
          }

          return Stack(
            children: [
              // ─── Map ───
              Positioned.fill(child: _buildMap(nav)),

              // ─── Top gradient overlay ───
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(context, nav),
              ),

              // ─── Re-center FAB ───
              Positioned(
                right: 16,
                bottom: _isNavigationStarted ? 320 : 200,
                child: _buildFloatingControls(nav),
              ),

              // ─── Bottom panel ───
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _isNavigationStarted
                    ? _buildNavigationPanel(nav)
                    : _buildStartPanel(nav),
              ),

              // ─── Arrival overlay ───
              if (nav.hasArrived)
                Positioned.fill(child: _buildArrivalOverlay(nav)),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MAP
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMap(NavigationProvider nav) {
    final userPos = nav.userLatLng;
    final destPos = nav.destinationLatLng;
    final pathPoints = nav.pathLatLngs;

    // Default center: destination, user, or VIT Pune campus
    final center = userPos ??
        destPos ??
        const LatLng(18.4529, 73.8674);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 18,
        maxZoom: 20,
        minZoom: 14,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            setState(() => _followUser = false);
          }
        },
      ),
      children: [
        // OSM tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.vit.campus.navigator',
          maxZoom: 20,
        ),

        // Route polyline
        if (pathPoints.length >= 2)
          PolylineLayer(
            polylines: [
              // Shadow
              Polyline(
                points: pathPoints,
                strokeWidth: 8,
                color: const Color(0xFF00BCD4).withOpacity(0.3),
              ),
              // Main route line
              Polyline(
                points: pathPoints,
                strokeWidth: 5,
                color: const Color(0xFF00E5FF),
                borderStrokeWidth: 1,
                borderColor: const Color(0xFF0088A3),
              ),
            ],
          ),

        // Path node markers (small dots on each graph node)
        if (pathPoints.length >= 2)
          MarkerLayer(
            markers: _buildPathNodeMarkers(nav),
          ),

        // Destination marker
        if (destPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: destPos,
                width: 50,
                height: 60,
                child: _buildDestinationMarker(nav),
              ),
            ],
          ),

        // User position marker
        if (userPos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userPos,
                width: 80,
                height: 80,
                child: _buildUserMarker(),
              ),
            ],
          ),
      ],
    );
  }

  /// Build small dot markers for each node along the path.
  List<Marker> _buildPathNodeMarkers(NavigationProvider nav) {
    final pathLatLngs = nav.pathLatLngs;
    if (pathLatLngs.length <= 2) return [];

    // Skip first and last (they have special markers)
    return List.generate(pathLatLngs.length - 2, (i) {
      final idx = i + 1;
      final isCurrentSegment = idx == nav.currentSegmentIndex;
      final isPast = idx < nav.currentSegmentIndex;

      return Marker(
        point: pathLatLngs[idx],
        width: 14,
        height: 14,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isPast
                ? const Color(0xFF4CAF50).withOpacity(0.6)
                : isCurrentSegment
                    ? const Color(0xFF00E5FF)
                    : const Color(0xFF00BCD4).withOpacity(0.4),
            border: Border.all(
              color: Colors.white.withOpacity(0.6),
              width: isCurrentSegment ? 2 : 1,
            ),
            boxShadow: isCurrentSegment
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
        ),
      );
    });
  }

  /// Animated blue pulsing dot for user position.
  Widget _buildUserMarker() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseRadius = 30.0 + _pulseController.value * 15.0;
        final pulseOpacity = 0.3 - _pulseController.value * 0.2;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulse ring
            Container(
              width: pulseRadius * 2,
              height: pulseRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2196F3).withOpacity(pulseOpacity),
              ),
            ),
            // Accuracy ring
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2196F3).withOpacity(0.2),
                border: Border.all(
                  color: const Color(0xFF2196F3).withOpacity(0.4),
                  width: 1.5,
                ),
              ),
            ),
            // Core dot
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2196F3),
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2196F3).withOpacity(0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Destination pin marker.
  Widget _buildDestinationMarker(NavigationProvider nav) {
    final destName = nav.destNode?.displayName ?? 'Destination';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E).withOpacity(0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Text(
            destName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Pin icon
        const Icon(
          Icons.location_on,
          color: Color(0xFFFF5252),
          size: 32,
          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext context, NavigationProvider nav) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8, MediaQuery.of(context).padding.top + 4, 8, 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A0E21),
            const Color(0xFF0A0E21).withOpacity(0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white70, size: 20),
            onPressed: () {
              nav.stopGpsTracking();
              Navigator.pop(context);
            },
          ),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isNavigationStarted ? 'NAVIGATING' : 'MAP VIEW',
                  style: TextStyle(
                    color: _isNavigationStarted
                        ? const Color(0xFF00E5FF)
                        : Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
                if (nav.destNode != null)
                  Text(
                    '→ ${nav.destNode!.displayName}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Algorithm badge
          if (nav.isNavigating && nav.algorithmUsed != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF00BCD4).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.route_rounded,
                      color: Color(0xFF00BCD4), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    nav.algorithmUsed!,
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FLOATING CONTROLS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFloatingControls(NavigationProvider nav) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AR View toggle
        if (nav.isNavigating)
          _buildFab(
            icon: Icons.view_in_ar_rounded,
            tooltip: 'AR View',
            color: const Color(0xFF7C4DFF),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ARNavigationScreen()),
              );
            },
          ),
        const SizedBox(height: 10),

        // Re-center
        _buildFab(
          icon: _followUser
              ? Icons.my_location_rounded
              : Icons.location_searching_rounded,
          tooltip: 'Center on me',
          color: const Color(0xFF00BCD4),
          onTap: _centerOnUser,
        ),
        const SizedBox(height: 10),

        // Fit path
        if (nav.pathLatLngs.length >= 2)
          _buildFab(
            icon: Icons.zoom_out_map_rounded,
            tooltip: 'Fit path',
            color: const Color(0xFF4CAF50),
            onTap: _fitPathBounds,
          ),
      ],
    );
  }

  Widget _buildFab({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E).withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // START PANEL (before navigation begins)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStartPanel(NavigationProvider nav) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00121830),
            Color(0xFF121830),
            Color(0xFF0D1225),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Route summary
              if (nav.activePath != null) ...[
                Row(
                  children: [
                    // Start
                    Expanded(
                      child: _routeEndpoint(
                        icon: Icons.my_location_rounded,
                        color: const Color(0xFF4CAF50),
                        label: nav.startNode?.displayName ?? 'Start',
                        sublabel: nav.startNode != null
                            ? 'Floor ${nav.startNode!.floor}'
                            : '',
                      ),
                    ),
                    // Arrow
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded,
                          color: Colors.white24, size: 20),
                    ),
                    // Destination
                    Expanded(
                      child: _routeEndpoint(
                        icon: Icons.flag_rounded,
                        color: const Color(0xFFFF5252),
                        label: nav.destNode?.displayName ?? 'Destination',
                        sublabel: nav.destNode != null
                            ? 'Floor ${nav.destNode!.floor}'
                            : '',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stats
                Row(
                  children: [
                    _infoChip(Icons.straighten_rounded,
                        nav.activePath!.formattedDistance),
                    const SizedBox(width: 12),
                    _infoChip(Icons.timer_outlined,
                        nav.activePath!.formattedETA),
                    const SizedBox(width: 12),
                    _infoChip(Icons.layers_rounded,
                        '${nav.activePath!.floorsTraversed.length} floor${nav.activePath!.isCrossFloor ? 's' : ''}'),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Start Navigation button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: nav.activePath != null ? _startNavigation : null,
                  icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                  label: const Text(
                    'Start Navigation',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BCD4),
                    disabledBackgroundColor: const Color(0xFF2A2A4A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // NAVIGATION PANEL (active navigation HUD)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavigationPanel(NavigationProvider nav) {
    final progress = nav.activePath != null
        ? 1.0 - (nav.remainingPathDistance / nav.activePath!.totalDistance).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00121830),
            Color(0xFF121830),
            Color(0xFF0D1225),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Direction arrow + instruction
              Row(
                children: [
                  // Direction arrow
                  DirectionArrow(
                    angleRadians: nav.relativeArrowAngle,
                    cardinalDirection: nav.directionToDestination,
                    size: 80,
                  ),
                  const SizedBox(width: 16),

                  // Instruction + distance
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nav.currentInstruction,
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _infoChip(Icons.straighten_rounded,
                                nav.formattedDistance),
                            const SizedBox(width: 12),
                            _infoChip(Icons.timer_outlined,
                                nav.activePath?.formattedETA ?? ''),
                          ],
                        ),
                      ],
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
                  minHeight: 4,
                  backgroundColor: const Color(0xFF1A2640),
                  valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF00BCD4)),
                ),
              ),
              const SizedBox(height: 12),

              // Action buttons
              Row(
                children: [
                  // Simulate step (for emulator)
                  Expanded(
                    child: _panelButton(
                      icon: Icons.directions_walk_rounded,
                      label: 'Simulate Step',
                      color: const Color(0xFF00BCD4),
                      onTap: () => nav.simulateStep(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Reroute
                  Expanded(
                    child: _panelButton(
                      icon: Icons.alt_route_rounded,
                      label: 'Reroute',
                      color: const Color(0xFFFFA726),
                      onTap: () {
                        nav.reroute();
                        _fitPathBounds();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Stop
                  Expanded(
                    child: _panelButton(
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      color: const Color(0xFFEF5350),
                      onTap: _stopNavigation,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ARRIVAL OVERLAY
  // ═══════════════════════════════════════════════════════════════

  Widget _buildArrivalOverlay(NavigationProvider nav) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF121830),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4CAF50).withOpacity(0.2),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF4CAF50), size: 64),
              const SizedBox(height: 16),
              const Text(
                '🎉 You have arrived!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                nav.destNode?.displayName ?? '',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    nav.stopNavigation();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.home_rounded, color: Colors.white),
                  label: const Text('Back to Home',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  Widget _routeEndpoint({
    required IconData icon,
    required Color color,
    required String label,
    required String sublabel,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (sublabel.isNotEmpty)
                Text(
                  sublabel,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white38),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _panelButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
