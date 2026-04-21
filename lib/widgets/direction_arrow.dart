/// Animated directional compass arrow widget.
///
/// Displays a rotated arrow pointing toward the destination,
/// with cardinal direction text and smooth rotation animation.

import 'dart:math';
import 'package:flutter/material.dart';

class DirectionArrow extends StatefulWidget {
  /// Relative arrow angle in radians (bearing - heading).
  final double angleRadians;

  /// Cardinal direction text (N, NE, E, etc.).
  final String cardinalDirection;

  /// Distance text to display below the arrow.
  final String? distanceText;

  /// Widget size (diameter).
  final double size;

  const DirectionArrow({
    super.key,
    required this.angleRadians,
    required this.cardinalDirection,
    this.distanceText,
    this.size = 120,
  });

  @override
  State<DirectionArrow> createState() => _DirectionArrowState();
}

class _DirectionArrowState extends State<DirectionArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseScale = 1.0 + _pulseController.value * 0.08;
        final glowOpacity = 0.3 + _pulseController.value * 0.4;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cardinal direction
            Text(
              widget.cardinalDirection,
              style: TextStyle(
                color: const Color(0xFF00E5FF).withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),

            // Arrow container
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  Transform.scale(
                    scale: pulseScale,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00BCD4).withOpacity(glowOpacity * 0.4),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00BCD4).withOpacity(glowOpacity * 0.2),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Inner circle background
                  Container(
                    width: widget.size * 0.85,
                    height: widget.size * 0.85,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D1B2A).withOpacity(0.9),
                      border: Border.all(
                        color: const Color(0xFF00BCD4).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                  ),

                  // Compass ticks
                  ...List.generate(8, (i) {
                    final tickAngle = i * pi / 4;
                    final isMajor = i % 2 == 0;
                    return Transform.rotate(
                      angle: tickAngle,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: EdgeInsets.only(top: widget.size * 0.08),
                          child: Container(
                            width: isMajor ? 2.5 : 1.5,
                            height: isMajor ? 12 : 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BCD4).withOpacity(
                                isMajor ? 0.6 : 0.3,
                              ),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  // Arrow (rotated)
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.angleRadians),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (context, angle, _) {
                      return Transform.rotate(
                        angle: angle,
                        child: CustomPaint(
                          size: Size(widget.size * 0.5, widget.size * 0.5),
                          painter: _ArrowPainter(
                            glowOpacity: glowOpacity,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Distance text
            if (widget.distanceText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BCD4).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00BCD4).withOpacity(0.2),
                  ),
                ),
                child: Text(
                  widget.distanceText!,
                  style: const TextStyle(
                    color: Color(0xFF00E5FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Custom painter for the directional arrow.
class _ArrowPainter extends CustomPainter {
  final double glowOpacity;

  _ArrowPainter({required this.glowOpacity});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final arrowHeight = size.height * 0.9;
    final arrowWidth = size.width * 0.5;

    // Arrow shape — pointing up
    final arrowPath = Path()
      ..moveTo(cx, cy - arrowHeight / 2) // tip
      ..lineTo(cx + arrowWidth / 2, cy + arrowHeight / 4) // right
      ..lineTo(cx, cy + arrowHeight / 8) // notch
      ..lineTo(cx - arrowWidth / 2, cy + arrowHeight / 4) // left
      ..close();

    // Glow shadow
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(glowOpacity * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Arrow fill — gradient effect via two layers
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xFF00BCD4)
        ..style = PaintingStyle.fill,
    );

    // Arrow highlight
    final highlightPath = Path()
      ..moveTo(cx, cy - arrowHeight / 2)
      ..lineTo(cx + arrowWidth / 4, cy + arrowHeight / 8)
      ..lineTo(cx, cy + arrowHeight / 10)
      ..close();

    canvas.drawPath(
      highlightPath,
      Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.4)
        ..style = PaintingStyle.fill,
    );

    // Arrow outline
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.glowOpacity != glowOpacity;
}
