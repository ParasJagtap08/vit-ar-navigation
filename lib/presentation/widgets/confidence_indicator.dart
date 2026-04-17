/// Confidence indicator widget — circular signal strength display.

import 'package:flutter/material.dart';

class ConfidenceIndicator extends StatelessWidget {
  final double confidence;

  const ConfidenceIndicator({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getColor().withOpacity(0.15),
        border: Border.all(color: _getColor(), width: 2),
      ),
      child: Center(
        child: Text(
          '${(confidence * 100).toInt()}',
          style: TextStyle(
            color: _getColor(),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Color _getColor() {
    if (confidence >= 0.7) return const Color(0xFF4CAF50);
    if (confidence >= 0.5) return const Color(0xFFFFC107);
    if (confidence >= 0.3) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }
}
