import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 极简 ZIP 读取器：EPUB 本质上就是 ZIP，只需要支持 stored / deflate 两种压缩方式。
/// 零第三方依赖，deflate 直接用 dart:io 的 ZLibDecoder(raw: true)。
class ZipEntry {
  final String name;
  final int method;
  final int compressedSize;
  final int localHeaderOffset;

  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.localHeaderOffset,
  });
}

class ZipArchive {
  final Uint8List _bytes;
  final Map<String, ZipEntry> entries;

  ZipArchive._(this._bytes, this.entries);

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static ZipArchive? open(Uint8List bytes) {
    if (bytes.length < 22) return null;
    // 从尾部找 EOCD（End of Central Directory）签名 0x06054b50
    final start = bytes.length > 66000 ? bytes.length - 66000 : 0;
    var eocd = -1;
    for (var i = bytes.length - 22; i >= start; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4B &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return null;

    final total = _u16(bytes, eocd + 10);
    final dirOffset = _u32(bytes, eocd + 16);
    final entries = <String, ZipEntry>{};
    var p = dirOffset;
    for (var n = 0; n < total && p + 46 <= bytes.length; n++) {
      if (_u32(bytes, p) != 0x02014b50) break;
      final method = _u16(bytes, p + 10);
      final compressedSize = _u32(bytes, p + 20);
      final nameLen = _u16(bytes, p + 28);
      final extraLen = _u16(bytes, p + 30);
      final commentLen = _u16(bytes, p + 32);
      final localOffset = _u32(bytes, p + 42);
      final nameBytes = bytes.sublist(p + 46, p + 46 + nameLen);
      final name = utf8
          .decode(nameBytes, allowMalformed: true)
          .replaceAll('\\', '/');
      entries[name] = ZipEntry(
        name: name,
        method: method,
        compressedSize: compressedSize,
        localHeaderOffset: localOffset,
      );
      p += 46 + nameLen + extraLen + commentLen;
    }
    if (entries.isEmpty) return null;
    return ZipArchive._(bytes, entries);
  }

  Uint8List? read(String name) {
    final entry = entries[name] ?? entries[name.replaceAll('\\', '/')];
    if (entry == null) return null;
    final o = entry.localHeaderOffset;
    if (o + 30 > _bytes.length) return null;
    final nameLen = _u16(_bytes, o + 26);
    final extraLen = _u16(_bytes, o + 28);
    final dataStart = o + 30 + nameLen + extraLen;
    final end = dataStart + entry.compressedSize;
    if (end > _bytes.length) return null;
    final raw = _bytes.sublist(dataStart, end);
    try {
      if (entry.method == 0) return raw;
      if (entry.method == 8) {
        return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? readText(String name) {
    final data = read(name);
    if (data == null) return null;
    return utf8.decode(data, allowMalformed: true);
  }

  /// 大小写不敏感地找条目（部分打包工具路径大小写不规范）
  String? findEntry(String name) {
    if (entries.containsKey(name)) return name;
    final lower = name.toLowerCase();
    for (final key in entries.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    return null;
  }
}
