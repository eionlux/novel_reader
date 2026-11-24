import 'dart:io';

import 'package:flutter/material.dart';

import '../models/book.dart';
import 'app_theme.dart';

/// 书籍封面：有真实封面图时显示图片，否则回退到「渐变 + 书名」的样式封面。
class BookCover extends StatelessWidget {
  final Book book;
  final double radius;
  final double titleSize;
  final bool showProgress;

  BookCover({
    super.key,
    required this.book,
    this.radius = 10,
    this.titleSize = 16,
    this.showProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.72,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: book.coverPath.isEmpty ? _fallbackCover() : _photoCover(context),
      ),
    );
  }

  Widget _photoCover(BuildContext context) {
    final percent = (book.progress * 100).clamp(0, 100);
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(book.coverPath),
          fit: BoxFit.cover,
          cacheWidth: 700,
          errorBuilder: (context, error, stackTrace) => _fallbackCover(),
        ),
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              book.format.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ),
        ),
        if (showProgress)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(8, 16, 8, 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.62),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    percent <= 0 ? '未开始' : '已读 ${percent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                    ),
                  ),
                  SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: book.progress.clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: Colors.white.withValues(alpha: 0.35),
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallbackCover() {
    final hue = (book.filePath.hashCode.abs() % 360).toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.34, 0.93).toColor();
    final c2 = HSLColor.fromAHSL(1, hue + 24, 0.38, 0.86).toColor();
    final percent = (book.progress * 100).clamp(0, 100);
    const ink = Color(0xFF2B2A28);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              book.format.toUpperCase(),
              style: TextStyle(
                fontSize: 8.5,
                letterSpacing: 2,
                color: ink.withValues(alpha: 0.35),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Text(
              book.title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink.withValues(alpha: 0.86),
                fontSize: titleSize,
                height: 1.4,
                fontFamily: 'KaiTi',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (showProgress)
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    percent <= 0 ? '未开始' : '已读 ${percent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: ink.withValues(alpha: 0.45),
                    ),
                  ),
                  SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: book.progress.clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: Colors.white.withValues(alpha: 0.55),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.accent.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
