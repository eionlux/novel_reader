import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

/// 一条书签：记在某本书的某章某字符位置
class Bookmark {
  final String id;
  final String bookId;
  final int chapter;
  final int charOffset;
  final String chapterTitle;
  final String snippet;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.charOffset,
    required this.chapterTitle,
    required this.snippet,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'chapter': chapter,
    'charOffset': charOffset,
    'chapterTitle': chapterTitle,
    'snippet': snippet,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    bookId: json['bookId'] as String? ?? '',
    chapter: (json['chapter'] as num?)?.toInt() ?? 0,
    charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
    chapterTitle: json['chapterTitle'] as String? ?? '',
    snippet: json['snippet'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 书签存储：按账户存一个 JSON 文件
class BookmarkService {
  BookmarkService._();

  static final BookmarkService instance = BookmarkService._();

  String _account = 'guest';
  List<Bookmark> _items = [];

  String get account => _account;

  Future<void> loadFor(String account) async {
    _account = account;
    _items = [];
    try {
      final file = File(AppPaths.bookmarksFileFor(account));
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          _items = raw
              .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {
      _items = [];
    }
  }

  /// 某本书的书签，新的在前
  List<Bookmark> forBook(String bookId) {
    final list = _items.where((b) => b.bookId == bookId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<Bookmark> add({
    required String bookId,
    required int chapter,
    required int charOffset,
    required String chapterTitle,
    required String snippet,
  }) async {
    final mark = Bookmark(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      bookId: bookId,
      chapter: chapter,
      charOffset: charOffset,
      chapterTitle: chapterTitle,
      snippet: snippet,
      createdAt: DateTime.now(),
    );
    _items.add(mark);
    await _save();
    return mark;
  }

  Future<void> remove(String id) async {
    _items.removeWhere((b) => b.id == id);
    await _save();
  }

  Future<void> _save() async {
    try {
      await AppPaths.ensureDirs();
      final file = File(AppPaths.bookmarksFileFor(_account));
      await file.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }
}
