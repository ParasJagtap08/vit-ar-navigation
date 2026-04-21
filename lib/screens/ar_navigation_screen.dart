import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../core/models.dart';
import '../providers/navigation_provider.dart';
import '../widgets/direction_arrow.dart';
import 'live_map_screen.dart';

class ARNavigationScreen extends StatefulWidget {
  const ARNavigationScreen({super.key});

  @override
  State<ARNavigationScreen> createState() => _ARNavigationScreenState();
}

class _ARNavigationScreenState extends State<ARNavigationScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _cameraError = false;

  late AnimationController _arrowAnimController;

  /// Compass heading stream subscription.
  StreamSubscription<CompassEvent>? _compassSub;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initCompass();

    _arrowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = true);
        return;
      }
      // Pick the first back camera
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _cameraError = true);
      }
    }
  }

  /// Initialize compass for real device heading.
  void _initCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading != null && mounted) {
        context.read<NavigationProvider>().updateDeviceHeading(event.heading!);
      }
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _arrowAnimController.dispose();
    _compassSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<NavigationProvider>(
        builder: (context, nav, _) {
          final hasPath = nav.activePath != null &&
              nav.currentSegmentIndex < nav.activePath!.nodes.length - 1;

          return Stack(
            children: [
              // 1. Camera Feed (or fallback)
              Positioned.fill(
                child: _buildCameraFeed(),
              ),

              // 2. AR Arrow Overlay
              if (hasPath)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _arrowAnimController,
                    builder: (context, _) => CustomPaint(
                      painter: ARArrowPainter(
                        nav: nav,
                        animationValue: _arrowAnimController.value,
                      ),
                    ),
                  ),
                ),

              // 3. Direction indicator (top center)
              if (hasPath)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: DirectionArrow(
                      angleRadians: nav.relativeArrowAngle,
                      cardinalDirection: nav.directionToDestination,
                      distanceText: nav.formattedDistance,
                      size: 100,
                    ),
                  ),
                ),

              // 4. Top Header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopHeader(context, nav),
              ),

              // 5. Map toggle FAB
              Positioned(
                right: 20,
                bottom: 180,
                child: FloatingActionButton(
                  heroTag: 'map_toggle',
                  backgroundColor:
                      const Color(0xFF00BCD4).withOpacity(0.8),
                  child: const Icon(Icons.map_rounded),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LiveMapScreen()),
                    );
                  },
                ),
              ),

              // 6. Instruction Panel
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: _buildInstructionPanel(nav),
              ),

              // 7. Arrival overlay
              if (nav.hasArrived)
                Positioned.fill(child: _buildArrivalOverlay(nav)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCameraFeed() {
    if (_isCameraInitialized && _cameraController != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 1,
            height: _cameraController!.value.previewSize?.width ?? 1,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    }
    return Container(
      color: const Color(0xFF050510),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_rounded,
                size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              _cameraError
                  ? 'Camera unavailable in simulator/web'
                  : 'Initializing AR Camera...',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, NavigationProvider nav) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          10, MediaQuery.of(context).padding.top + 10, 10, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: Colors.white, size: 28),
            onPressed: () {
              nav.stopNavigation();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AR LIVE VIEW',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Follow the arrows',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          // Compass heading indicator
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00BCD4).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF00BCD4).withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore_rounded,
                    color: Color(0xFF00BCD4), size: 14),
                const SizedBox(width: 4),
                Text(
                  '${nav.deviceHeading.toStringAsFixed(0)}°',
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

  Widget _buildInstructionPanel(NavigationProvider nav) {
    if (nav.activePath == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121830).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF00BCD4).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nav.currentInstruction,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _infoText(nav.formattedDistance, Icons.straighten),
              _infoText(
                  nav.activePath?.formattedETA ?? '', Icons.timer),
              _infoText('Floor ${nav.selectedFloor}', Icons.layers),
            ],
          ),
          const SizedBox(height: 16),
          // Simulate step button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.directions_walk,
                  color: Colors.white),
              label: const Text('Simulate Step Forward',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF00BCD4).withOpacity(0.8),
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => nav.simulateStep(),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildArrivalOverlay(NavigationProvider nav) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF121830),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFF4CAF50).withOpacity(0.5)),
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
                    fontSize: 16),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    nav.stopNavigation();
                    Navigator.of(context)
                        .popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.home_rounded,
                      color: Colors.white),
                  label: const Text('Back to Home',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
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

  Widget _infoText(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

/// Paints an AR-style directional arrow on the camera feed.
class ARArrowPainter extends CustomPainter {
  final NavigationProvider nav;
  final double animationValue;

  ARArrowPainter({required this.nav, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (nav.activePath == null) return;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Determine direction between current node and next node
    final path = nav.activePath!;
    final nodes = path.nodes;
    final currIdx = nav.currentSegmentIndex;

    if (currIdx >= nodes.length - 1) return;

    final currNode = nodes[currIdx];
    final nextNode = nodes[currIdx + 1];

    // Use the relative arrow angle from provider (compass-aware)
    double angle = nav.relativeArrowAngle;

    // Floating bob effect
    final bob = sin(animationValue * 2 * pi) * 20;

    canvas.save();
    canvas.translate(cx, cy + bob + 50);
    // Add a perspective skew to make it look 'AR' like it's painted on the floor
    canvas.transform(Float64List.fromList([
      1.0, 0.0, 0.0, 0.0,
      0.0, 0.5, 0.0, 0.0, // compress Y to look like floor
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ]));

    canvas.rotate(angle);

    // Draw Glowing Path on Floor
    final paintFloor = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final pathShadow = Path()
      ..moveTo(-30, 150)
      ..lineTo(30, 150)
      ..lineTo(40, -50)
      ..lineTo(70, -50)
      ..lineTo(0, -150)
      ..lineTo(-70, -50)
      ..lineTo(-40, -50)
      ..close();

    canvas.drawPath(pathShadow, paintFloor);

    // Draw main Arrow
    final paintArrow = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill
      ..strokeJoin = StrokeJoin.round;

    final paintWhite = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(pathShadow, paintArrow);
    canvas.drawPath(pathShadow, paintWhite);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ARArrowPainter oldDelegate) => true;
}
