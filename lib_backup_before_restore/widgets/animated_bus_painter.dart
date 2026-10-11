import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedBusPainter extends CustomPainter {
  final double animationValue;

  AnimatedBusPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 1. Draw Sky Background
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.blue.shade100, Colors.blue.shade50, Colors.white],
      ).createShader(Rect.fromLTWH(0, 0, width, height * 0.5));
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height * 0.5), skyPaint);

    // 2. Draw Distant City Silhouette Architecture
    final buildingPaint = Paint()..color = Colors.blue.shade50.withOpacity(0.5);
    final buildingPath = Path()
      ..moveTo(0, height * 0.45)
      ..lineTo(width * 0.1, height * 0.3)
      ..lineTo(width * 0.15, height * 0.3)
      ..lineTo(width * 0.18, height * 0.35)
      ..lineTo(width * 0.25, height * 0.25)
      ..lineTo(width * 0.32, height * 0.38)
      ..lineTo(width * 0.4, height * 0.2)
      ..lineTo(width * 0.48, height * 0.4)
      ..lineTo(width * 0.6, height * 0.28)
      ..lineTo(width * 0.7, height * 0.42)
      ..lineTo(width * 0.8, height * 0.33)
      ..lineTo(width * 0.9, height * 0.45)
      ..lineTo(width, height * 0.45)
      ..lineTo(width, height * 0.5)
      ..lineTo(0, height * 0.5)
      ..close();
    canvas.drawPath(buildingPath, buildingPaint);

    // 3. Draw Green Fields Ground Landscape
    final fieldPaint = Paint()..color = const Color(0xFFF1F7ED);
    canvas.drawRect(Rect.fromLTWH(0, height * 0.45, width, height * 0.55), fieldPaint);

    // 4. Draw Winding Perspective Highway Road Path Layout
    final roadPaint = Paint()
      ..color = const Color(0xFFBCC1C9)
      ..style = PaintingStyle.fill;

    final roadPath = Path()
      ..moveTo(width * 0.08, height * 0.45) // Starting point at the horizon (Left)
      ..quadraticBezierTo(
        width * 0.05, height * 0.55,        // Curve pull point
        width * 0.3, height * 0.65,         // Middle curve sweep
      )
      ..quadraticBezierTo(
        width * 0.7, height * 0.78,         // Lower curve pull point
        width * 0.5, height,                // Broad foreground road opening
      )
      ..lineTo(width, height)               // Right side expansion boundary
      ..quadraticBezierTo(
        width * 0.9, height * 0.72,
        width * 0.45, height * 0.62,
      )
      ..quadraticBezierTo(
        width * 0.15, height * 0.52,
        width * 0.12, height * 0.45,
      )
      ..close();
    canvas.drawPath(roadPath, roadPaint);

    // 5. Draw Yellow Central Divider Dash Lanes
    final centerDividerPaint = Paint()
      ..color = const Color(0xFFFBB03B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    final dividerPath = Path()
      ..moveTo(width * 0.1, height * 0.45)
      ..quadraticBezierTo(width * 0.1, height * 0.54, width * 0.35, height * 0.635)
      ..quadraticBezierTo(width * 0.75, height * 0.77, width * 0.72, height);
    canvas.drawPath(dividerPath, centerDividerPaint);

    // 6. Calculate Dynamic Bus Path Coordinates (Simulating driving closer over time)
    // Map animation progress value (0.0 to 1.0) into exponential curves
    double scale = math.pow(animationValue, 2) * 0.85 + 0.15; 
    
    // Path positions derived using progressive Bezier math coordinates
    double busX = width * 0.1 + (width * 0.42 * animationValue);
    double busY = height * 0.46 + (height * 0.32 * math.pow(animationValue, 1.5));

    // Shift origin context canvas mapping to place the bus dynamically
    canvas.save();
    canvas.translate(busX, busY);
    canvas.scale(scale);

    // 7. Draw the Canvas Bus Silhouette
    final busBodyPaint = Paint()..color = const Color(0xFFFBB03B);
    final busWindowPaint = Paint()..color = const Color(0xFF1E293B);
    final wheelPaint = Paint()..color = const Color(0xFF0F172A);

    // Main Body Box Shell Panel
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-70, -40, 140, 60),
        const Radius.circular(8),
      ),
      busBodyPaint,
    );

    // Front Windshield Glass
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(40, -35, 25, 25),
        const Radius.circular(4),
      ),
      busWindowPaint,
    );

    // Side Windows Array
    for (int i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(-60 + (i * 24), -35, 18, 20),
        busWindowPaint,
      );
    }

    // Black Radial Tires
    canvas.drawCircle(const Offset(-40, 20), 12, wheelPaint);
    canvas.drawCircle(const Offset(35, 20), 12, wheelPaint);
    canvas.drawCircle(const Offset(-40, 20), 5, Paint()..color = Colors.grey);
    canvas.drawCircle(const Offset(35, 20), 5, Paint()..color = Colors.grey);

    // Headlight Flares
    final lightPaint = Paint()..color = Colors.yellow.shade200.withOpacity(0.6);
    canvas.drawCircle(const Offset(68, 5), 6, lightPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AnimatedBusPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
