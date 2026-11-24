import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/library_service.dart';
import 'app_theme.dart';
import 'book_cover.dart';
import 'book_detail_page.dart';
import 'strings.dart';

/// 首页二级页：我的最爱 / 最近添加 / 最近阅读 / 回收站
class LibraryListPage extends StatefulWidget {
  LibraryListPage({super.key, required this.mode});

  /// favorites / added / viewed / trash
  final String mode;

  @override
  State<LibraryListPage> createState() => _LibraryListPageState();
}

class _LibraryListPageState extends State<LibraryListPage> {
  final LibraryService _lib = LibraryService.instance;

  static const Map<String, String> _titles = {
    'favorites': '我的喜爱',
    'added': '最近添加',
    'viewed': '最近阅读',
    'trash': '回收站',
  };

  static const Map<String, String> _emptyTexts = {
    'favorites': '还没有收藏的书，点封面右上角的爱心就能加进来',
    'added': '最近没有新导入的书',
    'viewed': '还没有阅读记录，打开一本书就会出现在这里',
    'trash': '回收站是空的',
  };

  @override
  void initState() {
    super.initState();
    _lib.addListener(_onChanged);
  }

  @override
  void dispose() {
    _lib.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String get _title => L.t(_titles[widget.mode] ?? '书库');

  bool get _isTrash => widget.mode == 'trash';

  List<Book> get _books {
    final source = _lib.books;
    switch (widget.mode) {
      case 'favorites':
        return source.where((b) => b.favorite && !b.trashed).toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      case 'added':
        return source.where((b) => !b.trashed).toList()
          ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case 'viewed':
        return source
            .where(
              (b) =>
                  !b.trashed &&
                  (b.progress > 0 || b.lastOpenedAt.isAfter(b.addedAt)),
            )
            .toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      case 'trash':
        return source.where((b) => b.trashed).toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      default:
        return source.where((b) => !b.trashed).toList();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(milliseconds: 1800),
        ),
      );
  }

  Future<void> _clearTrash() async {
    final items = _books;
    if (items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('清空回收站', style: TextStyle(fontSize: 16)),
        content: Text('将移除 ${items.length} 本书记录（原始文件不会被删除），且无法在本应用内恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L.t('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L.t('清空')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final book in items) {
      await _lib.purge(book);
    }
    _snack('已清空回收站');
  }

  Future<void> _deleteOne(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(L.t('从书库删除'), style: TextStyle(fontSize: 16)),
        content: Text('《${book.title}》将移入回收站，原文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L.t('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L.t('删除'), style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _lib.moveToTrash(book);
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Text(
              _title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryText,
              ),
            ),
            SizedBox(width: 8),
            Text(
              '${books.length}',
              style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
            ),
          ],
        ),
        actions: [
          if (_isTrash && books.isNotEmpty)
            TextButton(
              onPressed: _clearTrash,
              child: Text(
                '清空回收站',
                style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
              ),
            ),
          SizedBox(width: 8),
        ],
      ),
      body: books.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isTrash
                          ? Icons.delete_outline
                          : Icons.auto_stories_outlined,
                      size: 48,
                      color: AppTheme.accent.withValues(alpha: 0.45),
                    ),
                    SizedBox(height: 16),
                    Text(
                      _emptyTexts[widget.mode] ?? '这里还是空的',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppTheme.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _grid(books),
    );
  }

  Widget _grid(List<Book> books) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 28),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 118,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: books.length,
      itemBuilder: (ctx, i) => _tile(books[i]),
    );
  }

  Widget _tile(Book book) {
    return GestureDetector(
      onTap: () {
        if (_isTrash) {
          _lib.restoreFromTrash(book);
          _snack('已恢复到书库');
        } else {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => BookDetailPage(book: book)));
        }
      },
      onLongPress: () {
        if (!_isTrash) _deleteOne(book);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              BookCover(book: book, titleSize: 12.5),
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: () =>
                      _isTrash ? _lib.purge(book) : _lib.toggleFavorite(book),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: 0.82),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isTrash
                          ? Icons.delete_outline
                          : (book.favorite
                                ? Icons.favorite
                                : Icons.favorite_border),
                      size: 14,
                      color: _isTrash
                          ? Colors.redAccent
                          : (book.favorite
                                ? Colors.redAccent
                                : AppTheme.secondaryText),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
