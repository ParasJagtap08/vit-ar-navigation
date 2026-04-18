import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../core/models.dart';

/// Custom painter that renders a 2D floor plan with nodes, edges,
/// and navigation path overlay.
class MapPainter extends CustomPainter {
  final List<NavNode> nodes;
  final List<NavEdge> edges;
  final NavPath? activePath;
  final int currentSegmentIndex;
  final String? selectedNodeId;
  final String? startNodeId;
  final String? destNodeId;
  final Set<String> blockedEdges;
  final double animationValue;
  final Map<String, NavNode> nodeMap;

  MapPainter({
    required this.nodes,
    required this.edges,
    this.activePath,
    this.currentSegmentIndex = 0,
    this.selectedNodeId,
    this.startNodeId,
    this.destNodeId,
    this.blockedEdges = const {},
    this.animationValue = 0.0,
    required this.nodeMap,
  });

  // Layout constants
  static const double _scale = 7.0;
  static const double _offsetX = 20.0;
  static const double _offsetZ = 30.0;

  Offset _toScreen(Position3D pos) {
    return Offset(
      pos.x * _scale + _offsetX,
      (30.0 - pos.z) * _scale + _offsetZ, // Flip Z for screen coordinates
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawEdges(canvas);
    if (activePath != null) {
      _drawPath(canvas);
    }
    _drawNodes(canvas);
    _drawLabels(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1E1E3A)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += _scale * 5) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += _scale * 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawEdges(Canvas canvas) {
    final edgePaint = Paint()
      ..color = const Color(0xFF2A3A5C)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final blockedPaint = Paint()
      ..color = const Color(0xFF5C2A2A)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final from = nodeMap[edge.fromNode];
      final to = nodeMap[edge.toNode];
      if (from == null || to == null) continue;

      final p1 = _toScreen(from.position);
      final p2 = _toScreen(to.position);

      final isBlocked = blockedEdges.contains(edge.id);
      canvas.drawLine(p1, p2, isBlocked ? blockedPaint : edgePaint);

      if (isBlocked) {
        // Draw X on blocked edge
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final xPaint = Paint()
          ..color = const Color(0xFFFF4444)
          ..strokeWidth = 2.0;
        canvas.drawLine(mid + const Offset(-4, -4), mid + const Offset(4, 4), xPaint);
        canvas.drawLine(mid + const Offset(4, -4), mid + const Offset(-4, 4), xPaint);
      }
    }
  }

  void _drawPath(Canvas canvas) {
    if (activePath == null || activePath!.nodes.length < 2) return;

    // Draw glow behind path
    final glowPaint = Paint()
      ..color = const Color(0xFF00BCD4).withOpacity(0.15)
      ..strokeWidth = 12.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pathPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final passedPaint = Paint()
      ..color = const Color(0xFF00BCD4).withOpacity(0.3)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw full path glow
    final glowPath = Path();
    for (int i = 0; i < activePath!.nodes.length; i++) {
      final pt = _toScreen(activePath!.nodes[i].position);
      if (i == 0) {
        glowPath.moveTo(pt.dx, pt.dy);
      } else {
        glowPath.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(glowPath, glowPaint);

    // Draw segments
    for (int i = 0; i < activePath!.nodes.length - 1; i++) {
      final p1 = _toScreen(activePath!.nodes[i].position);
      final p2 = _toScreen(activePath!.nodes[i + 1].position);
      final isPassed = i < currentSegmentIndex;
      canvas.drawLine(p1, p2, isPassed ? passedPaint : pathPaint);
    }

    // Animated dot along active segment
    if (currentSegmentIndex < activePath!.nodes.length - 1) {
      final p1 = _toScreen(activePath!.nodes[currentSegmentIndex].position);
      final p2 = _toScreen(activePath!.nodes[currentSegmentIndex + 1].position);
      final t = animationValue;
      final dotPos = Offset(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
      canvas.drawCircle(
        dotPos,
        5,
        Paint()..color = const Color(0xFF00E5FF),
      );
      canvas.drawCircle(
        dotPos,
        8,
        Paint()
          ..color = const Color(0xFF00E5FF).withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Direction arrows on path
    for (int i = currentSegmentIndex; i < activePath!.nodes.length - 1; i++) {
      final p1 = _toScreen(activePath!.nodes[i].position);
      final p2 = _toScreen(activePath!.nodes[i + 1].position);
      _drawArrow(canvas, p1, p2, const Color(0xFF00E5FF));
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color) {
    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final dir = to - from;
    final len = dir.distance;
    if (len < 20) return;

    final norm = dir / len;
    final perp = Offset(-norm.dy, norm.dx);

    final arrowSize = 5.0;
    final tip = mid + norm * arrowSize;
    final left = mid - norm * arrowSize + perp * arrowSize * 0.6;
    final right = mid - norm * arrowSize - perp * arrowSize * 0.6;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.7)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawNodes(Canvas canvas) {
    for (final node in nodes) {
      final pos = _toScreen(node.position);
      final isStart = node.id == startNodeId;
      final isDest = node.id == destNodeId;
      final isSelected = node.id == selectedNodeId;
      final isOnPath = activePath?.nodes.any((n) => n.id == node.id) ?? false;

      double radius;
      Color color;
      Color borderColor;

      switch (node.type) {
        case NodeType.room:
          radius = 5;
          color = const Color(0xFF42A5F5);
          borderColor = const Color(0xFF1565C0);
        case NodeType.lab:
          radius = 6;
          color = const Color(0xFFAB47BC);
          borderColor = const Color(0xFF7B1FA2);
        case NodeType.office:
          radius = 6;
          color = const Color(0xFF66BB6A);
          borderColor = const Color(0xFF2E7D32);
        case NodeType.washroom:
          radius = 5;
          color = const Color(0xFF26C6DA);
          borderColor = const Color(0xFF00838F);
        case NodeType.stairs:
          radius = 6;
          color = const Color(0xFFFFA726);
          borderColor = const Color(0xFFEF6C00);
        case NodeType.lift:
          radius = 6;
          color = const Color(0xFF7E57C2);
          borderColor = const Color(0xFF4527A0);
        case NodeType.entrance:
          radius = 7;
          color = const Color(0xFFEF5350);
          borderColor = const Color(0xFFC62828);
        case NodeType.corridor:
        case NodeType.junction:
          radius = 3;
          color = const Color(0xFF546E7A);
          borderColor = const Color(0xFF37474F);
      }

      if (isStart) {
        radius = 9;
        color = const Color(0xFF4CAF50);
        borderColor = const Color(0xFFFFFFFF);
      }
      if (isDest) {
        radius = 9;
        color = const Color(0xFFFF5252);
        borderColor = const Color(0xFFFFFFFF);
      }
      if (isSelected && !isStart && !isDest) {
        radius += 2;
        borderColor = const Color(0xFFFFD740);
      }
      if (isOnPath && !isStart && !isDest) {
        radius += 1;
        borderColor = const Color(0xFF00E5FF);
      }

      // Glow for important nodes
      if (isStart || isDest || isSelected) {
        canvas.drawCircle(
          pos,
          radius + 6,
          Paint()..color = color.withOpacity(0.2),
        );
      }

      // Fill
      canvas.drawCircle(pos, radius, Paint()..color = color);

      // Border
      canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Icon overlay for special types
      if (node.type == NodeType.stairs || node.type == NodeType.lift ||
          node.type == NodeType.washroom || node.type == NodeType.entrance) {
        _drawNodeIcon(canvas, pos, node.type);
      }
    }
  }

  void _drawNodeIcon(Canvas canvas, Offset pos, NodeType type) {
    final textStyle = ui.TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 8,
      fontWeight: FontWeight.bold,
    );

    String icon;
    switch (type) {
      case NodeType.stairs:
        icon = '⇡';
      case NodeType.lift:
        icon = '⇕';
      case NodeType.washroom:
        icon = 'WC';
      case NodeType.entrance:
        icon = '⌂';
      default:
        return;
    }

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 7,
    ))
      ..pushStyle(textStyle)
      ..addText(icon);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 20));

    canvas.drawParagraph(
      paragraph,
      Offset(pos.dx - 10, pos.dy - 4),
    );
  }

  void _drawLabels(Canvas canvas) {
    for (final node in nodes) {
      if (node.type == NodeType.corridor && node.type != NodeType.junction) continue;

      final pos = _toScreen(node.position);
      final isOnPath = activePath?.nodes.any((n) => n.id == node.id) ?? false;
      final isStartOrDest = node.id == startNodeId || node.id == destNodeId;

      if (!isStartOrDest && !isOnPath && !node.isDestination) continue;

      String label;
      double fontSize;
      Color textColor;

      if (isStartOrDest) {
        label = node.displayName;
        fontSize = 10;
        textColor = Colors.white;
      } else if (isOnPath) {
        label = node.displayName;
        fontSize = 8;
        textColor = const Color(0xFF80DEEA);
      } else {
        label = node.displayName;
        fontSize = 7;
        textColor = const Color(0xFF78909C);
      }

      final textStyle = ui.TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: isStartOrDest ? FontWeight.bold : FontWeight.normal,
      );

      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.center,
        maxLines: 1,
      ))
        ..pushStyle(textStyle)
        ..addText(label);

      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 120));

      // Background
      if (isStartOrDest) {
        final textWidth = paragraph.longestLine;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(pos.dx, pos.dy + 15),
              width: textWidth + 8,
              height: 14,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xCC000000),
        );
      }

      canvas.drawParagraph(
        paragraph,
        Offset(pos.dx - 60, pos.dy + 9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) => true;
}
