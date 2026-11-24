import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import 'app_paths.dart';
import 'book_parser.dart';
import 'cover_service.dart';
import 'library_service.dart';

class DriveFile {
  final String id;
  final String name;
  final int size;
  final DateTime modified;

  const DriveFile({
    required this.id,
    required this.name,
    required this.size,
    required this.modified,
  });
}

/// OneDrive 网盘挂载：不登录微软账号、不调用 Graph，也不申请整个网盘权限。
///
/// - Windows：选择一个本机已经同步好的 OneDrive 文件夹。
/// - Android：通过系统 SAF 目录选择器只授权一个 OneDrive 文件夹。
///
/// 两条路径都只在所选目录里创建并读写 `DanQingReader/books` 与
/// `DanQingReader/covers`：书籍原文件放 books，封面放 covers。
class OneDriveService extends ChangeNotifier {
  OneDriveService._();

  static final OneDriveService instance = OneDriveService._();

  static const String appFolderName = 'DanQingReader';
  static const String booksFolderName = 'books';
  static const String coversFolderName = 'covers';

  static const MethodChannel _treeChannel = MethodChannel(
    'com.danqing.novel_reader/one_drive',
  );

  String _mountPath = '';
  String _mountLabel = '';
  bool _androidTree = false;
  bool _available = false;
  bool _writable = false;
  bool _loaded = false;

  /// Windows 是文件夹绝对路径；Android 是 SAF 授权目录的 content:// URI。
  String get mountPath => _mountPath;

  /// 设置页展示用：Android 显示 OneDrive 里的目录名，Windows 显示路径。
  String get displayPath {
    if (!connected) return '';
    if (_androidTree) return _mountLabel.isEmpty ? 'OneDrive' : _mountLabel;
    return _mountPath;
  }

  bool get connected => _mountPath.isNotEmpty;
  bool get isAndroidTree => _androidTree;
  bool get writable => !_androidTree || _writable;

  bool get available {
    if (!connected) return false;
    if (_androidTree) return _available;
    return Directory(_mountPath).existsSync();
  }

  /// 设置页展示用：网盘里的应用目录。
  String get remoteRootPath =>
      connected ? _displayJoin(displayPath, appFolderName) : '';
  String get booksPath =>
      connected ? _displayJoin(remoteRootPath, booksFolderName) : '';
  String get coversPath =>
      connected ? _displayJoin(remoteRootPath, coversFolderName) : '';
  String get account => _mountPath;

  /// Windows 上自动找已经同步到本机的 OneDrive 根目录；找不到返回 null。
  String? get detectedLocalRoot {
    if (Platform.isAndroid) return null;
    for (final key in const [
      'OneDrive',
      'OneDriveConsumer',
      'OneDriveCommercial',
    ]) {
      final path = Platform.environment[key];
      if (path != null && path.trim().isNotEmpty) {
        final dir = Directory(path);
        if (dir.existsSync()) return dir.absolute.path;
      }
    }
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isNotEmpty) {
      final dir = Directory(_join(home, 'OneDrive'));
      if (dir.existsSync()) return dir.absolute.path;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(AppPaths.oneDriveMountFile);
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final path = (json['mountPath'] as String? ?? '').trim();
        final label = (json['label'] as String? ?? '').trim();
        final kind = (json['kind'] as String? ?? '').trim();
        if (path.isNotEmpty) {
          _mountPath = path;
          _mountLabel = label;
          _androidTree =
              kind == 'androidTree' ||
              (Platform.isAndroid && path.startsWith('content://'));
          if (_androidTree) {
            await _refreshTreeState();
          } else {
            _available = Directory(path).existsSync();
            _writable = _available;
          }
        }
      }
    } catch (_) {
      _mountPath = '';
      _mountLabel = '';
      _androidTree = false;
      _available = false;
    }
    notifyListeners();
  }

  /// Android：打开系统 SAF 目录选择器，选中 OneDrive 文件夹后立即挂载。
  /// 返回 null 表示成功或用户取消；否则是可展示的错误。
  Future<String?> pickAndroidAndMount() async {
    if (!Platform.isAndroid) return '当前平台请直接选择 OneDrive 文件夹';
    try {
      final raw = await _treeChannel.invokeMethod<dynamic>('pickFolder');
      if (raw is! Map) return null;
      final data = Map<String, dynamic>.from(raw);
      final uri = (data['uri'] as String? ?? '').trim();
      if (uri.isEmpty) return null;
      final label = (data['label'] as String? ?? '').trim();
      return _mountAndroidTree(uri, label);
    } on MissingPluginException {
      return '当前安装包没有包含安卓网盘挂载组件，请更新后重试';
    } catch (e) {
      return '无法打开 OneDrive 文件夹选择器：$e';
    }
  }

  /// 挂载一个已经同步到本机的 OneDrive 文件夹（Windows）。
  /// 返回 null 表示成功，否则返回可展示的错误信息。
  Future<String?> mount(String path) async {
    final raw = path.trim();
    if (raw.isEmpty) return '没有选择文件夹';
    if (Platform.isAndroid && raw.startsWith('content://')) {
      return _mountAndroidTree(raw, 'OneDrive');
    }
    final oldPath = _mountPath;
    final oldLabel = _mountLabel;
    final oldTree = _androidTree;
    try {
      final dir = Directory(raw);
      if (!await dir.exists()) return '这个文件夹当前不可访问，请先让 OneDrive 完成同步';
      var base = dir.absolute.path;
      final segments = base.split(RegExp(r'[\\/]'));
      final appIndex = segments.lastIndexWhere(
        (s) => s.toLowerCase() == appFolderName.toLowerCase(),
      );
      if (appIndex > 0) {
        base = segments.sublist(0, appIndex).join(Platform.pathSeparator);
      }
      _mountPath = base;
      _mountLabel = _baseName(base);
      _androidTree = false;
      await _ensureStructure();
      _available = true;
      _writable = true;
      await _saveConfig();
      notifyListeners();
      return null;
    } catch (e) {
      _mountPath = oldPath;
      _mountLabel = oldLabel;
      _androidTree = oldTree;
      return '无法写入这个文件夹：$e';
    }
  }

  Future<String?> _mountAndroidTree(String uri, String label) async {
    final oldPath = _mountPath;
    final oldLabel = _mountLabel;
    final oldTree = _androidTree;
    try {
      final info = await _treeChannel.invokeMapMethod<String, dynamic>(
        'ensureStructure',
        {'uri': uri},
      );
      if (info == null) return 'OneDrive 没有返回应用目录';
      _mountPath = uri;
      _mountLabel = label.trim().isEmpty ? 'OneDrive' : label.trim();
      _androidTree = true;
      _available = true;
      _writable = true;
      await _saveConfig();
      notifyListeners();
      return null;
    } on PlatformException catch (e) {
      _mountPath = oldPath;
      _mountLabel = oldLabel;
      _androidTree = oldTree;
      return '无法在 OneDrive 里创建应用目录：${e.message ?? e.code}';
    } catch (e) {
      _mountPath = oldPath;
      _mountLabel = oldLabel;
      _androidTree = oldTree;
      return '无法挂载 OneDrive：$e';
    }
  }

  Future<void> unmount() async {
    _mountPath = '';
    _mountLabel = '';
    _androidTree = false;
    _available = false;
    _writable = false;
    try {
      final file = File(AppPaths.oneDriveMountFile);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _refreshTreeState() async {
    if (!_androidTree || _mountPath.isEmpty) return;
    try {
      final info = await _treeChannel.invokeMapMethod<String, dynamic>('check', {
        'uri': _mountPath,
      });
      if (info == null) {
        _available = false;
        _writable = false;
        return;
      }
      _available = info['available'] == true;
      _writable = info['writable'] == true;
      final label = (info['label'] as String? ?? '').trim();
      if (label.isNotEmpty) _mountLabel = label;
    } catch (_) {
      _available = false;
      _writable = false;
    }
  }

  Future<void> _saveConfig() async {
    await AppPaths.ensureDirs();
    await File(AppPaths.oneDriveMountFile).writeAsString(
      jsonEncode({
        'mountPath': _mountPath,
        'label': _mountLabel,
        'kind': _androidTree ? 'androidTree' : 'localFolder',
      }),
    );
  }

  Future<void> _ensureStructure() async {
    if (!connected) return;
    if (_androidTree) {
      final info = await _treeChannel.invokeMapMethod<String, dynamic>(
        'ensureStructure',
        {'uri': _mountPath},
      );
      if (info == null) throw StateError('OneDrive 没有返回应用目录');
      _available = true;
      return;
    }
    for (final dir in [remoteRootPath, booksPath, coversPath]) {
      final d = Directory(dir);
      if (!await d.exists()) await d.create(recursive: true);
    }
  }

  String _displayJoin(String a, String b) {
    if (a.endsWith('/') || a.endsWith('\\')) return '$a$b';
    return '$a/$b';
  }

  String _join(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }

  String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

  String _baseWithoutExtension(String path) {
    final name = _baseName(path);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _extension(String path) {
    final name = _baseName(path);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot).toLowerCase() : '';
  }

  Future<bool> _copyIfNeeded(File source, File target) async {
    if (!await source.exists()) return false;
    if (await target.exists() &&
        await target.length() == await source.length()) {
      return false;
    }
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return true;
  }

  Future<List<Map<String, dynamic>>> _treeList(String folder) async {
    if (!_androidTree || _mountPath.isEmpty) return const [];
    try {
      final raw = await _treeChannel.invokeMethod<dynamic>('list', {
        'uri': _mountPath,
        'folder': folder,
      });
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> _treeUpload(
    String folder,
    String localPath,
    String name,
  ) async {
    try {
      final result = await _treeChannel.invokeMethod<dynamic>('upload', {
        'uri': _mountPath,
        'folder': folder,
        'localPath': localPath,
        'name': name,
      });
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _treeCopyToLocal(String remoteUri, File target) async {
    try {
      await target.parent.create(recursive: true);
      final result = await _treeChannel.invokeMethod<dynamic>('copyToLocal', {
        'uri': remoteUri,
        'targetPath': target.path,
      });
      return (result is num && result >= 0);
    } catch (_) {
      return false;
    }
  }

  /// 列出网盘 books 目录里的书（不含封面与目录）。
  Future<List<DriveFile>> listFiles() async {
    if (!available) return const [];
    await _ensureStructure();
    if (_androidTree) {
      final rows = await _treeList(booksFolderName);
      final files = <DriveFile>[];
      for (final row in rows) {
        if (row['isDir'] == true) continue;
        final name = (row['name'] as String? ?? '').trim();
        if (name.isEmpty || !isSupportedBookFile(name)) continue;
        final uri = (row['uri'] as String? ?? '').trim();
        if (uri.isEmpty) continue;
        files.add(
          DriveFile(
            id: uri,
            name: name,
            size: (row['size'] as num?)?.toInt() ?? 0,
            modified: DateTime.fromMillisecondsSinceEpoch(
              (row['modified'] as num?)?.toInt() ?? 0,
            ),
          ),
        );
      }
      files.sort((a, b) => a.name.compareTo(b.name));
      return files;
    }
    final dir = Directory(booksPath);
    if (!await dir.exists()) return const [];
    final files = <DriveFile>[];
    await for (final entity in dir.list(recursive: false)) {
      if (entity is! File) continue;
      if (!isSupportedBookFile(entity.path)) continue;
      final stat = await entity.stat();
      files.add(
        DriveFile(
          id: entity.path,
          name: _baseName(entity.path),
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    files.sort((a, b) => a.name.compareTo(b.name));
    return files;
  }

  /// 把网盘里有、本地没有（或大小不同）的书和封面补齐到本地书库。
  Future<int> downloadMissing() async {
    if (!available) return 0;
    try {
      await _ensureStructure();
    } catch (_) {
      return 0;
    }
    await AppPaths.ensureDirs();
    var count = 0;
    if (_androidTree) {
      final remote = await _treeList(booksFolderName);
      for (final row in remote) {
        if (row['isDir'] == true) continue;
        final name = (row['name'] as String? ?? '').trim();
        if (name.isEmpty || !isSupportedBookFile(name)) continue;
        final uri = (row['uri'] as String? ?? '').trim();
        if (uri.isEmpty) continue;
        final target = File(_join(AppPaths.booksDir, name));
        final remoteSize = (row['size'] as num?)?.toInt() ?? 0;
        try {
          if (await target.exists() &&
              remoteSize > 0 &&
              await target.length() == remoteSize) {
            continue;
          }
          if (await _treeCopyToLocal(uri, target)) count++;
        } catch (_) {}
      }
      await _downloadCoversTree();
    } else {
      final remoteBooks = Directory(booksPath);
      if (await remoteBooks.exists()) {
        await for (final entity in remoteBooks.list(recursive: false)) {
          if (entity is! File || !isSupportedBookFile(entity.path)) continue;
          final target = File(_join(AppPaths.booksDir, _baseName(entity.path)));
          try {
            if (await _copyIfNeeded(entity, target)) count++;
          } catch (_) {}
        }
      }
      await _downloadCovers();
    }
    if (count > 0) notifyListeners();
    return count;
  }

  Future<void> _downloadCoversTree() async {
    final remote = await _treeList(coversFolderName);
    for (final row in remote) {
      if (row['isDir'] == true) continue;
      final name = (row['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final ext = _extension(name);
      if (!const ['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) continue;
      final uri = (row['uri'] as String? ?? '').trim();
      if (uri.isEmpty) continue;
      final target = File(_join(AppPaths.booksDir, name));
      final remoteSize = (row['size'] as num?)?.toInt() ?? 0;
      try {
        if (await target.exists() &&
            remoteSize > 0 &&
            await target.length() == remoteSize) {
          continue;
        }
        await _treeCopyToLocal(uri, target);
      } catch (_) {}
    }
  }

  Future<void> _downloadCovers() async {
    final remoteCovers = Directory(coversPath);
    if (!await remoteCovers.exists()) return;
    await for (final entity in remoteCovers.list(recursive: false)) {
      if (entity is! File) continue;
      final ext = _extension(entity.path);
      if (!const ['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) continue;
      // 本地书库用同名 sidecar，CoverService 会自动识别。
      final target = File(_join(AppPaths.booksDir, _baseName(entity.path)));
      try {
        await _copyIfNeeded(entity, target);
      } catch (_) {}
    }
  }

  /// 把本地书库里的书与封面推送到网盘。
  Future<int> uploadBooks() async {
    if (!available) return 0;
    try {
      await _ensureStructure();
    } catch (_) {
      return 0;
    }
    var count = 0;
    if (_androidTree) {
      final remoteRows = await _treeList(booksFolderName);
      final remoteSizes = <String, int>{};
      for (final row in remoteRows) {
        if (row['isDir'] == true) continue;
        final name = (row['name'] as String? ?? '').trim().toLowerCase();
        if (name.isEmpty) continue;
        remoteSizes[name] = (row['size'] as num?)?.toInt() ?? 0;
      }
      final localBooks = Directory(AppPaths.booksDir);
      if (await localBooks.exists()) {
        await for (final entity in localBooks.list(recursive: false)) {
          if (entity is! File || !isSupportedBookFile(entity.path)) continue;
          final name = _baseName(entity.path);
          final localSize = await entity.length();
          final remoteSize = remoteSizes[name.toLowerCase()] ?? -1;
          if (remoteSize == localSize) continue;
          if (await _treeUpload(booksFolderName, entity.path, name)) count++;
        }
      }
      final remoteCovers = await _treeList(coversFolderName);
      final remoteCoverSizes = <String, int>{};
      for (final row in remoteCovers) {
        if (row['isDir'] == true) continue;
        final name = (row['name'] as String? ?? '').trim().toLowerCase();
        if (name.isEmpty) continue;
        remoteCoverSizes[name] = (row['size'] as num?)?.toInt() ?? 0;
      }
      final books = LibraryService.instance.books
          .where((b) => !b.trashed)
          .toList();
      for (final book in books) {
        final source = await _coverSource(book);
        if (source == null) continue;
        final base = _baseWithoutExtension(book.filePath);
        final ext = _extension(source.path);
        final name = '$base${ext.isEmpty ? '.jpg' : ext}';
        final size = await source.length();
        final remoteSize = remoteCoverSizes[name.toLowerCase()] ?? -1;
        if (remoteSize == size) continue;
        if (await _treeUpload(coversFolderName, source.path, name)) count++;
      }
    } else {
      final localBooks = Directory(AppPaths.booksDir);
      if (await localBooks.exists()) {
        await for (final entity in localBooks.list(recursive: false)) {
          if (entity is! File || !isSupportedBookFile(entity.path)) continue;
          final target = File(_join(booksPath, _baseName(entity.path)));
          try {
            if (await _copyIfNeeded(entity, target)) count++;
          } catch (_) {}
        }
      }
      count += await _pushCovers();
    }
    if (count > 0) notifyListeners();
    return count;
  }

  Future<int> _pushCovers() async {
    var count = 0;
    final books = LibraryService.instance.books
        .where((b) => !b.trashed)
        .toList();
    for (final book in books) {
      final source = await _coverSource(book);
      if (source == null) continue;
      final base = _baseWithoutExtension(book.filePath);
      final ext = _extension(source.path);
      final target = File(
        _join(coversPath, '$base${ext.isEmpty ? '.jpg' : ext}'),
      );
      try {
        if (await _copyIfNeeded(source, target)) count++;
      } catch (_) {}
    }
    return count;
  }

  Future<File?> _coverSource(Book book) async {
    if (book.coverPath.isNotEmpty) {
      final cached = File(book.coverPath);
      if (await cached.exists()) return cached;
    }
    final base = _baseWithoutExtension(book.filePath);
    for (final ext in ['.jpg', '.jpeg', '.png', '.webp']) {
      final sidecar = File(_join(AppPaths.booksDir, '$base$ext'));
      if (await sidecar.exists()) return sidecar;
      final upper = File(_join(AppPaths.booksDir, '$base${ext.toUpperCase()}'));
      if (await upper.exists()) return upper;
    }
    return null;
  }

  /// 把网盘里的单个文件复制到指定目录（云书库导入用）。
  Future<String?> downloadTo(DriveFile file, String destDir) async {
    final target = File(_join(destDir, file.name));
    if (_androidTree && file.id.startsWith('content://')) {
      if (await target.exists() &&
          file.size > 0 &&
          await target.length() == file.size) {
        return target.path;
      }
      if (await _treeCopyToLocal(file.id, target)) return target.path;
      return null;
    }
    final source = File(file.id);
    if (!await source.exists()) return null;
    try {
      if (await target.exists() &&
          await target.length() == await source.length()) {
        return target.path;
      }
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// 一次完整同步：网盘 → 本地 → 补齐封面 → 本地新增 → 网盘。
  Future<void> syncNow() async {
    if (!available) return;
    await downloadMissing();
    await LibraryService.instance.scanBooksFolder();
    await CoverService.instance.ensureCovers();
    await uploadBooks();
    if (_androidTree) await _refreshTreeState();
  }
}
