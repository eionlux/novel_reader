import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_paths.dart';
import '../services/book_parser.dart';
import '../services/library_service.dart';
import 'app_theme.dart';
import 'strings.dart';

/// 书库管理：目录、扫描导入、清理无效与重复
class LibraryManagerPage extends StatefulWidget {
  LibraryManagerPage({super.key});

  @override
  State<LibraryManagerPage> createState() => _LibraryManagerPageState();
}

class _LibraryManagerPageState extends State<LibraryManagerPage> {
  final LibraryService _lib = LibraryService.instance;

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

  Future<void> _openFolder() async {
    await AppPaths.ensureDirs();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [AppPaths.booksDir]);
    } else {
      _snack('请用系统文件管理器打开上方路径，把电子书放进去后点「扫描导入新书」');
    }
  }

  Future<void> _scan() async {
    final added = await _lib.scanBooksFolder();
    _snack(added == 0 ? L.t('没有发现新书') : '${L.t('已导入')} $added ${L.t('本新书')}');
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

  @override
  Widget build(BuildContext context) {
    final active = _lib.books.where((b) => !b.trashed).length;
    final trashed = _lib.books.where((b) => b.trashed).length;
    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          L.t('书库管理'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryText,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(22, 10, 22, 30),
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.subtleCanvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: AppTheme.accent,
                    ),
                    SizedBox(width: 8),
                    Text(
                      L.t('书库文件夹'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryText,
                      ),
                    ),
                    Spacer(),
                    Text(
                      '$active 本 · 回收站 $trashed 本',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                SelectableText(
                  AppPaths.booksDir,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppTheme.primaryText,
                  ),
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: BorderSide(color: AppTheme.divider),
                      ),
                      onPressed: _openFolder,
                      icon: Icon(Icons.folder_open_outlined, size: 16),
                      label: Text(L.t('打开文件夹')),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.secondaryText,
                        side: BorderSide(color: AppTheme.divider),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: AppPaths.booksDir),
                        );
                        _snack('路径已复制');
                      },
                      icon: Icon(Icons.copy_rounded, size: 16),
                      label: Text('复制路径'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          _action(
            icon: Icons.drive_file_move_outline,
            title: L.t('扫描导入新书'),
            subtitle: '把放进书库文件夹的电子书加入索引（支持 $kFormatDescription）',
            onTap: _scan,
          ),
          _action(
            icon: Icons.auto_delete_outlined,
            title: L.t('清理无效图书'),
            subtitle: '移除文件已经被删除的记录',
            onTap: _cleanInvalid,
          ),
          _action(
            icon: Icons.content_copy_outlined,
            title: L.t('清理重复图书'),
            subtitle: '同书名同大小只保留一本',
            onTap: _cleanDuplicates,
          ),
          SizedBox(height: 18),
          Text(
            '书库索引保存在应用数据目录，电子书文件本身不会被删除；从索引移除只会影响阅读列表。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: AppTheme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: AppTheme.secondaryText,
      ),
      onTap: onTap,
    );
  }
}
