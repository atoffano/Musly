import 'package:flutter/material.dart';

/// Pixel-perfect vector YouTube Music logo icon widget.
class YouTubeMusicLogo extends StatelessWidget {
  final double size;

  const YouTubeMusicLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _YouTubeMusicLogoPainter(),
      ),
    );
  }
}

class _YouTubeMusicLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer red circle
    final bgPaint = Paint()
      ..color = const Color(0xFFFF0000)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, bgPaint);

    // Inner concentric white ring
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius * 0.62, ringPaint);

    // Central white play triangle
    final triPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final triHeight = radius * 0.46;
    final triWidth = triHeight * 0.88;
    final path = Path()
      ..moveTo(center.dx - triWidth * 0.38, center.dy - triHeight / 2)
      ..lineTo(center.dx + triWidth * 0.62, center.dy)
      ..lineTo(center.dx - triWidth * 0.38, center.dy + triHeight / 2)
      ..close();

    canvas.drawPath(path, triPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
