import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/app_settings.dart';
import '../services/library_service.dart';
import 'app_theme.dart';
import 'book_cover.dart';
import 'book_detail_page.dart';
import 'import_sheet.dart';
import 'library_list_page.dart';
import 'reader_page.dart';
import 'shelf_picker.dart';
import 'strings.dart';

/// 首页：四个快捷入口 + 可独立滚动的书库抽屉
class HomePage extends StatefulWidget {
  HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LibraryService _lib = LibraryService.instance;
  final AppSettings _settings = AppSettings.instance;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetSize = 0.5;
  double _bodyHeight = 720;
  double _maxSheetSize = 1.0;
  String _recentChapterTitle = '';
  String _recentChapterKey = '';

  @override
  void initState() {
    super.initState();
    _lib.addListener(_onChanged);
    _settings.addListener(_onChanged);
    unawaited(_loadRecentChapter());
  }

  @override
  void dispose() {
    _lib.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    _sheetController.dispose();
    super.dispose();
  }

  void _onDrawerHandleStart(DragStartDetails details) {
    if (_sheetController.isAttached) {
      _sheetSize = _sheetController.size;
    }
  }

  void _onDrawerHandleUpdate(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    final next = (_sheetSize - details.delta.dy / _bodyHeight).clamp(
      0.5,
      _maxSheetSize,
    );
    _sheetSize = next;
    _sheetController.jumpTo(next);
  }

  void _onDrawerHandleEnd(DragEndDetails details) {
    if (!_sheetController.isAttached) return;
    final target = _sheetSize >= (0.5 + _maxSheetSize) / 2
        ? _maxSheetSize
        : 0.5;
    _sheetController.animateTo(
      target,
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_loadRecentChapter());
  }

  Book? get _recentBook {
    final list =
        _lib.books
            .where(
              (b) =>
                  !b.trashed &&
                  (b.progress > 0 ||
                      b.lastChapter > 0 ||
                      b.lastCharOffset > 0 ||
                      b.lastOpenedAt.isAfter(b.addedAt)),
            )
            .toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return list.isEmpty ? null : list.first;
  }

  Future<void> _loadRecentChapter() async {
    final book = _recentBook;
    if (book == null) {
      if (_recentChapterTitle.isNotEmpty) {
        setState(() => _recentChapterTitle = '');
      }
      _recentChapterKey = '';
      return;
    }
    final key =
        '${book.id}|${book.lastChapter}|${book.chapterCount}|${book.parserVersion}';
    if (key == _recentChapterKey) return;
    _recentChapterKey = key;
    final chapters = await _lib.chaptersFor(book);
    if (!mounted || _recentBook?.id != book.id || _recentChapterKey != key) {
      return;
    }
    final index = chapters.isEmpty
        ? 0
        : book.lastChapter.clamp(0, chapters.length - 1);
    setState(() {
      _recentChapterTitle = chapters.isEmpty ? '' : chapters[index].title;
    });
  }

  List<Book> get _allBooks {
    final list = _lib.books.where((b) => !b.trashed).toList();
    final cmpMode = _settings.sortMode;
    list.sort((a, b) {
      final cmp = cmpMode == 'viewed'
          ? a.lastOpenedAt.compareTo(b.lastOpenedAt)
          : a.addedAt.compareTo(b.addedAt);
      return _settings.sortDesc ? -cmp : cmp;
    });
    return list;
  }

  int _count(String mode) {
    final source = _lib.books;
    switch (mode) {
      case 'favorites':
        return source.where((b) => b.favorite && !b.trashed).length;
      case 'viewed':
        return source
            .where(
              (b) =>
                  !b.trashed &&
                  (b.progress > 0 || b.lastOpenedAt.isAfter(b.addedAt)),
            )
            .length;
      case 'trash':
        return source.where((b) => b.trashed).length;
      default:
        return source.where((b) => !b.trashed).length;
    }
  }

  void _openDetail(Book book) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BookDetailPage(book: book)));
  }

  void _openReader(Book book) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderPage(book: book)));
  }

  void _openList(String mode) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LibraryListPage(mode: mode)));
  }

  Future<void> _showSortMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L.t('排序'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryText,
                  ),
                ),
                SizedBox(height: 8),
                _radioRow(
                  ctx,
                  L.t('按导入时间'),
                  _settings.sortMode == 'added',
                  () async {
                    await _settings.setSortMode('added');
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                _radioRow(
                  ctx,
                  L.t('按查看时间'),
                  _settings.sortMode == 'viewed',
                  () async {
                    await _settings.setSortMode('viewed');
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                Divider(height: 20),
                _radioRow(ctx, L.t('倒序'), _settings.sortDesc, () async {
                  if (!_settings.sortDesc) await _settings.toggleSortOrder();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }),
                _radioRow(ctx, L.t('正序'), !_settings.sortDesc, () async {
                  if (_settings.sortDesc) await _settings.toggleSortOrder();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _radioRow(
    BuildContext ctx,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: TextStyle(fontSize: 14, color: AppTheme.primaryText),
      ),
      trailing: selected
          ? Icon(Icons.check, size: 19, color: AppTheme.accent)
          : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _allBooks;
    final recent = _recentBook;
    final compact = _settings.layout == 'compact';
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.canvas.withValues(alpha: 0.72),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.divider.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 22,
        title: Text(
          L.t('丹青阅读'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryText,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            tooltip: L.t('布局'),
            onPressed: () => _settings.setLayout(compact ? 'loose' : 'compact'),
            icon: Icon(
              compact ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
              size: 19,
              color: AppTheme.secondaryText,
            ),
          ),
          IconButton(
            tooltip: L.t('排序'),
            onPressed: _showSortMenu,
            icon: Icon(
              Icons.swap_vert,
              size: 21,
              color: AppTheme.secondaryText,
            ),
          ),
          IconButton(
            tooltip: L.t('添加与书库管理'),
            onPressed: () => showAddSourceSheet(context),
            icon: Icon(Icons.add_circle, size: 23, color: AppTheme.accent),
          ),
          SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bodyConstraints) {
          _bodyHeight = bodyConstraints.maxHeight;
          final topOffset =
              MediaQuery.viewPaddingOf(context).top + kToolbarHeight;
          _maxSheetSize = bodyConstraints.maxHeight <= topOffset
              ? 1.0
              : (1 - topOffset / bodyConstraints.maxHeight).clamp(0.5, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.backgroundGradient,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height:
                            MediaQuery.viewPaddingOf(context).top +
                            kToolbarHeight,
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(22, 18, 22, 0),
                        child: Row(
                          children: [
                            Text(
                              L.t('快捷入口'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.secondaryText,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '书库与阅读记录',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.secondaryText.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                            Spacer(),
                            Text(
                              '共 ${books.length} 本',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.secondaryText.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: _quickSection(),
                      ),
                      if (recent != null)
                        _recentSection(recent)
                      else if (bodyConstraints.maxWidth >= 760) ...[
                        const SizedBox(height: 24),
                        _brandWatermark(),
                      ],
                      const SizedBox(height: 16),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: 0.5,
                  minChildSize: 0.5,
                  maxChildSize: _maxSheetSize,
                  snap: true,
                  snapSizes: [0.5, _maxSheetSize],
                  builder: (ctx, scrollController) =>
                      _libraryDrawer(books, compact, scrollController),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────── 二级入口 ─────────────────────────

  Widget _quickSection() {
    final items = [
      (mode: 'favorites', icon: Icons.favorite_border, label: '我的喜爱'),
      (mode: 'added', icon: Icons.fiber_new_outlined, label: '最近添加'),
      (mode: 'viewed', icon: Icons.history, label: '最近阅读'),
      (mode: 'trash', icon: Icons.delete_outline, label: '回收站'),
    ];
    return LayoutBuilder(
      builder: (ctx, c) {
        final columns = c.maxWidth >= 700 ? 4 : 2;
        return GridView(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 70,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          children: [
            for (final item in items)
              _quickCard(
                mode: item.mode,
                icon: item.icon,
                label: item.label,
                count: _count(item.mode),
              ),
          ],
        );
      },
    );
  }

  Widget _recentSection(Book book) {
    final chapter = _recentChapterTitle.isEmpty
        ? '第 ${book.lastChapter + 1} 章'
        : _recentChapterTitle;
    final percent = (book.progress * 100).clamp(0, 100);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_stories_outlined,
                size: 17,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 7),
              Text(
                '继续阅读',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryText,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '上次读到这里',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.secondaryText.withValues(alpha: 0.65),
                ),
              ),
              const Spacer(),
              Text(
                percent <= 0 ? '未开始' : '已读 ${percent.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppTheme.secondaryText.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final narrow = constraints.maxWidth < 620;
              final coverWidth = narrow ? 54.0 : 64.0;
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.divider.withValues(alpha: 0.9),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.shadow.withValues(alpha: 0.55),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openReader(book),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        narrow ? 12 : 14,
                        narrow ? 12 : 14,
                        narrow ? 12 : 16,
                        narrow ? 12 : 14,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: coverWidth,
                            child: BookCover(
                              book: book,
                              titleSize: narrow ? 8.5 : 10,
                              showProgress: false,
                            ),
                          ),
                          SizedBox(width: narrow ? 12 : 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: narrow ? 15 : 17,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryText,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '读到：$chapter',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: narrow ? 11 : 12,
                                    color: AppTheme.secondaryText,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: LinearProgressIndicator(
                                          value: book.progress
                                              .clamp(0.0, 1.0)
                                              .toDouble(),
                                          minHeight: 3,
                                          backgroundColor: AppTheme.divider
                                              .withValues(alpha: 0.55),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                AppTheme.accent,
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${percent.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppTheme.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: narrow ? 8 : 14),
                          Container(
                            width: narrow ? 34 : 38,
                            height: narrow ? 34 : 38,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: narrow ? 18 : 20,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _brandWatermark() {
    final markColor = AppTheme.primaryText.withValues(
      alpha: AppTheme.isNight ? 0.10 : 0.065,
    );
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'W',
            style: TextStyle(
              fontSize: 54,
              height: 1,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              letterSpacing: 3,
              color: markColor,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 28,
            height: 1,
            color: AppTheme.divider.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 12),
          Text(
            '万物皆可阅',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 5,
              color: AppTheme.secondaryText.withValues(alpha: 0.42),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickCard({
    required String mode,
    required IconData icon,
    required String label,
    required int count,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openList(mode),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.subtleCanvas,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: AppTheme.accent),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    L.t(label),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryText,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '$count 本',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 17, color: AppTheme.secondaryText),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 书库抽屉（内部独立滚动） ─────────────────────────

  Widget _libraryDrawer(
    List<Book> books,
    bool compact,
    ScrollController controller,
  ) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: AppTheme.divider)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.shadow,
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _onDrawerHandleStart,
            onVerticalDragUpdate: _onDrawerHandleUpdate,
            onVerticalDragEnd: _onDrawerHandleEnd,
            child: _drawerHeader(books.length),
          ),
          Expanded(
            child: CustomScrollView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (books.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _emptyView())
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 24),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: compact ? 118.0 : 190.0,
                        mainAxisSpacing: compact ? 14 : 22,
                        crossAxisSpacing: compact ? 12 : 20,
                        childAspectRatio: compact ? 0.58 : 0.62,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _bookTile(books[i], compact),
                        childCount: books.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerHeader(int count) {
    return Container(
      height: 52,
      color: AppTheme.surface,
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 9),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.primaryText.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(22, 10, 22, 6),
            child: Row(
              children: [
                Text(
                  L.t('全部书籍'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryText,
                  ),
                ),
                Spacer(),
                Text(
                  '上拉查看全部',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.secondaryText.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookTile(Book book, bool compact) {
    return GestureDetector(
      onTap: () => _openDetail(book),
      onLongPress: () async {
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
                child: Text(
                  L.t('删除'),
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true) await _lib.moveToTrash(book);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              BookCover(book: book, titleSize: compact ? 12.5 : 15),
              Positioned(
                top: 3,
                right: 3,
                child: Column(
                  children: [
                    Tooltip(
                      message: book.favorite ? '取消喜爱' : '我的喜爱',
                      child: GestureDetector(
                        onTap: () => _lib.toggleFavorite(book),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            book.favorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 14,
                            color: book.favorite
                                ? Colors.redAccent
                                : AppTheme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 5),
                    Tooltip(
                      message: book.shelfId.isEmpty ? '加入书架' : '已在书架',
                      child: GestureDetector(
                        onTap: () async {
                          await showAddToShelfSheet(context, book);
                          if (mounted) setState(() {});
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            book.shelfId.isEmpty ? Icons.add : Icons.check,
                            size: 15,
                            color: book.shelfId.isEmpty
                                ? AppTheme.accent
                                : AppTheme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ],
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
              style: TextStyle(fontSize: 10.5, color: AppTheme.secondaryText),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyView() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 18, horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 44,
            color: AppTheme.accent.withValues(alpha: 0.45),
          ),
          SizedBox(height: 12),
          Text(
            '书库还是空的',
            style: TextStyle(fontSize: 15, color: AppTheme.primaryText),
          ),
          SizedBox(height: 6),
          Text(
            '点右上角 + 从本地、文件夹或 OneDrive 导入电子书',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppTheme.secondaryText,
            ),
          ),
          SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => showAddSourceSheet(context),
            icon: Icon(Icons.add, size: 18),
            label: Text(L.t('导入电子书')),
          ),
        ],
      ),
    );
  }
}
