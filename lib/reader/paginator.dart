import 'package:flutter/material.dart';

class TextPage {
  final int start;
  final int end;

  const TextPage(this.start, this.end);

  int get length => end - start;
}

/// 按行切页：一次排版整章，再按行高累计切成页，保证页面不截断半行
List<TextPage> paginate({
  required String text,
  required TextStyle style,
  required double width,
  required double height,
}) {
  if (text.isEmpty) return const [TextPage(0, 0)];
  if (width <= 0 || height <= 0) return [TextPage(0, text.length)];

  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.left,
  )..layout(maxWidth: width);

  final metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) {
    painter.dispose();
    return [TextPage(0, text.length)];
  }

  final tops = <double>[];
  var acc = 0.0;
  for (final m in metrics) {
    tops.add(acc);
    acc += m.height;
  }

  final pages = <TextPage>[];
  var line = 0;
  var cursor = 0;
  while (line < metrics.length) {
    final pageTop = tops[line];
    var lastLine = line;
    while (lastLine + 1 < metrics.length &&
        tops[lastLine + 1] + metrics[lastLine + 1].height - pageTop <=
            height + 0.5) {
      lastLine++;
    }
    final lineBottom = tops[lastLine] + metrics[lastLine].height;
    final probeY = (lineBottom - 1) <= pageTop ? lineBottom : lineBottom - 1;
    var end = painter.getPositionForOffset(Offset(width - 0.5, probeY)).offset;
    if (end <= cursor) end = cursor + 1;
    if (end > text.length) end = text.length;

    // 尽量在段落之间断页：最后 45% 范围内若有换行，就退回到该段末
    if (end < text.length) {
      final span = end - cursor;
      final minKeep = cursor + (span * 0.55).round();
      var cut = -1;
      for (var i = end - 1; i > minKeep; i--) {
        if (text[i] == '\n' && text[i - 1] != '\n') {
          cut = i;
          break;
        }
      }
      if (cut > cursor) end = cut;
    }

    pages.add(TextPage(cursor, end));

    cursor = end;
    while (cursor < text.length && (text[cursor] == '\n')) {
      cursor++;
    }
    line = lastLine + 1;
  }
  if (pages.isEmpty) pages.add(TextPage(0, text.length));
  painter.dispose();
  return pages;
}

int pageIndexForOffset(List<TextPage> pages, int offset) {
  for (var i = 0; i < pages.length; i++) {
    if (offset < pages[i].end) return i;
  }
  return pages.length - 1;
}
