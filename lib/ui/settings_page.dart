import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/library_service.dart';
import '../services/one_drive_service.dart';
import '../services/reader_settings.dart';
import 'app_theme.dart';
import 'auth_sheet.dart';
import 'reader_sheets.dart';
import 'strings.dart';

/// 设置：账户、通用设置、阅读偏好、云同步（OneDrive 数据源）
class SettingsPage extends StatefulWidget {
  SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AuthService _auth = AuthService.instance;
  final LibraryService _lib = LibraryService.instance;
  final AppSettings _settings = AppSettings.instance;
  final OneDriveService _drive = OneDriveService.instance;
  ReaderSettings _readerSettings = ReaderSettings();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onChanged);
    _settings.addListener(_onChanged);
    _drive.addListener(_onChanged);
    unawaited(_loadReaderSettings());
  }

  Future<void> _loadReaderSettings() async {
    final settings = await ReaderSettings.load();
    if (mounted) setState(() => _readerSettings = settings);
  }

  Future<void> _saveReaderSettings(ReaderSettings next) async {
    if (mounted) setState(() => _readerSettings = next);
    await next.save();
  }

  Future<void> _openReaderSettings() async {
    final settings = await ReaderSettings.load();
    if (!mounted) return;
    setState(() => _readerSettings = settings);
    await showReaderSettingsSheet(
      context,
      initial: settings,
      onChanged: (next) {
        _readerSettings = next;
        unawaited(next.save());
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickReaderFlipStyle() async {
    final value = await _pickOption(L.t('翻页动画'), {
      for (final f in readerFlipStyles) f.id: f.name,
    }, _readerSettings.flipStyle);
    if (value != null) {
      await _saveReaderSettings(_readerSettings.copyWith(flipStyle: value));
    }
  }

  Future<void> _pickReaderTapZone() async {
    final value = await _pickOption(L.t('点击翻页'), {
      'leftPrev': '左侧上一页 / 右侧下一页',
      'rightPrev': '右侧上一页 / 左侧下一页',
    }, _readerSettings.tapZone);
    if (value != null) {
      await _saveReaderSettings(_readerSettings.copyWith(tapZone: value));
    }
  }

  Future<void> _resetReaderSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('恢复默认阅读设置', style: TextStyle(fontSize: 16)),
        content: Text('阅读主题、字号、行距、翻页方式和阅读界面选项都会恢复默认，不会影响书库与阅读进度。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L.t('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _saveReaderSettings(ReaderSettings());
    _snack('阅读设置已恢复默认');
  }

  @override
  void dispose() {
    _auth.removeListener(_onChanged);
    _settings.removeListener(_onChanged);
    _drive.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(milliseconds: 2000),
        ),
      );
  }

  Future<void> _pickOrientation() async {
    final value = await _pickOption(L.t('屏幕方向'), {
      'system': L.t('跟随系统'),
      'portrait': L.t('竖屏'),
      'landscape': L.t('横屏'),
    }, _settings.orientation);
    if (value != null) await _settings.setOrientation(value);
  }

  Future<void> _pickLanguage() async {
    final value = await _pickOption(L.t('语言'), {
      'zh': L.t('中文'),
      'en': L.t('英文'),
    }, _settings.language);
    if (value != null) await _settings.setLanguage(value);
  }

  Future<String?> _pickOption(
    String title,
    Map<String, String> options,
    String current,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryText,
                  ),
                ),
              ),
            ),
            for (final entry in options.entries)
              ListTile(
                dense: true,
                title: Text(
                  entry.value,
                  style: TextStyle(fontSize: 14, color: AppTheme.primaryText),
                ),
                trailing: entry.key == current
                    ? Icon(Icons.check, size: 19, color: AppTheme.accent)
                    : null,
                onTap: () => Navigator.of(ctx).pop(entry.key),
              ),
            SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _cleanInvalid() async {
    final count = await _lib.cleanupInvalid();
    _snack(count == 0 ? '没有发现无效图书' : '已清理 $count 本无效图书（文件已不存在）');
  }

  Future<void> _cleanDuplicates() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(L.t('清理重复图书'), style: TextStyle(fontSize: 16)),
        content: Text(
          '同书名、同大小的重复书籍会只保留一本（优先保留在书架、阅读进度更深的那本），其余从索引移除，原始文件不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(L.t('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(L.t('确定')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await _lib.cleanupDuplicates();
    _snack(count == 0 ? '没有发现重复图书' : '已清理 $count 本重复图书');
  }

  Future<void> _pickMountFolder() async {
    if (Platform.isAndroid) {
      final error = await _drive.pickAndroidAndMount();
      if (!mounted) return;
      if (error != null) {
        _snack(error);
        return;
      }
      if (!_drive.connected) return;
      await _afterMounted();
      return;
    }

    String? path;
    try {
      path = await getDirectoryPath(
        confirmButtonText: '选择这个 OneDrive 文件夹',
        initialDirectory: _drive.detectedLocalRoot,
        canCreateDirectories: false,
      );
    } catch (e) {
      _snack('当前系统无法打开文件夹选择器：$e');
      return;
    }
    if (path == null) return;
    final error = await _drive.mount(path);
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    await _afterMounted();
  }

  Future<void> _mountDetectedFolder() async {
    final path = _drive.detectedLocalRoot;
    if (path == null) {
      _snack('没有找到本机 OneDrive 文件夹，请手动选择');
      return;
    }
    final error = await _drive.mount(path);
    if (!mounted) return;
    if (error != null) {
      _snack(error);
      return;
    }
    await _afterMounted();
  }

  Future<void> _afterMounted() async {
    // 用户挂载后就是要“自动同步到首页书籍”，这里把自动同步一并打开。
    if (!_settings.autoSync) {
      _settings.autoSync = true;
      await _settings.save();
    }
    if (!mounted) return;
    _snack('已挂载 OneDrive 网盘，正在同步书库');
    await _syncDriveNow();
  }

  Future<void> _unmountDrive() async {
    await _drive.unmount();
    if (!mounted) return;
    _snack('已取消挂载，网盘里的文件没有删除');
  }

  Future<void> _syncDriveNow() async {
    if (!_drive.available) {
      _snack('网盘目录当前不可用，请检查 OneDrive 是否已同步完成');
      return;
    }
    await _drive.syncNow();
    if (!mounted) return;
    _snack('同步完成，书库已更新');
  }

  Future<void> _uploadToDrive() async {
    if (!_drive.available) {
      _snack(L.t('需要先在设置里挂载 OneDrive 网盘'));
      return;
    }
    final count = await _drive.uploadBooks();
    if (!mounted) return;
    _snack('已上传 $count 个文件到网盘');
  }

  Future<void> _downloadFromDrive() async {
    if (!_drive.available) {
      _snack(L.t('需要先在设置里挂载 OneDrive 网盘'));
      return;
    }
    final count = await _drive.downloadMissing();
    final imported = await _lib.scanBooksFolder();
    if (!mounted) return;
    _snack('已拉取 $count 个文件${imported > 0 ? '，导入 $imported 本' : ''}');
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = _auth.isLoggedIn;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        titleSpacing: 22,
        title: Text(
          L.t('设置'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryText,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(22, 8, 22, 30),
        children: [
          _accountCard(loggedIn),
          SizedBox(height: 22),
          _groupTitle(L.t('通用设置')),
          _groupCard([
            _valueTile(
              icon: Icons.screen_rotation_outlined,
              title: L.t('屏幕方向'),
              value: _settings.orientation == 'system'
                  ? L.t('跟随系统')
                  : _settings.orientation == 'portrait'
                  ? L.t('竖屏')
                  : L.t('横屏'),
              onTap: _pickOrientation,
            ),
            _divider(),
            _valueTile(
              icon: Icons.language_outlined,
              title: L.t('语言'),
              value: _settings.isEnglish ? 'English' : '中文',
              onTap: _pickLanguage,
            ),
            _divider(),
            _tile(
              icon: Icons.auto_delete_outlined,
              title: L.t('清理无效图书'),
              subtitle: '移除文件已不存在的记录',
              onTap: _cleanInvalid,
            ),
            _divider(),
            _tile(
              icon: Icons.content_copy_outlined,
              title: L.t('清理重复图书'),
              subtitle: '同书名同大小只保留一本',
              onTap: _cleanDuplicates,
            ),
            _divider(),
            _tile(
              icon: Icons.text_fields_outlined,
              title: L.t('字体与排版'),
              subtitle: '主题、字体、字号、行距、边距',
              onTap: _openReaderSettings,
            ),
            _divider(),
            _driveCard(),
            _divider(),
            _tile(
              icon: Icons.info_outline,
              title: L.t('丹青阅读'),
              subtitle:
                  'v1.8.4 · 双端阅读器 · TXT / EPUB / MOBI / AZW3 · OneDrive 网盘挂载',
              onTap: null,
            ),
          ]),
          SizedBox(height: 22),
          _groupTitle(L.t('阅读设置')),
          _groupCard([
            _readerThemeBlock(),
            _divider(),
            _valueTile(
              icon: Icons.animation_outlined,
              title: L.t('翻页动画'),
              value: flipStyleName(_readerSettings.flipStyle),
              onTap: _pickReaderFlipStyle,
            ),
            _divider(),
            _valueTile(
              icon: Icons.touch_app_outlined,
              title: L.t('点击翻页'),
              value: _readerSettings.tapZone == 'rightPrev' ? '右翻左进' : '左翻右进',
              onTap: _pickReaderTapZone,
            ),
            _divider(),
            _readerSwitchTile(
              icon: Icons.fullscreen,
              title: L.t('沉浸式阅读'),
              subtitle: '阅读页隐藏系统状态栏和导航栏',
              value: _readerSettings.immersive,
              onChanged: (v) =>
                  _saveReaderSettings(_readerSettings.copyWith(immersive: v)),
            ),
            _divider(),
            _readerSwitchTile(
              icon: Icons.view_agenda_outlined,
              title: L.t('底部阅读状态栏'),
              subtitle: '显示时间、电量、书名和进度',
              value: _readerSettings.showStatusBar,
              onChanged: (v) => _saveReaderSettings(
                _readerSettings.copyWith(showStatusBar: v),
              ),
            ),
            _divider(),
            _readerSwitchTile(
              icon: Icons.format_align_justify,
              title: L.t('正文两端对齐'),
              subtitle: '让段落左右两侧更整齐',
              value: _readerSettings.textAlign == 'justify',
              onChanged: (v) => _saveReaderSettings(
                _readerSettings.copyWith(textAlign: v ? 'justify' : 'left'),
              ),
            ),
            _divider(),
            _tile(
              icon: Icons.restart_alt,
              title: L.t('恢复默认阅读设置'),
              subtitle: '主题、字号、翻页方式和阅读界面复位',
              onTap: _resetReaderSettings,
            ),
          ]),
          SizedBox(height: 22),
          _groupTitle(L.t('外观')),
          _themeCard(),
        ],
      ),
    );
  }

  Widget _readerThemeBlock() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 22,
                color: AppTheme.primaryText.withValues(alpha: 0.7),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.t('阅读主题'),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AppTheme.primaryText,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '只改变阅读页的背景，不跟随软件配色',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final skin in readerSkins) _readerSkinChoice(skin)],
          ),
        ],
      ),
    );
  }

  Widget _readerSkinChoice(ReaderSkin skin) {
    final selected = _readerSettings.skinId == skin.id;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () =>
            _saveReaderSettings(_readerSettings.copyWith(skinId: skin.id)),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 170),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: skin.background,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: skin.accent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6),
              Text(
                skin.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: skin.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readerSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: AppTheme.primaryText.withValues(alpha: 0.7),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14.5, color: AppTheme.primaryText),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.accent,
            activeTrackColor: AppTheme.accent.withValues(alpha: 0.28),
            inactiveThumbColor: AppTheme.secondaryText,
            inactiveTrackColor: AppTheme.divider.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(List<Widget> children) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.6)),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: AppTheme.divider.withValues(alpha: 0.7),
    );
  }

  Widget _themeCard() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                size: 22,
                color: AppTheme.primaryText.withValues(alpha: 0.7),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L.t('配色方案'),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AppTheme.primaryText,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '只改变软件界面，阅读页内的工具与排版不受影响',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _paletteChoice(AppPalette.mono, L.t('黑白'), [
                  Color(0xFF141416),
                  Color(0xFFF4F4F4),
                  Color(0xFFFFFFFF),
                ]),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _paletteChoice(AppPalette.night, L.t('夜间'), [
                  Color(0xFF0F1113),
                  Color(0xFF1B1E21),
                  Color(0xFFC9A86A),
                ]),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _paletteChoice(AppPalette.paper, L.t('纸质'), [
                  Color(0xFFF5EDDF),
                  Color(0xFFFCF6EA),
                  Color(0xFF8A5E3B),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paletteChoice(
    AppPalette palette,
    String label,
    List<Color> swatches,
  ) {
    final selected = AppTheme.palette == palette;
    return GestureDetector(
      onTap: () async {
        AppTheme.palette = palette;
        await _settings.setPalette(palette.name);
        if (mounted) setState(() {});
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.08)
              : AppTheme.subtleCanvas,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < swatches.length; i++) ...[
                  if (i > 0) SizedBox(width: 4),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: swatches[i],
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.divider, width: 0.6),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppTheme.accent : AppTheme.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(bool loggedIn) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.subtleCanvas,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.accent.withValues(
              alpha: loggedIn ? 0.14 : 0.07,
            ),
            child: Icon(
              loggedIn ? Icons.person : Icons.person_outline,
              size: 28,
              color: AppTheme.accent,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loggedIn ? _auth.displayName : L.t('未登录'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryText,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  loggedIn ? '当前账户的书库与阅读进度独立保存' : '登录后可按账户分别管理书库',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (loggedIn)
            TextButton(
              onPressed: () async {
                _auth.logout();
                await _lib.loadFor(AuthService.guestAccount);
              },
              child: Text(
                L.t('退出登录'),
                style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
              ),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                padding: EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              onPressed: () => showAuthSheet(context),
              child: Text('${L.t('登录')} / ${L.t('注册')}'),
            ),
        ],
      ),
    );
  }

  Widget _driveCard() {
    final connected = _drive.connected;
    final available = _drive.available;
    final writable = _drive.writable;
    final statusColor = !connected
        ? AppTheme.secondaryText
        : (available && writable ? Colors.green.shade700 : Colors.orange.shade800);
    final statusText = !connected
        ? '未挂载'
        : (!available ? '等待授权' : (writable ? '已挂载' : '只读'));
    final detected = Platform.isAndroid ? null : _drive.detectedLocalRoot;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_outlined, size: 22, color: AppTheme.accent),
              SizedBox(width: 10),
              Text(
                'OneDrive 网盘',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryText,
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 10.5, color: statusColor),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            !connected
                ? (Platform.isAndroid
                      ? '在系统文件选择器里选择 OneDrive 文件夹。应用只获得这个文件夹的读写授权，并在其中创建 DanQingReader/books 与 covers；不登录微软账号、不读取其他网盘文件。'
                      : '选择本机已同步的 OneDrive 文件夹。应用只创建并读写其中的 DanQingReader/books 与 DanQingReader/covers，不登录微软账号、不读取网盘里的其他文件。')
                : !available
                ? '已挂载：${_drive.displayPath}\n授权已失效或目录暂不可用，请重新选择这个 OneDrive 文件夹。'
                : '已挂载：${_drive.displayPath}\n网盘目录：${_drive.remoteRootPath}\n书籍放 books，封面放 covers；应用只读写这个子目录。${writable ? '' : '\n当前只有只读授权，上传会被系统拒绝。'}',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: AppTheme.secondaryText,
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!connected) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                  ),
                  onPressed: _pickMountFolder,
                  icon: Icon(Icons.folder_open_outlined, size: 16),
                  label: Text('选择 OneDrive 文件夹'),
                ),
                if (detected != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                    ),
                    onPressed: _mountDetectedFolder,
                    icon: Icon(Icons.auto_awesome_outlined, size: 16),
                    label: Text('使用检测到的 OneDrive'),
                  ),
              ] else ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                  ),
                  onPressed: available ? _syncDriveNow : null,
                  icon: Icon(Icons.sync, size: 16),
                  label: Text('立即同步'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                  ),
                  onPressed: _pickMountFolder,
                  icon: Icon(Icons.folder_open_outlined, size: 16),
                  label: Text('更换文件夹'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  onPressed: _unmountDrive,
                  child: Text('取消挂载'),
                ),
              ],
              if (connected) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                  ),
                  onPressed: available && writable ? _uploadToDrive : null,
                  icon: Icon(Icons.cloud_upload_outlined, size: 16),
                  label: Text('上传书库'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                  ),
                  onPressed: available ? _downloadFromDrive : null,
                  icon: Icon(Icons.cloud_download_outlined, size: 16),
                  label: Text('拉取书库'),
                ),
              ],
            ],
          ),
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppTheme.accent,
              dense: true,
              title: Text(
                L.t('自动同步'),
                style: TextStyle(fontSize: 13, color: AppTheme.primaryText),
              ),
              subtitle: Text(
                '默认开启：挂载后自动把网盘里的书与封面补到首页书库，并把本地新增上传',
                style: TextStyle(fontSize: 10.5, color: AppTheme.secondaryText),
              ),
              value: _settings.autoSync,
              onChanged: (v) async {
                _settings.autoSync = v;
                await _settings.save();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.secondaryText,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: Icon(
        icon,
        size: 22,
        color: AppTheme.primaryText.withValues(alpha: 0.7),
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 14.5, color: AppTheme.primaryText),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryText),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right, size: 20, color: AppTheme.secondaryText),
      onTap: onTap,
    );
  }

  Widget _valueTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      leading: Icon(
        icon,
        size: 22,
        color: AppTheme.primaryText.withValues(alpha: 0.7),
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 14.5, color: AppTheme.primaryText),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 12.5, color: AppTheme.secondaryText),
          ),
          SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: AppTheme.secondaryText),
        ],
      ),
      onTap: onTap,
    );
  }
}
