import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/reader_settings.dart';

/// 阅读页纸张背景：底色 + 程序化纸纹，不依赖图片资源，任何分辨率都清晰。
class PaperBackground extends StatelessWidget {
  final ReaderSkin skin;
  final Widget child;

  const PaperBackground({super.key, required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaperPainter(skin),
      isComplex: true,
      willChange: false,
      child: child,
    );
  }
}

class _PaperPainter extends CustomPainter {
  final ReaderSkin skin;
  _PaperPainter(this.skin);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = skin.background);

    switch (skin.texture) {
      case PaperTexture.none:
        if (skin.id == 'night') _paintVignette(canvas, size, 0.16);
        return;
      case PaperTexture.fiber:
        _paintFiber(canvas, size, 0.055);
        _paintVignette(canvas, size, 0.035);
      case PaperTexture.laid:
        _paintLaid(canvas, size);
        _paintVignette(canvas, size, 0.04);
      case PaperTexture.oldPage:
        _paintFiber(canvas, size, 0.06);
        _paintStains(canvas, size, 7, 0.07);
        _paintEdgeShade(canvas, size, 0.06);
      case PaperTexture.kraft:
        _paintKraft(canvas, size);
        _paintVignette(canvas, size, 0.05);
      case PaperTexture.ruled:
        _paintRuled(canvas, size);
      case PaperTexture.grid:
        _paintGrid(canvas, size);
      case PaperTexture.newsprint:
        _paintNewsprint(canvas, size);
      case PaperTexture.inkWash:
        _paintInk(canvas, size);
        _paintVignette(canvas, size, 0.035);
    }
  }

  double _rand(int seed) {
    final x = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  void _paintFiber(Canvas canvas, Size size, double alpha) {
    final base = _mix(skin.background, skin.foreground, 0.55);
    final paint = Paint()
      ..color = base.withValues(alpha: alpha)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final count = (size.width * size.height / 1600).round().clamp(70, 260);
    for (var i = 0; i < count; i++) {
      final x = _rand(i * 7 + 1) * size.width;
      final y = _rand(i * 13 + 3) * size.height;
      final len = 4 + _rand(i * 17 + 5) * 18;
      final angle = (_rand(i * 23 + 7) - 0.5) * 0.5;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + len * math.cos(angle), y + len * math.sin(angle)),
        paint,
      );
    }
    final dotPaint = Paint()..color = base.withValues(alpha: alpha * 0.6);
    for (var i = 0; i < count / 5; i++) {
      final x = _rand(i * 31 + 9) * size.width;
      final y = _rand(i * 37 + 11) * size.height;
      canvas.drawCircle(Offset(x, y), 0.7 + _rand(i * 41) * 0.8, dotPaint);
    }
  }

  void _paintLaid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _mix(
        skin.background,
        skin.foreground,
        0.5,
      ).withValues(alpha: 0.045)
      ..strokeWidth = 0.8;
    for (var y = 18.0; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var x = 16.0; x < size.width; x += 74) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  void _paintStains(Canvas canvas, Size size, int count, double alpha) {
    for (var i = 0; i < count; i++) {
      final center = Offset(
        _rand(i * 53 + 21) * size.width,
        _rand(i * 59 + 23) * size.height,
      );
      final radius =
          ((30 + _rand(i * 61 + 25) * 90) * (size.width / 460).clamp(0.7, 1.8))
              .toDouble();
      final color = _mix(
        skin.background,
        const Color(0xFF8B6034),
        0.45 + _rand(i * 67) * 0.2,
      ).withValues(alpha: alpha);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
      canvas.drawCircle(
        center,
        radius * 0.45,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  void _paintKraft(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _mix(
        skin.background,
        skin.foreground,
        0.45,
      ).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var y = 8.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 1), line);
    }
    final speck = Paint()
      ..color = _mix(
        skin.background,
        skin.foreground,
        0.65,
      ).withValues(alpha: 0.08);
    for (var i = 0; i < 120; i++) {
      final x = _rand(i * 71 + 3) * size.width;
      final y = _rand(i * 73 + 5) * size.height;
      canvas.drawCircle(Offset(x, y), 0.6 + _rand(i * 79) * 1.2, speck);
    }
  }

  void _paintRuled(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF6D8AA3).withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var y = 40.0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final margin = Paint()
      ..color = const Color(0xFFBE6A5E).withValues(alpha: 0.14)
      ..strokeWidth = 1.4;
    canvas.drawLine(const Offset(46, 0), Offset(46, size.height), margin);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF8E9A85).withValues(alpha: 0.14)
      ..strokeWidth = 0.9;
    const step = 26.0;
    for (var y = 18.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var x = 18.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  void _paintNewsprint(Canvas canvas, Size size) {
    final tint = Paint()
      ..color = const Color(0xFF7A7365).withValues(alpha: 0.05);
    for (var i = 0; i < 90; i++) {
      final x = _rand(i * 83 + 7) * size.width;
      final y = _rand(i * 89 + 11) * size.height;
      canvas.drawCircle(Offset(x, y), 0.6 + _rand(i * 97) * 1.6, tint);
    }
    final column = Paint()
      ..color = const Color(0xFF6F6A5E).withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (var x = 50.0; x < size.width; x += 120) {
      canvas.drawLine(Offset(x, 20), Offset(x, size.height - 20), column);
    }
    _paintVignette(canvas, size, 0.04);
  }

  void _paintInk(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF5B6B73),
      const Color(0xFF8A9AA0),
      const Color(0xFF6B6257),
    ];
    for (var i = 0; i < 5; i++) {
      final center = Offset(
        _rand(i * 101 + 3) * size.width,
        _rand(i * 103 + 7) * size.height,
      );
      final radius = 80 + _rand(i * 107) * 160;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors[i % colors.length].withValues(alpha: 0.045),
              colors[i % colors.length].withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    _paintFiber(canvas, size, 0.025);
  }

  void _paintVignette(Canvas canvas, Size size, double alpha) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: alpha),
          ],
          stops: const [0.68, 1.0],
        ).createShader(rect),
    );
  }

  void _paintEdgeShade(Canvas canvas, Size size, double alpha) {
    final paint = Paint()
      ..color = const Color(0xFF6E5436).withValues(alpha: alpha);
    const width = 16.0;
    final left = Paint()
      ..shader = LinearGradient(
        colors: [paint.color, Colors.transparent],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, width * 3, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, width * 3, size.height), left);
    final right = Paint()
      ..shader =
          LinearGradient(
            colors: [Colors.transparent, paint.color],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(
            Rect.fromLTWH(size.width - width * 3, 0, width * 3, size.height),
          );
    canvas.drawRect(
      Rect.fromLTWH(size.width - width * 3, 0, width * 3, size.height),
      right,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.skin.id != skin.id;
}
