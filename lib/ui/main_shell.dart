import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/cover_service.dart';
import '../services/library_service.dart';
import '../services/one_drive_service.dart';
import '../services/open_file_service.dart';
import '../services/shelf_service.dart';
import 'app_theme.dart';
import 'home_page.dart';
import 'reader_page.dart';
import 'settings_page.dart';
import 'shelf_page.dart';
import 'strings.dart';

/// 主框架：底部三栏导航（首页 / 书架 / 设置）
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.onBootSettled});

  /// 启动数据准备完成（或失败）时通知开屏层，避免开屏与主界面各走各的计时。
  final VoidCallback? onBootSettled;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _ready = false;
  String? _bootError;
  final AppSettings _settings = AppSettings.instance;

  final ValueNotifier<double> _lensSlot = ValueNotifier<double>(0);
  late final AnimationController _lensAnim;
  double _lensAnimBegin = 0;
  double _lensAnimTarget = 0;
  double _dragStartSlot = 0;
  double _dragDistance = 0;
  double _navItemWidth = 0;
  bool _draggingLens = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _lensAnim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 260),
    )..addListener(_onLensTick);
    _boot();
  }

  void _onLensTick() {
    final t = Curves.easeOutCubic.transform(_lensAnim.value);
    _lensSlot.value = _lensAnimBegin + (_lensAnimTarget - _lensAnimBegin) * t;
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _startLensDrag(DragStartDetails details) {
    _lensAnim.stop();
    _dragStartSlot = _lensSlot.value;
    _dragDistance = 0;
    setState(() => _draggingLens = true);
    HapticFeedback.selectionClick();
  }

  void _updateLensDrag(DragUpdateDetails details) {
    if (_navItemWidth <= 0) return;
    _dragDistance += details.delta.dx;
    _lensSlot.value = (_dragStartSlot + _dragDistance / _navItemWidth).clamp(
      0.0,
      2.0,
    );
  }

  void _endLensDrag([DragEndDetails? details]) {
    if (!_draggingLens) return;
    final target = _lensSlot.value.roundToDouble();
    final nextIndex = target.toInt();
    final changed = nextIndex != _index;
    setState(() {
      _draggingLens = false;
      if (changed) _index = nextIndex;
    });
    if (changed) HapticFeedback.selectionClick();
    _animateLensTo(target);
  }

  void _selectTab(int index) {
    final changed = index != _index;
    setState(() {
      _index = index;
      _draggingLens = false;
    });
    if (changed) HapticFeedback.selectionClick();
    _animateLensTo(index.toDouble());
  }

  void _animateLensTo(double target) {
    if ((target - _lensSlot.value).abs() < 0.001) return;
    _lensAnim.stop();
    _lensAnimBegin = _lensSlot.value;
    _lensAnimTarget = target;
    _lensAnim.forward(from: 0);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _lensAnim.dispose();
    _lensSlot.dispose();
    OpenFileService.instance.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await AppSettings.instance.load();
      final auth = AuthService.instance;
      await auth.ensureLoaded();
      await ShelfService.instance.load();
      await LibraryService.instance.loadFor(auth.currentAccount);
      await _normalizeShelfIds();
      await OneDriveService.instance.load();
      if (mounted) setState(() => _ready = true);
      widget.onBootSettled?.call();

      // 封面补齐与「打开方式」进来的文件都在后台处理，不阻塞启动
      unawaited(
        CoverService.instance.ensureCovers().then((_) {
          if (mounted) setState(() {});
        }),
      );
      unawaited(_openPendingExternal());
      OpenFileService.instance.startWatching((path) {
        unawaited(_openExternal(path));
      });

      // 启动后自动同步：先补齐云端书籍，再上传本地新增
      if (AppSettings.instance.autoSync &&
          OneDriveService.instance.connected &&
          OneDriveService.instance.available) {
        unawaited(_autoSync());
      }
    } catch (error) {
      if (mounted) setState(() => _bootError = error.toString());
      widget.onBootSettled?.call();
    }
  }

  Future<void> _normalizeShelfIds() async {
    final valid = ShelfService.instance.shelves.map((s) => s.id).toSet();
    var changed = false;
    for (final book in LibraryService.instance.books) {
      if (book.shelfId.isNotEmpty && !valid.contains(book.shelfId)) {
        book.shelfId = '';
        book.inShelf = false;
        changed = true;
      }
    }
    if (changed) await LibraryService.instance.save();
  }

  Future<void> _openPendingExternal() async {
    final path = await OpenFileService.instance.takeInitial();
    if (path != null) await _openExternal(path);
  }

  Future<void> _openExternal(String path) async {
    final book = await LibraryService.instance.importExternal(path);
    if (!mounted) return;
    if (book == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('无法打开这个文件，支持 TXT / EPUB / MOBI / AZW3')),
        );
      return;
    }
    book.inShelf = false;
    book.shelfId = '';
    await LibraryService.instance.save();
    LibraryService.instance.refresh();
    unawaited(CoverService.instance.ensureCovers());
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(book: book)));
  }

  Future<void> _autoSync() async {
    final lib = LibraryService.instance;
    try {
      final drive = OneDriveService.instance;
      await drive.downloadMissing();
      await lib.scanBooksFolder();
      await CoverService.instance.ensureCovers();
      await drive.uploadBooks();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      final error = _bootError;
      return Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Center(
          child: error == null
              ? CircularProgressIndicator(color: AppTheme.accent)
              : Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: AppTheme.accent,
                        size: 42,
                      ),
                      SizedBox(height: 12),
                      Text(
                        '启动失败，请重试',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppTheme.primaryText,
                        ),
                      ),
                      SizedBox(height: 8),
                      SelectableText(
                        error,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                      SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                        ),
                        onPressed: () {
                          setState(() {
                            _bootError = null;
                            _ready = false;
                          });
                          _boot();
                        },
                        child: Text('重试'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [HomePage(), ShelfPage(), SettingsPage()],
              ),
            ),
            _bottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _bottomNav() {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final isNight = AppTheme.isNight;
    final rimColor = isNight
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.72);
    return SizedBox(
      height: 82 + bottomInset,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, 10 + bottomInset),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 680),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.shadow,
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                  BoxShadow(
                    color: isNight
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.white.withValues(alpha: 0.5),
                    blurRadius: 2,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.surface.withValues(
                            alpha: isNight ? 0.78 : 0.9,
                          ),
                          AppTheme.surface.withValues(
                            alpha: isNight ? 0.58 : 0.68,
                          ),
                        ],
                      ),
                      border: Border.all(color: rimColor),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemWidth = constraints.maxWidth / 3;
                        _navItemWidth = itemWidth;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _lensSlot,
                                builder: (context, slot, child) {
                                  return Stack(
                                    children: [
                                      Positioned(
                                        left: itemWidth * slot + 6,
                                        top: 3,
                                        width: itemWidth - 12,
                                        height: 58,
                                        child: IgnorePointer(
                                          child: _glassLens(),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            Row(
                              children: [
                                _navItem(
                                  0,
                                  Icons.home_outlined,
                                  Icons.home,
                                  L.t('首页'),
                                ),
                                _navItem(
                                  1,
                                  Icons.bookmarks_outlined,
                                  Icons.bookmarks,
                                  L.t('书架'),
                                ),
                                _navItem(
                                  2,
                                  Icons.settings_outlined,
                                  Icons.settings,
                                  L.t('设置'),
                                ),
                              ],
                            ),
                            Positioned.fill(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _lensSlot,
                                builder: (context, slot, child) {
                                  return Stack(
                                    children: [
                                      Positioned(
                                        left: itemWidth * slot + 6,
                                        top: 3,
                                        width: itemWidth - 12,
                                        height: 58,
                                        child: MouseRegion(
                                          cursor: _draggingLens
                                              ? SystemMouseCursors.grabbing
                                              : SystemMouseCursors.grab,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onHorizontalDragStart:
                                                _startLensDrag,
                                            onHorizontalDragUpdate:
                                                _updateLensDrag,
                                            onHorizontalDragEnd: _endLensDrag,
                                            onHorizontalDragCancel: () =>
                                                _endLensDrag(),
                                            child: const SizedBox.expand(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 当前栏目上的一层透明玻璃罩：磨砂、边缘高光和顶部反光。
  Widget _glassLens() {
    final isNight = AppTheme.isNight;
    final isPaper = AppTheme.isPaper;
    final radius = 29.0;
    final topColor = isNight
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.70);
    final bottomColor = isNight
        ? Colors.white.withValues(alpha: 0.055)
        : AppTheme.divider.withValues(alpha: 0.50);
    final rimColor = isNight
        ? Colors.white.withValues(alpha: 0.22)
        : (isPaper
              ? const Color(0xFFB49B7E).withValues(alpha: 0.38)
              : const Color(0xFFB8BCC4).withValues(alpha: 0.34));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: isNight
                ? Colors.black.withValues(alpha: 0.42)
                : AppTheme.primaryText.withValues(
                    alpha: isPaper ? 0.10 : 0.075,
                  ),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
          BoxShadow(
            color: isNight
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.5),
            blurRadius: 1.5,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [topColor, bottomColor],
              ),
              border: Border.all(color: rimColor, width: 1.2),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 14,
                  top: 4,
                  right: 14,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: isNight ? 0.12 : 0.45),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 2,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.primaryText.withValues(
                            alpha: isNight ? 0.0 : 0.035,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final active = _index == index;
    final color = active ? AppTheme.accent : AppTheme.secondaryText;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(27),
            splashColor: AppTheme.accent.withValues(alpha: 0.07),
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            mouseCursor: SystemMouseCursors.click,
            onTap: () => _selectTab(index),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: active ? 1.05 : 1.0,
                    duration: Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      active ? activeIcon : icon,
                      size: 22,
                      color: color,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.15,
                      color: color,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
