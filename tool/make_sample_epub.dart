// 生成一本示例 EPUB 到书库目录，便于直接体验 EPUB 阅读
// 运行：dart run tool\make_sample_epub.dart
import 'dart:io';

import 'format_check.dart' show buildSampleEpub;

void main() {
  final home = Platform.environment['USERPROFILE'] ?? '.';
  final dir = Directory('$home\\Documents\\丹青阅读\\书库');
  dir.createSync(recursive: true);
  final file = File('${dir.path}\\格式演示.epub');
  file.writeAsBytesSync(buildSampleEpub());
  print('已生成 ${file.path}（${file.lengthSync()} 字节）');
}
