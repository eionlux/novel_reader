import 'dart:io';

import '../models/book.dart';
import 'chapter_parser.dart';
import 'epub_parser.dart';
import 'mobi_parser.dart';
import 'text_codec.dart';

/// 支持的电子书格式
const List<String> kSupportedExtensions = [
  'txt',
  'md',
  'epub',
  'mobi',
  'azw3',
  'azw',
];

const String kFormatDescription = 'TXT / EPUB / MOBI / AZW3';

String extensionOf(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isSupportedBookFile(String path) =>
    kSupportedExtensions.contains(extensionOf(path));

/// 统一解析入口：按扩展名分派到对应解析器，产出统一的 ParsedBook。
Future<ParsedBook?> parseBookFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final ext = extensionOf(path);
  final baseName = file.uri.pathSegments.last.replaceAll(
    RegExp(r'\.[^.]+$'),
    '',
  );
  final bytes = await file.readAsBytes();

  switch (ext) {
    case 'txt':
    case 'md':
      final decoded = decodeTextBytes(bytes);
      return parseBookText(decoded.text, fallbackTitle: baseName);
    case 'epub':
      try {
        final epub = EpubParser.parse(bytes);
        if (epub == null) return null;
        return _fromRawChapters(
          epub.title == '未命名' ? baseName : epub.title,
          epub.author,
          epub.chapters,
        );
      } catch (_) {
        return null;
      }
    case 'mobi':
    case 'azw3':
    case 'azw':
      try {
        final mobi = MobiParser.parse(bytes);
        if (mobi == null) return null;
        return parseBookText(
          mobi.text,
          fallbackTitle: mobi.title == '未命名' ? baseName : mobi.title,
          fallbackAuthor: mobi.author,
        );
      } catch (_) {
        return null;
      }
    default:
      return null;
  }
}

ParsedBook _fromRawChapters(String title, String author, List<RawChapter> raw) {
  final chapters = <Chapter>[];
  var acc = 0;
  for (var i = 0; i < raw.length; i++) {
    final text = indentParagraphs(normalizeText(raw[i].text));
    if (text.trim().isEmpty) continue;
    chapters.add(
      Chapter(
        index: chapters.length,
        title: cleanChapterTitle(
          raw[i].title,
          fallbackIndex: chapters.length,
          sourcePath: raw[i].sourcePath,
        ),
        charStart: acc,
        text: text,
      ),
    );
    acc += text.length;
  }
  if (chapters.isEmpty) {
    return ParsedBook(
      title: title,
      author: author,
      chapters: const [],
      charCount: 0,
    );
  }
  return ParsedBook(
    title: title,
    author: author,
    chapters: chapters,
    charCount: acc,
  );
}
