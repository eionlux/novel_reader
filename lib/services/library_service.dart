import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/book.dart';
import 'app_paths.dart';
import 'auth_service.dart';
import 'book_parser.dart';
import 'chapter_parser.dart';

class LibraryService extends ChangeNotifier {
  LibraryService._();

  static final LibraryService instance = LibraryService._();

  final List<Book> books = [];
  final Map<String, List<Chapter>> _chapterCache = {};
  String _account = AuthService.guestAccount;
  int _loadGeneration = 0;

  String get account => _account;

  List<Book> get shelfBooks =>
      books.where((b) => b.inShelf).toList()
        ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));

  /// 最近阅读：打开过的书按时间倒序
  List<Book> get recentBooks {
    final list =
        books
            .where((b) => b.progress > 0 || b.lastOpenedAt.isAfter(b.addedAt))
            .toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    if (list.isEmpty) {
      final fallback = List<Book>.from(books)
        ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      return fallback.take(8).toList();
    }
    return list.take(8).toList();
  }

  Future<void> loadFor(String account) async {
    final generation = ++_loadGeneration;
    _account = account;
    await AppPaths.ensureDirs();
    books.clear();
    _chapterCache.clear();
    final file = File(AppPaths.libraryFileFor(account));
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        books.addAll(
          (raw as List).map((e) => Book.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {}
    } else if (account == AuthService.guestAccount) {
      // 旧版本索引迁移到游客账户
      final legacy = File(AppPaths.libraryFile);
      if (await legacy.exists()) {
        try {
          final raw = jsonDecode(await legacy.readAsString());
          books.addAll(
            (raw as List).map((e) => Book.fromJson(e as Map<String, dynamic>)),
          );
        } catch (_) {}
      }
    }
    await _ensureSampleBook();
    _sort();
    notifyListeners();

    // Parsing every changed book can take a long time on a phone. Show the
    // library first, then refresh stale entries without blocking app startup.
    unawaited(_refreshStale(generation, account, List<Book>.from(books)));
  }

  Future<void> reload() => loadFor(_account);

  Future<void> _refreshStale(
    int generation,
    String account,
    List<Book> snapshot,
  ) async {
    var dirty = false;
    try {
      for (final book in snapshot) {
        if (generation != _loadGeneration || account != _account) return;
        final file = File(book.filePath);
        if (!await file.exists()) continue;
        final size = await file.length();
        if (size == book.fileSize && book.parserVersion == kParserVersion)
          continue;

        final parsed = await parseBookFile(book.filePath);
        if (parsed == null || parsed.chapters.isEmpty) continue;
        if (generation != _loadGeneration || account != _account) return;

        book
          ..title = parsed.title
          ..author = parsed.author
          ..charCount = parsed.charCount
          ..chapterCount = parsed.chapters.length
          ..fileSize = size
          ..parserVersion = kParserVersion
          ..format = extensionOf(book.filePath);
        _chapterCache[book.filePath] = parsed.chapters;
        dirty = true;
      }
      if (dirty && generation == _loadGeneration && account == _account) {
        _sort();
        await save();
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('后台更新书库索引失败: $error\n$stackTrace');
    }
  }

  void _sort() {
    books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  }

  Future<void> _ensureSampleBook() async {
    final path = '${AppPaths.booksDir}${Platform.pathSeparator}青崖记.txt';
    final file = File(path);
    if (!await file.exists()) {
      try {
        final data = await rootBundle.load('assets/sample/qingya.txt');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } catch (_) {
        return;
      }
    }
    if (!books.any((b) => b.filePath.toLowerCase() == path.toLowerCase())) {
      final book = await importFile(path, quiet: true);
      book?.inShelf = true;
    }
  }

  Future<int> scanBooksFolder() async {
    final dir = Directory(AppPaths.booksDir);
    if (!await dir.exists()) return 0;
    var added = 0;
    await for (final entity in dir.list(recursive: false)) {
      if (entity is File && isSupportedBookFile(entity.path)) {
        final existed = books.any(
          (b) => b.filePath.toLowerCase() == entity.path.toLowerCase(),
        );
        final book = await importFile(entity.path, quiet: true);
        if (book != null && !existed) added++;
      }
    }
    _sort();
    await save();
    notifyListeners();
    return added;
  }

  Future<Book?> importFile(String path, {bool quiet = false}) async {
    if (!isSupportedBookFile(path)) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final parsed = await parseBookFile(path);
    if (parsed == null || parsed.chapters.isEmpty) return null;
    final size = await file.length();

    final existing = books.indexWhere(
      (b) => b.filePath.toLowerCase() == path.toLowerCase(),
    );
    final now = DateTime.now();
    final book = Book(
      id: '${path.hashCode.toUnsigned(32).toRadixString(16)}-$size',
      title: parsed.title,
      author: parsed.author,
      filePath: path,
      charCount: parsed.charCount,
      chapterCount: parsed.chapters.length,
      addedAt: existing >= 0 ? books[existing].addedAt : now,
      lastOpenedAt: existing >= 0 ? books[existing].lastOpenedAt : now,
      lastChapter: existing >= 0 ? books[existing].lastChapter : 0,
      lastCharOffset: existing >= 0 ? books[existing].lastCharOffset : 0,
      progress: existing >= 0 ? books[existing].progress : 0,
      fileSize: size,
      parserVersion: kParserVersion,
      inShelf: existing >= 0 ? books[existing].inShelf : false,
      format: extensionOf(path),
      favorite: existing >= 0 ? books[existing].favorite : false,
      trashed: existing >= 0 ? books[existing].trashed : false,
      shelfId: existing >= 0 ? books[existing].shelfId : '',
      coverPath: existing >= 0 ? books[existing].coverPath : '',
    );
    _chapterCache[path] = parsed.chapters;
    if (existing >= 0) {
      books[existing] = book;
    } else {
      books.add(book);
    }
    if (!quiet) {
      _sort();
      await save();
      notifyListeners();
    }
    return book;
  }

  /// 从系统「打开方式」进来的外部文件：先复制进书库目录，再入库
  Future<Book?> importExternal(String path) async {
    if (!isSupportedBookFile(path)) return null;
    final source = File(path);
    if (!await source.exists()) return null;
    final dir = Directory(AppPaths.booksDir);
    if (!await dir.exists()) await dir.create(recursive: true);

    final normalizedDir = dir.path.toLowerCase();
    final normalizedSource = path.toLowerCase();
    if (normalizedSource.startsWith(
      '$normalizedDir${Platform.pathSeparator}',
    )) {
      return importFile(path);
    }

    final fileName = path.split(RegExp(r'[\\/]')).last;
    var target = File('${dir.path}${Platform.pathSeparator}$fileName');
    var index = 2;
    while (await target.exists()) {
      if (await target.length() == await source.length()) break;
      final dot = fileName.lastIndexOf('.');
      final base = dot > 0 ? fileName.substring(0, dot) : fileName;
      final ext = dot > 0 ? fileName.substring(dot) : '';
      target = File('${dir.path}${Platform.pathSeparator}$base ($index)$ext');
      index++;
    }
    if (!await target.exists()) {
      await source.copy(target.path);
    }
    return importFile(target.path);
  }

  Future<List<Chapter>> chaptersFor(Book book) async {
    final cached = _chapterCache[book.filePath];
    if (cached != null) return cached;
    final parsed = await parseBookFile(book.filePath);
    if (parsed == null) return const [];
    _chapterCache[book.filePath] = parsed.chapters;
    return parsed.chapters;
  }

  Future<void> toggleShelf(Book book) async {
    book.inShelf = !book.inShelf;
    await save();
    notifyListeners();
  }

  Future<void> toggleFavorite(Book book) async {
    book.favorite = !book.favorite;
    await save();
    notifyListeners();
  }

  Future<void> setShelfOf(Book book, String shelfId) async {
    book.shelfId = shelfId;
    book.inShelf = true;
    await save();
    notifyListeners();
  }

  Future<void> moveToTrash(Book book) async {
    book.trashed = true;
    await save();
    notifyListeners();
  }

  Future<void> restoreFromTrash(Book book) async {
    book.trashed = false;
    await save();
    notifyListeners();
  }

  Future<void> purge(Book book) async {
    books.removeWhere((b) => b.id == book.id);
    _chapterCache.remove(book.filePath);
    await save();
    notifyListeners();
  }

  /// 批量导入文件路径，返回成功数量
  Future<int> importFiles(Iterable<String> paths) async {
    var added = 0;
    for (final path in paths) {
      final book = await importFile(path, quiet: true);
      if (book != null) added++;
    }
    _sort();
    await save();
    notifyListeners();
    return added;
  }

  /// 扫描一个文件夹（默认递归子目录），导入其中所有支持的电子书
  Future<int> importDirectory(String dirPath, {bool recursive = true}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    final candidates = <String>[];
    await for (final entity in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is File && isSupportedBookFile(entity.path))
        candidates.add(entity.path);
    }
    return importFiles(candidates);
  }

  /// 清理无效图书：文件已不存在的索引记录直接移除，返回移除数量
  Future<int> cleanupInvalid() async {
    final invalid = <Book>[];
    for (final book in books) {
      if (!await File(book.filePath).exists()) invalid.add(book);
    }
    for (final book in invalid) {
      books.removeWhere((b) => b.id == book.id);
      _chapterCache.remove(book.filePath);
    }
    if (invalid.isNotEmpty) {
      await save();
      notifyListeners();
    }
    return invalid.length;
  }

  /// 清理重复图书：同书名同大小视为重复，保留在架/进度最深/最早加入的一本
  Future<int> cleanupDuplicates() async {
    final groups = <String, List<Book>>{};
    for (final book in books) {
      groups.putIfAbsent('${book.title}|${book.fileSize}', () => []).add(book);
    }
    var removed = 0;
    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) {
        if (a.inShelf != b.inShelf) return a.inShelf ? -1 : 1;
        if (a.progress != b.progress) return b.progress.compareTo(a.progress);
        return a.addedAt.compareTo(b.addedAt);
      });
      for (final duplicate in group.skip(1)) {
        books.removeWhere((b) => b.id == duplicate.id);
        _chapterCache.remove(duplicate.filePath);
        removed++;
      }
    }
    if (removed > 0) {
      await save();
      notifyListeners();
    }
    return removed;
  }

  Future<void> remove(Book book) async {
    books.removeWhere((b) => b.id == book.id);
    _chapterCache.remove(book.filePath);
    await save();
    notifyListeners();
  }

  Future<void> touchOpened(Book book) async {
    book.lastOpenedAt = DateTime.now();
    _sort();
    await save();
    notifyListeners();
  }

  Future<void> updateProgress(
    Book book, {
    required int chapter,
    required int charOffset,
    required double progress,
  }) async {
    book.lastChapter = chapter;
    book.lastCharOffset = charOffset;
    book.progress = progress.clamp(0.0, 1.0);
    await save();
  }

  /// 供外部修改 Book 字段后通知界面刷新。
  void refresh() => notifyListeners();

  Future<void> save() async {
    try {
      final file = File(AppPaths.libraryFileFor(_account));
      final payload = const JsonEncoder.withIndent(
        '  ',
      ).convert(books.map((b) => b.toJson()).toList());
      await file.writeAsString(payload);
    } catch (_) {}
  }
}
