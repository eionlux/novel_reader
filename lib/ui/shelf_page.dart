import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/app_settings.dart';
import '../services/library_service.dart';
import '../services/shelf_service.dart';
import 'app_theme.dart';
import 'book_cover.dart';
import 'book_detail_page.dart';
import 'reader_page.dart';
import 'shelf_picker.dart';
import 'strings.dart';

/// 书架：搜索、多书架（新建/切换）、刷新
class ShelfPage extends StatefulWidget {
  ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  final LibraryService _lib = LibraryService.instance;
  final ShelfService _shelves = ShelfService.instance;
  final AppSettings _settings = AppSettings.instance;
  final TextEditingController _searchController = TextEditingController();

  String _shelfId = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _lib.addListener(_onChanged);
    _shelves.addListener(_onChanged);
    _settings.addListener(_onChanged);
  }

  @override
  void dispose() {
    _lib.removeListener(_onChanged);
    _shelves.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final valid = _shelves.shelves.any((s) => s.id == _shelfId);
    if (!valid) {
      _shelfId = _shelves.shelves.isEmpty ? '' : _shelves.shelves.first.id;
    }
    setState(() {});
  }

  List<Book> get _books {
    final query = _searchController.text.trim().toLowerCase();
    return _lib.books
        .where((b) => b.inShelf && !b.trashed && b.shelfId == _shelfId)
        .where(
          (b) =>
              query.isEmpty ||
              b.title.toLowerCase().contains(query) ||
              b.author.toLowerCase().contains(query),
        )
        .toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  }

  Future<void> _createShelf() async {
    final shelf = await promptCreateShelf(context);
    if (shelf != null && mounted) {
      setState(() => _shelfId = shelf.id);
    }
  }

  Future<void> _shelfActions(Shelf shelf) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, size: 20),
              title: Text('重命名「${shelf.name}」'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _renameShelf(shelf);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.redAccent,
              ),
              title: Text('删除书架', style: TextStyle(color: Colors.redAccent)),
              subtitle: Text('书架里的书会移出书架，回到全部书籍'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _shelves.delete(shelf);
                if (mounted) {
                  setState(() {
                    _shelfId = _shelves.shelves.isEmpty
                        ? ''
                        : _shelves.shelves.first.id;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameShelf(Shelf shelf) async {
    final controller = TextEditingController(text: shelf.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('重命名书架', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L.t('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(L.t('保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty)
      await _shelves.rename(shelf, name);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(milliseconds: 1500),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        titleSpacing: 22,
        leading: _searching
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: AppTheme.primaryText,
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searching = false);
                },
              )
            : null,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '${L.t('搜索')}书名 / 作者',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondaryText,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(
                L.t('我的书架'),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryText,
                ),
              ),
        actions: [
          if (!_searching)
            IconButton(
              tooltip: L.t('搜索'),
              onPressed: () => setState(() => _searching = true),
              icon: Icon(Icons.search, size: 21, color: AppTheme.secondaryText),
            ),
          IconButton(
            tooltip: L.t('新建书架'),
            onPressed: _createShelf,
            icon: Icon(
              Icons.create_new_folder_outlined,
              size: 21,
              color: AppTheme.secondaryText,
            ),
          ),
          IconButton(
            tooltip: L.t('刷新'),
            onPressed: () async {
              await _lib.reload();
              if (mounted) _snack('已刷新');
            },
            icon: Icon(Icons.refresh, size: 21, color: AppTheme.secondaryText),
          ),
          SizedBox(width: 8),
        ],
      ),
      body: _shelves.shelves.isEmpty
          ? _noShelvesView()
          : Column(
              children: [
                _shelfChips(),
                Expanded(child: books.isEmpty ? _emptyView() : _grid(books)),
              ],
            ),
    );
  }

  Widget _shelfChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: _shelves.shelves.length + 1,
        separatorBuilder: (_, _) => SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          if (i == _shelves.shelves.length) {
            return GestureDetector(
              onTap: _createShelf,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.divider),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 14, color: AppTheme.secondaryText),
                    SizedBox(width: 4),
                    Text(
                      '新建',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final shelf = _shelves.shelves[i];
          final active = shelf.id == _shelfId;
          final count = _lib.books
              .where((b) => b.inShelf && !b.trashed && b.shelfId == shelf.id)
              .length;
          return GestureDetector(
            onTap: () => setState(() => _shelfId = shelf.id),
            onLongPress: () => _shelfActions(shelf),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 160),
              padding: EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.accent.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${shelf.name} · $count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? AppTheme.accent : AppTheme.secondaryText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid(List<Book> books) {
    final compact = _settings.layout == 'compact';
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 24,
            10,
            compact ? 18 : 24,
            28,
          ),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: compact ? 118 : 190,
            mainAxisSpacing: compact ? 14 : 22,
            crossAxisSpacing: compact ? 12 : 20,
            childAspectRatio: compact ? 0.58 : 0.62,
          ),
          itemCount: books.length,
          itemBuilder: (ctx, i) {
            final book = books[i];
            return GestureDetector(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => ReaderPage(book: book))),
              onLongPress: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BookDetailPage(book: book)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(book: book, titleSize: compact ? 12.5 : 15),
                  SizedBox(height: 7),
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryText,
                    ),
                  ),
                  if (!compact) ...[
                    SizedBox(height: 2),
                    Text(
                      '${book.author} · ${book.chapterCount} ${L.t('章')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _noShelvesView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              size: 48,
              color: AppTheme.accent.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              L.t('还没有书架'),
              style: TextStyle(fontSize: 16, color: AppTheme.primaryText),
            ),
            const SizedBox(height: 8),
            Text(
              '先创建一个书架，再从首页「全部书籍」的 + 把书加进来',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppTheme.secondaryText,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.onAccent,
              ),
              onPressed: _createShelf,
              icon: const Icon(Icons.add, size: 18),
              label: Text(L.t('创建书架')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_add_outlined,
              size: 46,
              color: AppTheme.accent.withValues(alpha: 0.45),
            ),
            SizedBox(height: 16),
            Text(
              L.t('还没有加入书架的书'),
              style: TextStyle(fontSize: 16, color: AppTheme.primaryText),
            ),
            SizedBox(height: 8),
            Text(
              L.t('去首页「全部书籍」，点封面右上角的 + 加入书架'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppTheme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
