import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../core/models.dart';
import '../providers/navigation_provider.dart';
import 'navigation_screen.dart'; // fallback

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

  @override
  void initState() {
    super.initState();
    _initCamera();
    
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

  @override
  void dispose() {
    _cameraController?.dispose();
    _arrowAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<NavigationProvider>(
        builder: (context, nav, _) {
          final hasPath = nav.activePath != null && nav.currentSegmentIndex < nav.activePath!.nodes.length - 1;
          
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

              // 3. Top Header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopHeader(context, nav),
              ),

              // 4. Floating Map Toggle
              Positioned(
                right: 20,
                bottom: 150,
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFF00BCD4).withOpacity(0.8),
                  child: const Icon(Icons.map_rounded),
                  onPressed: () {
                    // Switch to 2D Map view natively
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const NavigationScreen()),
                    );
                  },
                ),
              ),

              // 5. Instruction Panel
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: _buildInstructionPanel(nav),
              ),
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
            Icon(Icons.camera_alt_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              _cameraError ? 'Camera unavailable in simulator/web' : 'Initializing AR Camera...',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, NavigationProvider nav) {
    return Container(
      padding: EdgeInsets.fromLTRB(10, MediaQuery.of(context).padding.top + 10, 10, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
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
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInstructionPanel(NavigationProvider nav) {
    if (nav.activePath == null) return const SizedBox();
    
    final path = nav.activePath!;
    final remaining = path.remainingDistance(nav.currentSegmentIndex);
    
    String instruction = 'Arrived at destination!';
    if (nav.currentSegmentIndex < path.nodes.length - 1) {
      final next = path.nodes[nav.currentSegmentIndex + 1];
      if (next.type == NodeType.stairs) instruction = 'Head up the stairs';
      else if (next.type == NodeType.entrance) instruction = 'Exit to the campus';
      else instruction = 'Head towards ${next.displayName}';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121830).withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.3)),
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
            instruction,
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
              _infoText('${remaining.toStringAsFixed(0)}m left', Icons.straighten),
              _infoText(path.formattedETA, Icons.timer),
              _infoText('Floor ${nav.selectedFloor}', Icons.layers),
            ],
          ),
          const SizedBox(height: 16),
          // AR Simulator Control (Since we lack physical movement in emulator)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.directions_walk, color: Colors.white),
              label: const Text('Simulate Step Forward', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4).withOpacity(0.8),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => nav.advanceSegment(),
            ),
          )
        ],
      ),
    );
  }

  Widget _infoText(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

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

    // Simple delta calculations for visual arrow rotation
    final dx = nextNode.position.x - currNode.position.x;
    final dz = nextNode.position.z - currNode.position.z;
    
    // We assume the user's camera is facing "forward" dynamically, 
    // but without real compass tracking we will animate a floating arrow
    // that subtly bobs in front of the camera, pointing slightly left or right
    // depending on the required turn.
    
    double angle = 0.0;
    if (dx.abs() > dz.abs()) {
      angle = dx > 0 ? pi / 4 : -pi / 4; // Turn Right or Left
    } else {
      angle = 0; // Go Straight
    }

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
