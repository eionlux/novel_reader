import 'dart:convert';
import 'dart:typed_data';

import 'html_text.dart';
import 'text_codec.dart';

class MobiBook {
  final String title;
  final String author;
  final String text;
  const MobiBook({
    required this.title,
    required this.author,
    required this.text,
  });
}

/// MOBI / AZW3 基础解析：PalmDB 记录表 + PalmDOC LZ77 解压 + HTML 剥离。
/// 支持未加密、PalmDOC 压缩（compression=2）或无压缩（=1）的书；
/// HUFF/CDIC 压缩与 DRM 加密的文件会返回 null。
class MobiParser {
  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static MobiBook? parse(Uint8List bytes) {
    if (bytes.length < 78) return null;
    final recordCount = _u16(bytes, 0x3C);
    if (recordCount <= 1) return null;
    final offsets = <int>[];
    for (var i = 0; i < recordCount; i++) {
      final p = 0x4E + i * 8;
      if (p + 4 > bytes.length) return null;
      offsets.add(_u32(bytes, p));
    }
    int recordEnd(int i) =>
        i + 1 < offsets.length ? offsets[i + 1] : bytes.length;
    Uint8List record(int i) => bytes.sublist(offsets[i], recordEnd(i));

    final head = record(0);
    if (head.length < 20) return null;
    final compression = _u16(head, 0);
    final textLength = _u32(head, 4);
    final textRecords = _u16(head, 8);
    final encryption = _u16(head, 12);
    if (encryption != 0) return null; // DRM
    if (compression != 1 && compression != 2) return null; // 不支持 HUFF

    // MOBI 头：编码与全名
    var encoding = 1252;
    String? fullName;
    var author = '佚名';
    if (head.length >= 20 &&
        head[16] == 0x4D &&
        head[17] == 0x4F &&
        head[18] == 0x42 &&
        head[19] == 0x49) {
      encoding = _u32(head, 16 + 0x0C);
      final nameOffset = _u32(head, 16 + 0x54);
      final nameLength = _u32(head, 16 + 0x58);
      if (nameOffset > 0 &&
          nameLength > 0 &&
          nameOffset + nameLength <= head.length) {
        final raw = head.sublist(nameOffset, nameOffset + nameLength);
        fullName = encoding == 65001
            ? utf8.decode(raw, allowMalformed: true)
            : decodeTextBytes(raw).text;
      }
      // EXTH：作者（100）
      final exthFlags = head.length >= 16 + 0x84 ? _u32(head, 16 + 0x80) : 0;
      if (exthFlags & 0x40 != 0) {
        final mobiHeaderLen = _u32(head, 16 + 0x04);
        final exthStart = 16 + mobiHeaderLen;
        if (exthStart + 8 <= head.length &&
            head[exthStart] == 0x45 &&
            head[exthStart + 1] == 0x58 &&
            head[exthStart + 2] == 0x54 &&
            head[exthStart + 3] == 0x48) {
          final count = _u32(head, exthStart + 8);
          var p = exthStart + 12;
          for (var i = 0; i < count && p + 8 <= head.length; i++) {
            final type = _u32(head, p);
            final len = _u32(head, p + 4);
            if (len < 8 || p + len > head.length) break;
            if (type == 100) {
              final raw = head.sublist(p + 8, p + len);
              author =
                  (encoding == 65001
                          ? utf8.decode(raw, allowMalformed: true)
                          : decodeTextBytes(raw).text)
                      .trim();
            }
            p += len;
          }
        }
      }
    }

    // 解压正文记录
    final out = BytesBuilder(copy: false);
    for (var i = 1; i <= textRecords && i < recordCount; i++) {
      final data = record(i);
      if (compression == 2) {
        final chunk = _palmdocInflate(data);
        if (chunk == null) return null;
        out.add(chunk);
      } else {
        out.add(data);
      }
    }
    var raw = out.takeBytes();
    if (raw.length > textLength) raw = raw.sublist(0, textLength);
    if (raw.isEmpty) return null;

    final html = encoding == 65001
        ? utf8.decode(raw, allowMalformed: true)
        : decodeTextBytes(raw).text;
    final text = htmlToText(html).trim();
    if (text.isEmpty) return null;

    return MobiBook(
      title: (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : '未命名',
      author: author.isEmpty ? '佚名' : author,
      text: text,
    );
  }

  /// PalmDOC LZ77 解压
  static Uint8List? _palmdocInflate(Uint8List data) {
    try {
      final out = BytesBuilder(copy: false);
      final buffer = <int>[];
      var i = 0;
      while (i < data.length) {
        final c = data[i++];
        if (c == 0) {
          buffer.add(0);
        } else if (c <= 8) {
          for (var k = 0; k < c && i < data.length; k++) {
            buffer.add(data[i++]);
          }
        } else if (c <= 0x7F) {
          buffer.add(c);
        } else if (c <= 0xBF) {
          if (i >= data.length) break;
          final pair = (c << 8) | data[i++];
          final distance = (pair >> 3) & 0x7FF;
          final length = (pair & 7) + 3;
          if (distance > buffer.length) break;
          for (var k = 0; k < length; k++) {
            buffer.add(buffer[buffer.length - distance]);
          }
        } else {
          buffer.add(0x20);
          buffer.add(c ^ 0x80);
        }
      }
      out.add(buffer);
      return out.takeBytes();
    } catch (_) {
      return null;
    }
  }
}
