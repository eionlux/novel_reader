import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/book_parser.dart';
import '../services/library_service.dart';
import '../services/shelf_service.dart';
import 'app_theme.dart';
import 'book_cover.dart';
import 'reader_page.dart';
import 'shelf_picker.dart';
import 'strings.dart';

/// 书籍详情：封面、信息、加入书架、开始阅读
class BookDetailPage extends StatefulWidget {
  final Book book;
  BookDetailPage({super.key, required this.book});

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final LibraryService _lib = LibraryService.instance;

  Future<void> _openReader() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderPage(book: widget.book)));
    if (mounted) setState(() {});
  }

  Future<void> _pickShelf() async {
    await showAddToShelfSheet(context, widget.book);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final started = book.progress > 0;
    final shelf = ShelfService.instance.byId(book.shelfId);
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: AppTheme.primaryText,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          L.t('书籍详情'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryText,
          ),
        ),
        actions: [
          IconButton(
            tooltip: L.t('我的喜爱'),
            icon: Icon(
              book.favorite ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: book.favorite ? Colors.redAccent : AppTheme.secondaryText,
            ),
            onPressed: () async {
              await _lib.toggleFavorite(book);
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: book.trashed ? L.t('永久删除') : L.t('从书库删除'),
            icon: Icon(
              book.trashed ? Icons.delete_forever : Icons.delete_outline,
              size: 20,
              color: AppTheme.secondaryText,
            ),
            onPressed: () async {
              if (book.trashed) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.surface,
                    title: Text(L.t('永久删除'), style: TextStyle(fontSize: 16)),
                    content: Text('《${book.title}》会从索引永久移除，${L.t('该操作不可撤销')}。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(L.t('取消')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          L.t('永久删除'),
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _lib.purge(book);
                  if (mounted) Navigator.of(context).maybePop();
                }
                return;
              }
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.surface,
                  title: Text(L.t('从书库删除'), style: TextStyle(fontSize: 16)),
                  content: Text('《${book.title}》将移入回收站，原始文件不会被删除。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(L.t('取消')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        L.t('删除'),
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await _lib.moveToTrash(book);
                if (mounted) Navigator.of(context).maybePop();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 30),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 128,
                child: BookCover(
                  book: book,
                  titleSize: 17,
                  showProgress: false,
                ),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 6),
                    Text(
                      book.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryText,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      book.author,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                    SizedBox(height: 14),
                    _infoLine(L.t('格式'), book.format.toUpperCase()),
                    _infoLine(L.t('章节'), '${book.chapterCount} ${L.t('章')}'),
                    _infoLine(
                      L.t('字数'),
                      '${(book.charCount / 10000).toStringAsFixed(1)} 万',
                    ),
                    if (started)
                      _infoLine(
                        L.t('进度'),
                        '${(book.progress * 100).toStringAsFixed(0)}%',
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 26),
          if (book.trashed)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.5),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      await _lib.restoreFromTrash(book);
                      if (!mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(L.t('已恢复')),
                            duration: Duration(milliseconds: 1200),
                          ),
                        );
                    },
                    icon: Icon(Icons.restore, size: 18),
                    label: Text(L.t('恢复')),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppTheme.surface,
                          title: Text(
                            L.t('永久删除'),
                            style: TextStyle(fontSize: 16),
                          ),
                          content: Text(
                            '《${book.title}》会从索引永久移除，${L.t('该操作不可撤销')}。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text(L.t('取消')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: Text(
                                L.t('永久删除'),
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _lib.purge(book);
                        if (mounted) Navigator.of(context).maybePop();
                      }
                    },
                    icon: Icon(Icons.delete_forever, size: 18),
                    label: Text(L.t('永久删除')),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: book.inShelf
                          ? AppTheme.secondaryText
                          : AppTheme.accent,
                      side: BorderSide(
                        color: book.inShelf
                            ? AppTheme.divider
                            : AppTheme.accent.withValues(alpha: 0.5),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pickShelf,
                    icon: Icon(
                      book.inShelf
                          ? Icons.bookmark
                          : Icons.bookmark_add_outlined,
                      size: 18,
                    ),
                    label: Text(
                      book.inShelf
                          ? '${L.t('已在书架')}${shelf == null ? '' : ' · ${shelf.name}'}'
                          : L.t('加入书架'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      padding: EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _openReader,
                    icon: Icon(Icons.menu_book_outlined, size: 18),
                    label: Text(started ? L.t('继续阅读') : L.t('开始阅读')),
                  ),
                ),
              ],
            ),
          SizedBox(height: 26),
          Divider(),
          SizedBox(height: 14),
          Text(
            '文件信息',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryText,
            ),
          ),
          SizedBox(height: 10),
          SelectableText(
            book.filePath,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.secondaryText,
              height: 1.6,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '支持格式：$kFormatDescription',
            style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.5, color: AppTheme.primaryText),
            ),
          ),
        ],
      ),
    );
  }
}
