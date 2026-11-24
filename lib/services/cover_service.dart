import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/book.dart';
import 'app_paths.dart';
import 'library_service.dart';
import 'zip_reader.dart';

/// 从书籍文件里提取封面（EPUB 读 OPF，MOBI/AZW3 读 EXTH 图片记录），
/// 也支持同目录同名 sidecar 图片。结果写入 `coversDir`，路径存到 `Book.coverPath`。
class CoverService extends ChangeNotifier {
  CoverService._();

  static final CoverService instance = CoverService._();

  bool _running = false;

  /// 为所有还没有封面的书补齐封面。
  Future<void> ensureCovers() async {
    if (_running) return;
    _running = true;
    try {
      final books = LibraryService.instance.books
          .where((b) => !b.trashed)
          .toList();
      var changed = false;
      for (final book in books) {
        if (book.coverPath.isNotEmpty && await File(book.coverPath).exists()) {
          continue;
        }
        final cover = await extractFor(book);
        if (cover == null) continue;
        book.coverPath = cover;
        changed = true;
        notifyListeners();
      }
      if (changed) {
        await LibraryService.instance.save();
        LibraryService.instance.notifyListeners();
      }
    } catch (_) {
      // 封面失败不影响阅读
    } finally {
      _running = false;
    }
  }

  Future<String?> extractFor(Book book) async {
    final source = File(book.filePath);
    if (!await source.exists()) return null;

    final sidecar = await _sidecarCover(book.filePath);
    if (sidecar != null) return sidecar;

    try {
      final format = book.format.toLowerCase();
      if (format == 'epub') {
        final bytes = await source.readAsBytes();
        final data = _epubCover(bytes);
        if (data != null) return _write(book, data);
      } else if (format == 'mobi' || format == 'azw3' || format == 'azw') {
        final bytes = await source.readAsBytes();
        final data = _mobiCover(bytes);
        if (data != null) return _write(book, data);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> _sidecarCover(String bookPath) async {
    final name = bookPath.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final dir = bookPath.substring(0, bookPath.length - name.length);
    for (final ext in ['jpg', 'jpeg', 'png', 'webp']) {
      for (final candidate in ['$base.$ext', '$base.${ext.toUpperCase()}']) {
        final file = File('$dir$candidate');
        if (await file.exists()) return file.path;
      }
    }
    return null;
  }

  String _safeName(String raw) {
    final buffer = StringBuffer();
    for (final unit in raw.codeUnits) {
      final isDigit = unit >= 48 && unit <= 57;
      final isLower = unit >= 97 && unit <= 122;
      final isUpper = unit >= 65 && unit <= 90;
      if (isDigit || isLower || isUpper) {
        buffer.writeCharCode(unit);
      } else {
        buffer.write('_');
      }
    }
    final text = buffer.toString();
    return text.length > 80 ? text.substring(0, 80) : text;
  }

  Future<String> _write(Book book, Uint8List data) async {
    await Directory(AppPaths.coversDir).create(recursive: true);
    final ext = _extensionFor(data);
    final name = '${_safeName(book.id)}.$ext';
    final file = File('${AppPaths.coversDir}${Platform.pathSeparator}$name');
    await file.writeAsBytes(data, flush: true);
    return file.path;
  }

  String _extensionFor(Uint8List data) {
    if (data.length > 3 &&
        data[0] == 0xFF &&
        data[1] == 0xD8 &&
        data[2] == 0xFF) {
      return 'jpg';
    }
    if (data.length > 8 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return 'png';
    }
    if (data.length > 3 &&
        data[0] == 0x47 &&
        data[1] == 0x49 &&
        data[2] == 0x46) {
      return 'gif';
    }
    if (data.length > 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) {
      return 'webp';
    }
    return 'jpg';
  }

  // ---------------- EPUB ----------------

  Uint8List? _epubCover(Uint8List bytes) {
    final zip = ZipArchive.open(bytes);
    if (zip == null) return null;

    var opfPath = '';
    final container = zip.readText('META-INF/container.xml');
    if (container != null) {
      final m = RegExp(r'full-path\s*=\s*"([^"]+)"').firstMatch(container);
      if (m != null) opfPath = m.group(1)!;
    }
    if (opfPath.isEmpty || zip.findEntry(opfPath) == null) {
      for (final name in zip.entries.keys) {
        if (name.toLowerCase().endsWith('.opf')) {
          opfPath = name;
          break;
        }
      }
    }
    final opfKey = zip.findEntry(opfPath);
    if (opfKey == null) return null;
    final opf = zip.readText(opfKey);
    if (opf == null) return null;

    final baseDir = opfKey.contains('/')
        ? opfKey.substring(0, opfKey.lastIndexOf('/') + 1)
        : '';

    String? coverHref;
    final metaTag = RegExp(
      r'<meta\s+[^>]*name\s*=\s*"cover"[^>]*>',
      caseSensitive: false,
    ).firstMatch(opf)?.group(0);
    final coverId = metaTag == null ? null : _attr(metaTag, 'content');

    for (final m in RegExp(
      r'<item\s+[^>]*>',
      caseSensitive: false,
    ).allMatches(opf)) {
      final tag = m.group(0)!;
      final id = _attr(tag, 'id');
      final href = _attr(tag, 'href');
      final properties = (_attr(tag, 'properties') ?? '').split(RegExp(r'\s+'));
      if (properties.contains('cover-image') && href != null) {
        coverHref = href;
        break;
      }
      if (coverId != null && id == coverId && href != null) {
        coverHref = href;
        break;
      }
    }

    if (coverHref == null) {
      for (final name in zip.entries.keys) {
        final lower = name.toLowerCase();
        if (lower.contains('cover') &&
            (lower.endsWith('.jpg') ||
                lower.endsWith('.jpeg') ||
                lower.endsWith('.png') ||
                lower.endsWith('.webp') ||
                lower.endsWith('.gif'))) {
          coverHref = name.substring(baseDir.length);
          if (zip.findEntry(name) != null) return zip.read(name);
        }
      }
    }
    if (coverHref == null) return null;

    var decoded = coverHref;
    try {
      decoded = Uri.decodeComponent(coverHref);
    } catch (_) {}
    final resolved = _resolve(baseDir, decoded);
    final key = zip.findEntry(resolved);
    if (key == null) return null;
    final data = zip.read(key);
    if (data == null || data.length < 256) return null;
    return data;
  }

  String _resolve(String baseDir, String href) {
    var path = href.split('#').first;
    if (path.startsWith('/')) path = path.substring(1);
    final result = <String>[];
    for (final part in ('$baseDir$path').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (result.isNotEmpty) result.removeLast();
      } else {
        result.add(part);
      }
    }
    return result.join('/');
  }

  String? _attr(String tag, String name) {
    final m = RegExp(
      '$name\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return m?.group(1);
  }

  // ---------------- MOBI / AZW3 ----------------

  int _u16(Uint8List b, int o) =>
      (o >= 0 && o + 1 < b.length) ? (b[o] | (b[o + 1] << 8)) : 0;

  int _u32(Uint8List b, int o) => (o >= 0 && o + 3 < b.length)
      ? (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24))
      : 0;

  Uint8List? _record(Uint8List bytes, List<int> offsets, int index) {
    if (index < 0 || index >= offsets.length) return null;
    final start = offsets[index];
    final end = index + 1 < offsets.length ? offsets[index + 1] : bytes.length;
    if (start < 0 || start >= bytes.length) return null;
    if (end <= start || end > bytes.length) return null;
    return Uint8List.sublistView(bytes, start, end);
  }

  bool _isImage(Uint8List data) {
    if (data.length < 24) return false;
    if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
    if (data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47) {
      return true;
    }
    if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) return true;
    if (data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) {
      return true;
    }
    return false;
  }

  Uint8List? _mobiCover(Uint8List bytes) {
    if (bytes.length < 100) return null;
    final recordCount = _u16(bytes, 0x3C);
    if (recordCount <= 0) return null;
    final tableEnd = 78 + recordCount * 8 + 2;
    if (tableEnd > bytes.length) return null;

    final offsets = <int>[
      for (var i = 0; i < recordCount; i++) _u32(bytes, 78 + i * 8),
    ];
    final rec0 = _record(bytes, offsets, 0);
    if (rec0 == null) return null;
    final textRecords = _u16(rec0, 8);
    final firstImage = 1 + textRecords;
    if (firstImage >= recordCount) return null;

    final exthFlags = _u32(rec0, 0x90);
    int? coverOffset;
    if ((exthFlags & 0x40) != 0) {
      final mobiLength = _u32(rec0, 20);
      final exthStart = 16 + mobiLength;
      if (exthStart + 8 <= rec0.length &&
          rec0[exthStart] == 0x45 &&
          rec0[exthStart + 1] == 0x58 &&
          rec0[exthStart + 2] == 0x54 &&
          rec0[exthStart + 3] == 0x48) {
        final count = _u32(rec0, exthStart + 4);
        var p = exthStart + 8;
        for (var i = 0; i < count && p + 8 <= rec0.length; i++) {
          final type = _u32(rec0, p);
          final length = _u32(rec0, p + 4);
          if (length < 8 || p + length > rec0.length) break;
          if (type == 201 && length >= 12) {
            coverOffset = _u32(rec0, p + 8);
          }
          p += length;
        }
      }
    }

    if (coverOffset != null && coverOffset >= 0) {
      final data = _record(bytes, offsets, firstImage + coverOffset);
      if (data != null && _isImage(data)) return data;
    }

    for (var i = firstImage; i < recordCount; i++) {
      final data = _record(bytes, offsets, i);
      if (data != null && data.length > 512 && _isImage(data)) return data;
    }
    return null;
  }
}
