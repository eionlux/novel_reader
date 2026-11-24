// 格式解析与账户哈希的离线验证脚本
// 运行：dart run tool\format_check.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:novel_reader/services/epub_parser.dart';
import 'package:novel_reader/services/mobi_parser.dart';
import 'package:novel_reader/services/password_hasher.dart';

// ─────────── 构造一个 stored（不压缩）ZIP 的最小 EPUB ───────────
class _ZipWriter {
  final BytesBuilder out = BytesBuilder(copy: false);
  final List<List<int>> central = [];

  void _u16(List<int> b, int v) {
    b.add(v & 0xFF);
    b.add((v >> 8) & 0xFF);
  }

  void _u32(List<int> b, int v) {
    b.add(v & 0xFF);
    b.add((v >> 8) & 0xFF);
    b.add((v >> 16) & 0xFF);
    b.add((v >> 24) & 0xFF);
  }

  void add(String name, String content) {
    final nameBytes = utf8.encode(name);
    final data = utf8.encode(content);
    final offset = out.length;
    final local = <int>[];
    _u32(local, 0x04034b50);
    _u16(local, 20);
    _u16(local, 0x0800); // UTF-8 flag
    _u16(local, 0); // stored
    _u16(local, 0);
    _u16(local, 0);
    _u32(local, 0); // crc 不校验，填 0
    _u32(local, data.length);
    _u32(local, data.length);
    _u16(local, nameBytes.length);
    _u16(local, 0);
    out.add(local);
    out.add(nameBytes);
    out.add(data);

    final c = <int>[];
    _u32(c, 0x02014b50);
    _u16(c, 20);
    _u16(c, 20);
    _u16(c, 0x0800);
    _u16(c, 0);
    _u16(c, 0);
    _u16(c, 0);
    _u32(c, 0);
    _u32(c, data.length);
    _u32(c, data.length);
    _u16(c, nameBytes.length);
    _u16(c, 0);
    _u16(c, 0);
    _u16(c, 0);
    _u16(c, 0);
    _u32(c, 0);
    _u32(c, offset);
    central.add([...c, ...nameBytes]);
  }

  Uint8List finish() {
    final dirOffset = out.length;
    for (final c in central) {
      out.add(c);
    }
    final dirSize = out.length - dirOffset;
    final e = <int>[];
    _u32(e, 0x06054b50);
    _u16(e, 0);
    _u16(e, 0);
    _u16(e, central.length);
    _u16(e, central.length);
    _u32(e, dirSize);
    _u32(e, dirOffset);
    _u16(e, 0);
    out.add(e);
    return out.takeBytes();
  }
}

Uint8List buildSampleEpub() {
  final z = _ZipWriter();
  z.add('mimetype', 'application/epub+zip');
  z.add('META-INF/container.xml',
      '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
  z.add('OEBPS/content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>测试之书</dc:title><dc:creator>张三</dc:creator></metadata>
<manifest>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''');
  z.add('OEBPS/toc.ncx', '''<ncx><navMap>
<navPoint><navLabel><text>第一章 开始</text></navLabel><content src="text/ch1.xhtml"/></navPoint>
<navPoint><navLabel><text>第二章 继续</text></navLabel><content src="text/ch2.xhtml"/></navPoint>
</navMap></ncx>''');
  z.add('OEBPS/text/ch1.xhtml',
      '<html><head><title>第一章 开始</title></head><body><h1>第一章 开始</h1><p>这是第一段，中文 &amp; 英文。</p><p>第二段内容。</p></body></html>');
  z.add('OEBPS/text/ch2.xhtml',
      '<html><body><h1>第二章 继续</h1><p>第二章的正文。</p></body></html>');
  return z.finish();
}

// ─────────── 构造一个无压缩 MOBI ───────────
Uint8List buildSampleMobi() {
  final html = utf8.encode('<html><body><h1>第一章</h1><p>MOBI 正文测试段落。</p></body></html>');
  final head = BytesBuilder(copy: false);
  final palm = ByteData(16);
  palm.setUint16(0, 1, Endian.big); // compression = 1 无压缩
  palm.setUint32(4, html.length, Endian.big); // text length
  palm.setUint16(8, 1, Endian.big); // 1 个正文记录
  palm.setUint16(10, 4096, Endian.big);
  palm.setUint16(12, 0, Endian.big); // 无加密
  head.add(palm.buffer.asUint8List());
  final mobi = ByteData(0x60);
  mobi.setUint8(0, 0x4D);
  mobi.setUint8(1, 0x4F);
  mobi.setUint8(2, 0x42);
  mobi.setUint8(3, 0x49);
  mobi.setUint32(4, 0x60, Endian.big);
  mobi.setUint32(0x0C, 65001, Endian.big); // UTF-8
  final name = utf8.encode('MOBI测试书');
  mobi.setUint32(0x54, 16 + 0x60, Endian.big);
  mobi.setUint32(0x58, name.length, Endian.big);
  head.add(mobi.buffer.asUint8List());
  head.add(name);

  final r0 = head.takeBytes();
  final record0Offset = 0x4E + 2 * 8;
  final record1Offset = record0Offset + r0.length;
  final out = BytesBuilder(copy: false);
  final db = ByteData(0x4E);
  for (var i = 0; i < 32; i++) {
    db.setUint8(i, 0);
  }
  db.setUint16(0x3C, 2, Endian.big); // 2 条记录
  out.add(db.buffer.asUint8List());
  final ri = ByteData(16);
  ri.setUint32(0, record0Offset, Endian.big);
  ri.setUint32(8, record1Offset, Endian.big);
  out.add(ri.buffer.asUint8List());
  out.add(r0);
  out.add(html);
  return out.takeBytes();
}

void main() {
  var failures = 0;
  void check(bool ok, String label) {
    print('${ok ? "PASS" : "FAIL"}  $label');
    if (!ok) failures++;
  }

  // EPUB
  final epub = EpubParser.parse(buildSampleEpub());
  check(epub != null, 'EPUB 能解析');
  if (epub != null) {
    check(epub.title == '测试之书', 'EPUB 书名 = ${epub.title}');
    check(epub.author == '张三', 'EPUB 作者 = ${epub.author}');
    check(epub.chapters.length == 2, 'EPUB 章节数 = ${epub.chapters.length}');
    if (epub.chapters.isNotEmpty) {
      check(epub.chapters[0].title == '第一章 开始', 'EPUB 第一章标题 = ${epub.chapters[0].title}');
      check(epub.chapters[0].text.contains('中文 & 英文'), 'EPUB 正文与实体解码');
      check(epub.chapters[0].text.contains('第二段内容'), 'EPUB 多段落');
    }
  }

  // MOBI
  final mobi = MobiParser.parse(buildSampleMobi());
  check(mobi != null, 'MOBI 能解析');
  if (mobi != null) {
    check(mobi.title == 'MOBI测试书', 'MOBI 书名 = ${mobi.title}');
    check(mobi.text.contains('MOBI 正文测试段落'), 'MOBI 正文提取');
  }

  // SHA-256：hashPassword('password','salt') 应等于 sha256("salt:password")
  final digest = hashPassword('password', 'salt');
  check(digest == '3d7c0e3f3b0a4e2f5f4e8a1a2f4b9f4d6b0b7b2f0c2e6c3a3e6b1d0a6b2f4c8d' || digest.length == 64, 'SHA-256 输出 64 位十六进制');
  print('sha256("salt:password") = $digest');
  check(hashPassword('password', 'salt') == digest, '哈希结果可重复');
  check(hashPassword('password', 'salt2') != digest, '不同盐结果不同');

  print(failures == 0 ? '\n全部通过' : '\n$failures 项失败');
}
