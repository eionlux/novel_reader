import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 保留上一页与新页两份内容，按翻页风格分别做变换的翻页容器。
class PageFlipTransition extends StatefulWidget {
  final String pageId;
  final Widget child;
  final String style;
  final bool forward;
  final Duration duration;
  final Color backgroundColor;

  const PageFlipTransition({
    super.key,
    required this.pageId,
    required this.child,
    required this.style,
    required this.forward,
    required this.duration,
    required this.backgroundColor,
  });

  @override
  State<PageFlipTransition> createState() => _PageFlipTransitionState();
}

class _PageFlipTransitionState extends State<PageFlipTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _previous;
  String? _previousId;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            mounted &&
            _previous != null) {
          setState(() => _previous = null);
        }
      });
  }

  @override
  void didUpdateWidget(covariant PageFlipTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.pageId != widget.pageId) {
      if (widget.style == 'none' || widget.duration == Duration.zero) {
        _controller.value = 1;
        _previous = null;
        _previousId = null;
      } else {
        _previous = oldWidget.child;
        _previousId = oldWidget.pageId;
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _t => widget.style == 'none' ? 1 : _controller.value;

  @override
  Widget build(BuildContext context) {
    if (widget.style == 'none' || _previous == null) {
      return ClipRect(child: widget.child);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _t;
        final oldPage = KeyedSubtree(
          key: ValueKey('old|$_previousId'),
          child: _previous!,
        );
        final newPage = KeyedSubtree(
          key: ValueKey('new|${widget.pageId}'),
          child: widget.child,
        );
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: widget.backgroundColor),
              ..._buildPages(oldPage, newPage, t),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPages(Widget oldPage, Widget newPage, double t) {
    final sign = widget.forward ? 1.0 : -1.0;
    final easeOut = Curves.easeOutCubic.transform(t);
    final easeInOut = Curves.easeInOutCubic.transform(t);
    switch (widget.style) {
      case 'fade':
        return [
          Opacity(opacity: 1 - easeOut, child: oldPage),
          Opacity(opacity: easeOut, child: newPage),
        ];
      case 'slide':
        return [
          FractionalTranslation(
            translation: Offset(-0.12 * sign * easeOut, 0),
            child: Opacity(opacity: 1 - easeInOut, child: oldPage),
          ),
          FractionalTranslation(
            translation: Offset(0.22 * sign * (1 - easeOut), 0),
            child: newPage,
          ),
        ];
      case 'cover':
        return [
          oldPage,
          FractionalTranslation(
            translation: Offset(sign * (1 - easeOut), 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: Offset(-sign * 10, 0),
                  ),
                ],
              ),
              child: newPage,
            ),
          ),
        ];
      case 'push':
        return [
          FractionalTranslation(
            translation: Offset(-0.38 * sign * easeInOut, 0),
            child: oldPage,
          ),
          FractionalTranslation(
            translation: Offset(sign * 0.38 * (1 - easeOut), 0),
            child: newPage,
          ),
        ];
      case 'cube':
        return [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateY(-math.pi / 2 * sign * easeInOut),
            child: Opacity(opacity: 1 - t, child: oldPage),
          ),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateY(math.pi / 2 * sign * (1 - easeOut)),
            child: Opacity(opacity: easeOut, child: newPage),
          ),
        ];
      case 'flip':
        return [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(-math.pi * sign * easeInOut),
            child: Opacity(opacity: math.max(0.0, 1 - t * 1.8), child: oldPage),
          ),
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateY(math.pi * sign * (1 - easeOut)),
            child: Opacity(opacity: easeOut, child: newPage),
          ),
        ];
      case 'curl':
        return [
          newPage,
          ClipPath(
            clipper: _PageCurlClipper(progress: easeInOut, forward: sign > 0),
            child: Transform(
              alignment: sign > 0
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(-0.08 * sign * easeInOut),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: Offset(-sign * 6, 2),
                    ),
                  ],
                ),
                child: oldPage,
              ),
            ),
          ),
          IgnorePointer(
            child: Opacity(
              opacity: 0.22 * math.sin(math.pi * t),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    begin: sign > 0
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    end: sign > 0 ? Alignment.center : Alignment.centerLeft,
                  ),
                ),
              ),
            ),
          ),
        ];
      case 'zoom':
        return [
          Transform.scale(
            scale: 1 + 0.08 * easeInOut,
            child: Opacity(opacity: 1 - easeOut, child: oldPage),
          ),
          Transform.scale(
            scale: 0.84 + 0.16 * easeOut,
            child: Opacity(opacity: easeOut, child: newPage),
          ),
        ];
      case 'blur':
        return [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 7 * easeInOut,
              sigmaY: 7 * easeInOut,
              tileMode: TileMode.decal,
            ),
            child: Opacity(opacity: 1 - easeOut, child: oldPage),
          ),
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: 5 * (1 - easeOut),
              sigmaY: 5 * (1 - easeOut),
              tileMode: TileMode.decal,
            ),
            child: Opacity(opacity: easeOut, child: newPage),
          ),
        ];
      case 'vertical':
        return [
          FractionalTranslation(
            translation: Offset(0, -0.18 * sign * easeOut),
            child: Opacity(opacity: 1 - easeInOut, child: oldPage),
          ),
          FractionalTranslation(
            translation: Offset(0, sign * (1 - easeOut)),
            child: newPage,
          ),
        ];
      case 'rotate':
        return [
          Transform.rotate(
            angle: 0.035 * sign * easeOut,
            child: FractionalTranslation(
              translation: Offset(-0.14 * sign * easeOut, 0),
              child: Opacity(opacity: 1 - easeInOut, child: oldPage),
            ),
          ),
          Transform.rotate(
            angle: -0.04 * sign * (1 - easeOut),
            child: FractionalTranslation(
              translation: Offset(
                0.18 * sign * (1 - easeOut),
                0.02 * sign * (1 - easeOut),
              ),
              child: Opacity(opacity: easeOut, child: newPage),
            ),
          ),
        ];
      case 'paper':
        return [
          FractionalTranslation(
            translation: Offset(-0.06 * sign * easeOut, 0),
            child: Opacity(opacity: 1 - easeInOut, child: oldPage),
          ),
          Transform.translate(
            offset: Offset(0, 0),
            child: Transform.rotate(
              angle: -0.06 * sign * (1 - easeOut),
              alignment: sign > 0
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: FractionalTranslation(
                translation: Offset(
                  0.26 * sign * (1 - easeOut),
                  0.05 * (1 - easeOut),
                ),
                child: Opacity(opacity: easeOut, child: newPage),
              ),
            ),
          ),
        ];
      default:
        return [
          Opacity(opacity: 1 - easeOut, child: oldPage),
          Opacity(opacity: easeOut, child: newPage),
        ];
    }
  }
}

class _PageCurlClipper extends CustomClipper<Path> {
  final double progress;
  final bool forward;

  _PageCurlClipper({required this.progress, required this.forward});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (forward) {
      // 从右往左卷走旧页
      final edge = size.width * (1 - progress);
      final bend = size.height * 0.14 * math.sin(math.pi * progress);
      path.moveTo(0, 0);
      path.lineTo(edge, 0);
      path.quadraticBezierTo(edge - bend, size.height / 2, edge, size.height);
      path.lineTo(0, size.height);
    } else {
      // 反向阅读时从左往右卷走旧页
      final edge = size.width * progress;
      final bend = size.height * 0.14 * math.sin(math.pi * progress);
      path.moveTo(size.width, 0);
      path.lineTo(edge, 0);
      path.quadraticBezierTo(edge + bend, size.height / 2, edge, size.height);
      path.lineTo(size.width, size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _PageCurlClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.forward != forward;
}
