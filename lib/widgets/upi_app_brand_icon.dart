import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Home-screen-style marks for UPI app shortcuts (not Material fallbacks).
class UpiAppBrandIcon extends StatelessWidget {
  const UpiAppBrandIcon({super.key, required this.appId, this.size = 32});

  final String appId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _painterFor(appId)),
    );
  }
}

CustomPainter _painterFor(String appId) {
  switch (appId) {
    case 'gpay':
      return const _GpayIconPainter();
    case 'phonepe':
      return const _PhonePeIconPainter();
    case 'paytm':
      return const _PaytmIconPainter();
    case 'bhim':
      return const _BhimIconPainter();
    default:
      return const _GpayIconPainter();
  }
}

void _squircle(Canvas canvas, Size size, Color color) {
  final r = Radius.circular(size.width * 0.22);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Offset.zero & size, r),
    Paint()..color = color,
  );
}

class _GpayIconPainter extends CustomPainter {
  const _GpayIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _squircle(canvas, size, const Color(0xFFF1F3F4));
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.28;
    final stroke = size.width * 0.11;
    final rect = Rect.fromCircle(center: c, radius: radius);

    void arc(Color color, double start, double sweep) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Google G: blue bar + four-color ring.
    arc(const Color(0xFFEA4335), -math.pi * 0.85, math.pi * 0.7);
    arc(const Color(0xFFFBBC05), math.pi * 0.15, math.pi * 0.55);
    arc(const Color(0xFF34A853), math.pi * 0.7, math.pi * 0.55);
    arc(const Color(0xFF4285F4), -math.pi * 0.15, math.pi * 0.45);

    final bar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRRect(
      RRect.fromLTRBR(
        c.dx,
        c.dy - stroke * 0.48,
        c.dx + radius + stroke * 0.15,
        c.dy + stroke * 0.48,
        Radius.circular(stroke * 0.2),
      ),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PhonePeIconPainter extends CustomPainter {
  const _PhonePeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _squircle(canvas, size, const Color(0xFF5F259F));
    final w = size.width;
    final h = size.height;
    final white = Paint()..color = Colors.white;

    // Stylized upright phone (PhonePe app mark).
    final phone = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.30, h * 0.18, w * 0.40, h * 0.64),
      Radius.circular(w * 0.08),
    );
    canvas.drawRRect(phone, white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.36, h * 0.26, w * 0.28, h * 0.38),
        Radius.circular(w * 0.04),
      ),
      Paint()..color = const Color(0xFF5F259F),
    );
    canvas.drawCircle(Offset(w * 0.50, h * 0.72), w * 0.035, white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PaytmIconPainter extends CustomPainter {
  const _PaytmIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _squircle(canvas, size, const Color(0xFF00BAF2));
    final tp = TextPainter(
      text: TextSpan(
        text: 'Paytm',
        style: TextStyle(
          color: const Color(0xFF012B72),
          fontWeight: FontWeight.w800,
          fontSize: size.width * 0.22,
          letterSpacing: -0.4,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.86);
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BhimIconPainter extends CustomPainter {
  const _BhimIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    _squircle(canvas, size, const Color(0xFFF36F21));
    final tp = TextPainter(
      text: TextSpan(
        text: 'BHIM',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size.width * 0.24,
          letterSpacing: 0.2,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.9);
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
