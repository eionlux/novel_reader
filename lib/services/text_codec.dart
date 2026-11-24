import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// 文本解码结果
class DecodedText {
  final String text;
  final String encoding;
  const DecodedText(this.text, this.encoding);
}

typedef _MallocNative = Pointer<Uint8> Function(Int32);
typedef _MallocDart = Pointer<Uint8> Function(int);

typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _FreeDart = void Function(Pointer<Uint8>);

typedef _MultiByteToWideCharNative =
    Int32 Function(
      Int32 codePage,
      Uint32 flags,
      Pointer<Uint8> str,
      Int32 cbMultiByte,
      Pointer<Uint16> out,
      Int32 cchWideChar,
    );
typedef _MultiByteToWideCharDart =
    int Function(
      int codePage,
      int flags,
      Pointer<Uint8> str,
      int cbMultiByte,
      Pointer<Uint16> out,
      int cchWideChar,
    );

class _WinApi {
  static final _MallocDart? malloc = _lookupMalloc();
  static final _FreeDart? free = _lookupFree();
  static final _MultiByteToWideCharDart? mb2wc = _lookupMb2wc();

  static _MallocDart? _lookupMalloc() {
    if (!Platform.isWindows) return null;
    for (final lib in ['msvcrt.dll', 'ucrtbase.dll']) {
      try {
        return DynamicLibrary.open(
          lib,
        ).lookupFunction<_MallocNative, _MallocDart>('malloc');
      } catch (_) {}
    }
    return null;
  }

  static _FreeDart? _lookupFree() {
    for (final lib in ['msvcrt.dll', 'ucrtbase.dll']) {
      try {
        return DynamicLibrary.open(
          lib,
        ).lookupFunction<_FreeNative, _FreeDart>('free');
      } catch (_) {}
    }
    return null;
  }

  static _MultiByteToWideCharDart? _lookupMb2wc() {
    if (!Platform.isWindows) return null;
    try {
      return DynamicLibrary.open(
        'kernel32.dll',
      ).lookupFunction<_MultiByteToWideCharNative, _MultiByteToWideCharDart>(
        'MultiByteToWideChar',
      );
    } catch (_) {
      return null;
    }
  }
}

/// 用 Windows API 把 GBK / GB18030 字节解成字符串，失败返回 null
String? _decodeGbkViaWin32(Uint8List bytes) {
  final malloc = _WinApi.malloc;
  final free = _WinApi.free;
  final mb2wc = _WinApi.mb2wc;
  if (malloc == null || free == null || mb2wc == null) return null;

  Pointer<Uint8> src = nullptr;
  Pointer<Uint16> dst = nullptr;
  try {
    src = malloc(bytes.isEmpty ? 1 : bytes.length);
    if (src == nullptr) return null;
    if (bytes.isNotEmpty) {
      src.asTypedList(bytes.length).setAll(0, bytes);
    }

    // 54936 = GB18030（兼容 GBK），0 = 不做校验，逐字节转换
    final need = mb2wc(54936, 0, src, bytes.length, nullptr, 0);
    if (need <= 0) return null;

    dst = malloc(need * 2).cast<Uint16>();
    if (dst == nullptr) return null;
    final done = mb2wc(54936, 0, src, bytes.length, dst, need);
    if (done <= 0) return null;

    final units = Uint16List(done);
    units.setAll(0, dst.asTypedList(done));
    return String.fromCharCodes(units);
  } catch (_) {
    return null;
  } finally {
    if (src != nullptr) free(src);
    if (dst != nullptr) free(dst.cast<Uint8>());
  }
}

String _decodeUtf16Le(Uint8List bytes, int offset) {
  final n = (bytes.length - offset) ~/ 2;
  final units = Uint16List(n);
  for (var i = 0; i < n; i++) {
    final p = offset + i * 2;
    units[i] = bytes[p] | (bytes[p + 1] << 8);
  }
  return String.fromCharCodes(units);
}

String _decodeUtf16Be(Uint8List bytes, int offset) {
  final n = (bytes.length - offset) ~/ 2;
  final units = Uint16List(n);
  for (var i = 0; i < n; i++) {
    final p = offset + i * 2;
    units[i] = (bytes[p] << 8) | bytes[p + 1];
  }
  return String.fromCharCodes(units);
}

/// 常见中文小说编码的自动识别：UTF-8 / UTF-16（带 BOM）/ GBK(GB18030)
DecodedText decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return DecodedText(
      utf8.decode(bytes.sublist(3), allowMalformed: true),
      'UTF-8',
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return DecodedText(_decodeUtf16Le(bytes, 2), 'UTF-16LE');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return DecodedText(_decodeUtf16Be(bytes, 2), 'UTF-16BE');
  }

  // 先按严格 UTF-8 试，失败再走 GB18030
  try {
    return DecodedText(utf8.decode(bytes), 'UTF-8');
  } catch (_) {}

  final gbk = _decodeGbkViaWin32(bytes);
  if (gbk != null) {
    return DecodedText(gbk, 'GBK/GB18030');
  }

  // 最后兜底：允许损坏的 UTF-8
  return DecodedText(utf8.decode(bytes, allowMalformed: true), '未知(UTF-8 容错)');
}
