import 'dart:io';

import 'package:novel_reader/services/chapter_parser.dart';
import 'package:novel_reader/services/text_codec.dart';

void main() {
  final path = r'C:\Users\Plus\Doubao\chats\2026-11-20\new-chat\GBK测试.txt';
  final bytes = File(path).readAsBytesSync();
  final decoded = decodeTextBytes(bytes);
  stdout.writeln('encoding = ${decoded.encoding}, chars = ${decoded.text.length}');
  stdout.writeln('head = ${decoded.text.split('\n').take(4).join(' | ')}');
  final parsed = parseBookText(decoded.text, fallbackTitle: 'GBK测试');
  stdout.writeln('author = ${parsed.author}, chapters = ${parsed.chapters.length}, chars = ${parsed.charCount}');
  for (final c in parsed.chapters) {
    stdout.writeln('  [${c.index}] ${c.title}  start=${c.charStart} len=${c.text.length}');
  }
}
