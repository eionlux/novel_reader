import 'dart:io';

import 'package:novel_reader/services/chapter_parser.dart';
import 'package:novel_reader/services/text_codec.dart';

void main() {
  final dir = Directory(r'C:\Users\Plus\Documents\丹青阅读\书库');
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.toLowerCase().endsWith('.txt')) continue;
    final decoded = decodeTextBytes(f.readAsBytesSync());
    final parsed = parseBookText(decoded.text, fallbackTitle: f.uri.pathSegments.last);
    stdout.writeln(f.uri.pathSegments.last);
    stdout.writeln('  encoding=${decoded.encoding} title=${parsed.title} author=${parsed.author}');
    stdout.writeln('  chapters=${parsed.chapters.length} chars=${parsed.charCount}');
    for (final c in parsed.chapters) {
      stdout.writeln('    ${c.index + 1}. ${c.title}  (${c.text.length} 字)');
    }
  }
}
