import 'dart:io';

import 'package:novel_reader/services/chapter_parser.dart';
import 'package:novel_reader/services/epub_parser.dart';

void main() {
  final file = File(r'C:\Users\Plus\AppData\Local\Temp\toc_test.epub');
  final epub = EpubParser.parse(file.readAsBytesSync());
  if (epub == null) {
    print('EPUB 解析失败');
    return;
  }
  for (var i = 0; i < epub.chapters.length; i++) {
    final raw = epub.chapters[i];
    final cleaned = cleanChapterTitle(
      raw.title,
      fallbackIndex: i,
      sourcePath: raw.sourcePath,
    );
    print('RAW=${raw.title} | SRC=${raw.sourcePath} | CLEAN=$cleaned');
  }
  print('--- direct ---');
  for (final title in [
    'C H A P T E R - 1',
    'CHAPTER-1',
    'Chapter',
    'Cave',
    'chapter_01.xhtml',
    'contents',
    '001.xhtml',
  ]) {
    print('$title => ${cleanChapterTitle(title, fallbackIndex: 2)}');
  }
}
