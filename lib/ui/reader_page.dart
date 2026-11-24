import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../reader/paginator.dart';
import '../services/bookmark_service.dart';
import '../services/library_service.dart';
import '../services/reader_settings.dart';
import 'page_flip.dart';
import 'reader_paper.dart';
import 'reader_sheets.dart';

class ReaderPage extends StatefulWidget {
  final Book book;

  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final LibraryService _lib = LibraryService.instance;

  List<Chapter> _chapters = const [];
  ReaderSettings _settings = ReaderSettings();
  bool _ready = false;

  int _chapterIndex = 0;
  int _pageIndex = 0;
  List<TextPage> _pages = const [];
  String _pageKey = '';
  int _anchorChar = 0;
  bool _wantLastPage = false;
  bool _chrome = false;
  bool _forward = true;

  final Map<String, List<TextPage>> _pageCache = {};
  Timer? _saveTimer;

  // 顶部/底部状态信息
  int? _battery;
  bool _charging = false;
  DateTime _clock = DateTime.now();
  Timer? _clockTimer;
  StreamSubscription<BatteryState>? _batterySub;

  // 书签
  List<Bookmark> _marks = const [];

  // 拖拽进度条时的临时值
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _load();
    _initBattery();
    _clock = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _clock = DateTime.now());
    });
  }

  Future<void> _load() async {
    final settings = await ReaderSettings.load();
    await _applyImmersive(settings);
    final chapters = await _lib.chaptersFor(widget.book);
    await BookmarkService.instance.loadFor(_lib.account);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _chapters = chapters;
      _ready = true;
      _chapterIndex = chapters.isEmpty
          ? 0
          : widget.book.lastChapter.clamp(0, chapters.length - 1);
      _anchorChar = widget.book.lastCharOffset;
      _pageKey = '';
      _marks = BookmarkService.instance.forBook(widget.book.id);
    });
    unawaited(_lib.touchOpened(widget.book));
  }

  Future<void> _applyImmersive(ReaderSettings settings) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(
      settings.immersive
          ? SystemUiMode.immersiveSticky
          : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _initBattery() async {
    final battery = Battery();
    try {
      final level = await battery.batteryLevel;
      BatteryState state = BatteryState.unknown;
      try {
        state = await battery.batteryState;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _battery = level;
          _charging =
              state == BatteryState.charging || state == BatteryState.full;
        });
      }
      _batterySub = battery.onBatteryStateChanged.listen((state) async {
        try {
          final level = await battery.batteryLevel;
          if (!mounted) return;
          setState(() {
            _battery = level;
            _charging =
                state == BatteryState.charging || state == BatteryState.full;
          });
        } catch (_) {}
      });
    } catch (_) {
      // 桌面设备无电池或插件不可用时忽略
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _clockTimer?.cancel();
    final batterySub = _batterySub;
    if (batterySub != null) unawaited(batterySub.cancel());
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    unawaited(_saveNow());
    super.dispose();
  }

  // ───────────────────────── 排版与翻页 ─────────────────────────

  double get _pagePadTop => math.max(10.0, _settings.marginV * 0.45);
  double get _pagePadBottom => math.max(6.0, _settings.marginV * 0.25);

  void _syncLayout(double width, double height) {
    if (_chapters.isEmpty) return;
    final chapter = _chapters[_chapterIndex];
    final key = [
      _chapterIndex,
      _settings.fontSize,
      _settings.lineHeight,
      _settings.fontFamily,
      _settings.marginH,
      _settings.marginV,
      width.toStringAsFixed(1),
      height.toStringAsFixed(1),
    ].join('|');

    final pages = _pageCache.putIfAbsent(
      key,
      () => paginate(
        text: chapter.text,
        style: _settings.textStyle,
        width: width - _settings.marginH * 2,
        height: height - _pagePadTop - _pagePadBottom,
      ),
    );
    _pages = pages;

    if (key != _pageKey) {
      _pageKey = key;
      final target = _wantLastPage
          ? pages.length - 1
          : pageIndexForOffset(pages, _anchorChar).clamp(0, pages.length - 1);
      _wantLastPage = false;
      _pageIndex = target;
    }
  }

  int _currentPageSafe() =>
      _pageIndex.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);

  int _currentCharOffset() {
    if (_pages.isEmpty) return 0;
    return _pages[_currentPageSafe()].start;
  }

  double get _chapterProgress {
    if (_chapters.isEmpty) return 0;
    final chapter = _chapters[_chapterIndex];
    if (widget.book.charCount <= 0) return 0;
    return ((chapter.charStart + _currentCharOffset()) / widget.book.charCount)
        .clamp(0.0, 1.0);
  }

  String get _chapterTitle =>
      _chapters.isEmpty ? '' : _chapters[_chapterIndex].title;

  void _goChapter(int index, {int charOffset = 0, bool lastPage = false}) {
    if (_chapters.isEmpty) return;
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _chapterIndex = index;
      _anchorChar = charOffset;
      _wantLastPage = lastPage;
      _pageKey = '';
      _chrome = false;
    });
    _scheduleSave();
  }

  void _nextPage() {
    if (_pages.isEmpty) return;
    _forward = true;
    if (_pageIndex < _pages.length - 1) {
      setState(() {
        _pageIndex++;
        _anchorChar = _pages[_pageIndex].start;
      });
      _scheduleSave();
      return;
    }
    if (_pageIndex == _pages.length - 1) {
      setState(() => _pageIndex = _pages.length); // 末页：本章完卡片
      return;
    }
    if (_chapterIndex < _chapters.length - 1) {
      _goChapter(_chapterIndex + 1);
    } else {
      _toast('已经是最后一章了');
    }
  }

  void _prevPage() {
    if (_pages.isEmpty) return;
    _forward = false;
    if (_pageIndex > 0) {
      final target = _pageIndex >= _pages.length
          ? _pages.length - 1
          : _pageIndex - 1;
      setState(() {
        _pageIndex = target;
        _anchorChar = _pages[target].start;
      });
      _scheduleSave();
      return;
    }
    if (_chapterIndex > 0) {
      _goChapter(_chapterIndex - 1, lastPage: true);
    } else {
      _toast('已经是第一章了');
    }
  }

  void _handleTap(double dx, double width) {
    if (_chrome) {
      setState(() => _chrome = false);
      return;
    }
    final leftIsPrev = _settings.tapZone != 'rightPrev';
    if (dx < width * 0.28) {
      if (leftIsPrev) {
        _prevPage();
      } else {
        _nextPage();
      }
    } else if (dx > width * 0.72) {
      if (leftIsPrev) {
        _nextPage();
      } else {
        _prevPage();
      }
    } else {
      setState(() => _chrome = true);
    }
  }

  void _jumpToProgress(double value) {
    if (widget.book.charCount <= 0 || _chapters.isEmpty) return;
    final target = (value * widget.book.charCount).round().clamp(
      0,
      widget.book.charCount - 1,
    );
    var idx = _chapters.length - 1;
    for (var i = 0; i < _chapters.length; i++) {
      final ch = _chapters[i];
      if (target < ch.charStart + ch.text.length) {
        idx = i;
        break;
      }
    }
    final ch = _chapters[idx];
    final offset = (target - ch.charStart).clamp(0, ch.text.length);
    _goChapter(idx, charOffset: offset);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_saveNow()),
    );
  }

  Future<void> _saveNow() async {
    if (_chapters.isEmpty) return;
    final offset = _currentCharOffset();
    final chapter = _chapters[_chapterIndex];
    final progress = widget.book.charCount == 0
        ? 0.0
        : (chapter.charStart + offset) / widget.book.charCount;
    await _lib.updateProgress(
      widget.book,
      chapter: _chapterIndex,
      charOffset: offset,
      progress: progress,
    );
    // 通知首页刷新“继续阅读”卡片的章节与进度。
    _lib.refresh();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _settings.skin.foreground.withValues(alpha: 0.86),
        ),
      );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.pageDown) {
      _nextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _prevPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_chrome) {
        setState(() => _chrome = false);
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ───────────────────────── 弹层 ─────────────────────────

  void _openToc() {
    showTocSheet(
      context,
      chapters: _chapters,
      currentIndex: _chapterIndex,
      skin: _settings.skin,
      onSelected: (i) => _goChapter(i),
    );
  }

  void _openSettings() {
    showReaderSettingsSheet(
      context,
      initial: _settings,
      onChanged: (next) {
        setState(() => _settings = next);
        unawaited(_applyImmersive(next));
        unawaited(next.save());
      },
    );
  }

  void _openQuickOptions() {
    showQuickOptionsSheet(
      context,
      initial: _settings,
      onChanged: (next) {
        setState(() => _settings = next);
        unawaited(_applyImmersive(next));
        unawaited(next.save());
      },
    );
  }

  void _openSearch() {
    showSearchSheet(
      context,
      chapters: _chapters,
      skin: _settings.skin,
      onJump: (chapter, offset) => _goChapter(
        chapter.clamp(0, _chapters.length - 1),
        charOffset: offset,
      ),
    );
  }

  Future<void> _openBookmarks() async {
    await showBookmarksSheet(
      context,
      skin: _settings.skin,
      bookmarksOf: () => _marks,
      onAdd: () async {
        final chapter = _chapters[_chapterIndex];
        final offset = _currentCharOffset();
        await BookmarkService.instance.add(
          bookId: widget.book.id,
          chapter: _chapterIndex,
          charOffset: offset,
          chapterTitle: chapter.title,
          snippet: _bookmarkSnippet(chapter.text, offset),
        );
        if (mounted)
          setState(
            () => _marks = BookmarkService.instance.forBook(widget.book.id),
          );
        _toast('已添加书签');
      },
      onDelete: (mark) async {
        await BookmarkService.instance.remove(mark.id);
        if (mounted)
          setState(
            () => _marks = BookmarkService.instance.forBook(widget.book.id),
          );
      },
      onJump: (mark) => _goChapter(
        mark.chapter.clamp(0, _chapters.length - 1),
        charOffset: mark.charOffset,
      ),
    );
  }

  String _bookmarkSnippet(String text, int offset) {
    final start = offset.clamp(0, text.length);
    final end = (start + 46).clamp(0, text.length);
    return text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ───────────────────────── 界面 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final skin = _settings.skin;
    return Scaffold(
      backgroundColor: skin.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: !_ready
            ? Center(child: CircularProgressIndicator(color: skin.accent))
            : _chapters.isEmpty
            ? _missingView(skin)
            : Stack(
                children: [
                  Positioned.fill(child: _contentLayer(skin)),
                  _chromeLayer(skin),
                ],
              ),
      ),
    );
  }

  /// 第二层：内容层（章节标题 + 正文 + 底部状态栏）
  Widget _contentLayer(ReaderSkin skin) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        SizedBox(height: topPad),
        SizedBox(
          height: 26,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: skin.foreground.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              _syncLayout(constraints.maxWidth, constraints.maxHeight);
              return _pageArea(skin);
            },
          ),
        ),
        if (_settings.showStatusBar)
          SizedBox(height: 24, child: _statusRow(skin))
        else
          SizedBox(height: 6),
        SizedBox(height: bottomPad),
      ],
    );
  }

  Widget _pageArea(ReaderSkin skin) {
    final chapter = _chapters[_chapterIndex];
    final atEnd = _pages.isNotEmpty && _pageIndex >= _pages.length;
    final Widget content;
    if (_pages.isEmpty) {
      content = const SizedBox.shrink();
    } else if (atEnd) {
      content = _endCard(skin);
    } else {
      content = _pageText(skin, chapter.text, _pages[_currentPageSafe()]);
    }
    final pageId =
        'c$_chapterIndex|p$_pageIndex|n${_pages.length}|m${_settings.marginH}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _handleTap(
        details.localPosition.dx,
        MediaQuery.sizeOf(context).width,
      ),
      onHorizontalDragEnd: (details) {
        if (_chrome) return;
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -260) {
          _nextPage();
        } else if (velocity > 260) {
          _prevPage();
        }
      },
      onVerticalDragEnd: (details) {
        if (_chrome) return;
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -260) {
          _nextPage();
        } else if (velocity > 260) {
          _prevPage();
        }
      },
      child: PageFlipTransition(
        pageId: pageId,
        style: _settings.flipStyle,
        forward: _forward,
        duration: _settings.pageTurnDuration,
        backgroundColor: skin.background,
        child: content,
      ),
    );
  }

  Widget _pageText(ReaderSkin skin, String text, TextPage page) {
    final body = (page.end > page.start && page.start < text.length)
        ? text.substring(
            page.start.clamp(0, text.length),
            page.end.clamp(0, text.length),
          )
        : '';
    return PaperBackground(
      skin: skin,
      child: SizedBox.expand(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _settings.marginH,
            _pagePadTop,
            _settings.marginH,
            _pagePadBottom,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: MediaQuery.withNoTextScaling(
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  body,
                  textAlign: _settings.textAlign == 'justify'
                      ? TextAlign.justify
                      : TextAlign.left,
                  style: _settings.textStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusRow(ReaderSkin skin) {
    final muted = skin.foreground.withValues(alpha: 0.46);
    final style = TextStyle(fontSize: 10.5, color: muted, height: 1.2);
    final hour = _clock.hour.toString().padLeft(2, '0');
    final minute = _clock.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左：电量 + 时间，作为一个整体左对齐
          Expanded(
            flex: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_battery != null) ...[
                  Icon(_batteryIcon(_battery!), size: 13.5, color: muted),
                  const SizedBox(width: 3),
                  Text('$_battery%', style: style),
                  const SizedBox(width: 8),
                ],
                Text('$hour:$minute', style: style),
              ],
            ),
          ),
          // 中：书名，始终居中
          Expanded(
            flex: 5,
            child: Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          // 右：进度百分比，右对齐（与左侧等宽，保证书名真正居中）
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(_chapterProgress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10.5,
                  color: skin.accent.withValues(alpha: 0.8),
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _batteryIcon(int level) {
    if (_charging) return Icons.battery_charging_full;
    if (level >= 90) return Icons.battery_full;
    if (level >= 70) return Icons.battery_6_bar;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 30) return Icons.battery_3_bar;
    if (level >= 15) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Widget _endCard(ReaderSkin skin) {
    final isLast = _chapterIndex >= _chapters.length - 1;
    return PaperBackground(
      skin: skin,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 44,
                  color: skin.accent.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 18),
                Text(
                  isLast ? '全书完' : '本章完',
                  style: TextStyle(
                    fontSize: 18,
                    color: skin.foreground,
                    fontWeight: FontWeight.w600,
                    fontFamily: _settings.fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _chapterTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: skin.foreground.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 26),
                if (!isLast)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: skin.accent.withValues(alpha: 0.9),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _goChapter(_chapterIndex + 1),
                    child: Text(
                      '下一章 · ${_chapters[_chapterIndex + 1].title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: skin.accent.withValues(alpha: 0.9),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('返回书架'),
                  ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _openToc,
                  child: Text('查看目录', style: TextStyle(color: skin.accent)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 第一层：菜单层（返回 / 选项 / 搜索 / 目录 / 书签 / 主题 / 全书进度）
  Widget _chromeLayer(ReaderSkin skin) {
    return IgnorePointer(
      ignoring: !_chrome,
      child: AnimatedOpacity(
        opacity: _chrome ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _chrome = false),
                child: Container(
                  color: Colors.black.withValues(
                    alpha: skin.id == 'night' ? 0.4 : 0.22,
                  ),
                ),
              ),
            ),
            Align(alignment: Alignment.topCenter, child: _topBar(skin)),
            Align(alignment: Alignment.bottomCenter, child: _bottomPanel(skin)),
          ],
        ),
      ),
    );
  }

  Widget _topBar(ReaderSkin skin) {
    final surface = skin.background.withValues(alpha: 0.98);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          bottom: BorderSide(color: skin.foreground.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: skin.foreground.withValues(alpha: 0.8),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: '返回',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: skin.foreground,
                      ),
                    ),
                    Text(
                      widget.book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: skin.foreground.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.tune,
                  size: 20,
                  color: skin.foreground.withValues(alpha: 0.75),
                ),
                onPressed: _openQuickOptions,
                tooltip: '选项',
              ),
              IconButton(
                icon: Icon(
                  Icons.search,
                  size: 20,
                  color: skin.foreground.withValues(alpha: 0.75),
                ),
                onPressed: _openSearch,
                tooltip: '搜索',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel(ReaderSkin skin) {
    final surface = skin.background.withValues(alpha: 0.98);
    final progress = _chapterProgress;
    final sliderValue = (_dragValue ?? progress).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(color: skin.foreground.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _toolItem(skin, Icons.menu_book_outlined, '目录', _openToc),
                  _toolItem(
                    skin,
                    Icons.bookmark_border,
                    '书签',
                    () => unawaited(_openBookmarks()),
                  ),
                  _toolItem(skin, Icons.palette_outlined, '主题', _openSettings),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                child: Row(
                  children: [
                    Text(
                      '第 ${_chapterIndex + 1} / ${_chapters.length} 章',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: skin.foreground.withValues(alpha: 0.45),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(sliderValue * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: skin.accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: skin.accent.withValues(alpha: 0.75),
                  inactiveTrackColor: skin.foreground.withValues(alpha: 0.14),
                  thumbColor: skin.accent,
                  trackHeight: 2,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: sliderValue,
                  onChanged: (v) => setState(() => _dragValue = v),
                  onChangeEnd: (v) {
                    _jumpToProgress(v);
                    setState(() => _dragValue = null);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolItem(
    ReaderSkin skin,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Icon(
                icon,
                size: 21,
                color: skin.foreground.withValues(alpha: 0.72),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: skin.foreground.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missingView(ReaderSkin skin) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 40,
              color: skin.foreground.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              '读不到这本书的文件',
              style: TextStyle(fontSize: 15, color: skin.foreground),
            ),
            const SizedBox(height: 6),
            Text(
              widget.book.filePath,
              style: TextStyle(
                fontSize: 12,
                color: skin.foreground.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('返回书架', style: TextStyle(color: skin.accent)),
            ),
          ],
        ),
      ),
    );
  }
}
