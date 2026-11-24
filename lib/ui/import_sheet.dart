import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_paths.dart';
import '../services/book_parser.dart';
import '../services/cover_service.dart';
import '../services/library_service.dart';
import '../services/one_drive_service.dart';
import 'app_theme.dart';
import 'library_manager_page.dart';
import 'strings.dart';

/// 右上角「+」：导入来源 + 书库管理
Future<void> showAddSourceSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L.t('选择图书来源'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryText,
                ),
              ),
              SizedBox(height: 14),
              _sourceTile(
                ctx,
                icon: Icons.insert_drive_file_outlined,
                title: L.t('从本地导入'),
                subtitle: '选择 txt / epub / mobi / azw3 文件，可多选',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _importFiles(context);
                },
              ),
              _sourceTile(
                ctx,
                icon: Icons.folder_open_outlined,
                title: L.t('从本地文件夹导入'),
                subtitle: '扫描整个文件夹，批量导入里面的电子书',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _importFolder(context);
                },
              ),
              _sourceTile(
                ctx,
                icon: Icons.cloud_outlined,
                title: L.t('从云端导入'),
                subtitle: '从已挂载的 OneDrive 网盘选择书籍',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await showCloudImportSheet(context);
                },
              ),
              _sourceTile(
                ctx,
                icon: Icons.folder_copy_outlined,
                title: L.t('书库管理'),
                subtitle: '书库目录、扫描新书、清理无效与重复',
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LibraryManagerPage()),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _sourceTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    leading: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 21, color: AppTheme.accent),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: AppTheme.primaryText,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: TextStyle(fontSize: 11.5, color: AppTheme.secondaryText),
    ),
    trailing: Icon(
      Icons.chevron_right,
      size: 19,
      color: AppTheme.secondaryText,
    ),
    onTap: onTap,
  );
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: Duration(milliseconds: 2000)),
    );
}

Future<void> _importFiles(BuildContext context) async {
  try {
    final group = XTypeGroup(label: '电子书', extensions: kSupportedExtensions);
    final files = await openFiles(
      acceptedTypeGroups: [group],
      confirmButtonText: L.t('从本地导入'),
    );
    if (files.isEmpty) return;
    final count = await LibraryService.instance.importFiles(
      files.map((f) => f.path),
    );
    unawaited(CoverService.instance.ensureCovers());
    _snack(
      context,
      count == 0
          ? L.t('读不到这个文件，或格式暂不支持')
          : '${L.t('已导入')} $count ${L.t('本新书')}',
    );
  } catch (e) {
    _snack(context, '打开文件选择器失败：$e');
  }
}

Future<void> _importFolder(BuildContext context) async {
  if (Platform.isAndroid) {
    // Android 的目录选择器返回 SAF 树，dart:io 读不到；退化为多选文件
    await _importFiles(context);
    return;
  }
  try {
    final path = await getDirectoryPath(confirmButtonText: '导入这个文件夹');
    if (path == null) return;
    final count = await LibraryService.instance.importDirectory(path);
    _snack(
      context,
      count == 0 ? L.t('没有发现新书') : '${L.t('已导入')} $count ${L.t('本新书')}',
    );
  } catch (e) {
    _snack(context, '打开文件夹选择器失败：$e');
  }
}

/// 从 OneDrive 选择书籍下载并导入
Future<void> showCloudImportSheet(BuildContext context) async {
  final drive = OneDriveService.instance;
  if (!drive.connected) {
    _snack(context, L.t('需要先在设置里挂载 OneDrive 网盘'));
    return;
  }
  if (!drive.available) {
    _snack(context, 'OneDrive 网盘目录当前不可用，请等同步完成');
    return;
  }

  final selected = <String>{};
  List<DriveFile> files = [];
  var loading = true;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool supported(String name) {
            final lower = name.toLowerCase();
            return lower.endsWith('.txt') ||
                lower.endsWith('.md') ||
                lower.endsWith('.epub') ||
                lower.endsWith('.mobi') ||
                lower.endsWith('.azw3') ||
                lower.endsWith('.azw');
          }

          Future<void> load() async {
            final list = await drive.listFiles();
            if (!ctx.mounted) return;
            setSheetState(() {
              files = list.where((f) => supported(f.name)).toList();
              loading = false;
            });
          }

          if (loading) load();

          Future<void> downloadSelected() async {
            if (selected.isEmpty) return;
            Navigator.of(ctx).pop();
            final lib = LibraryService.instance;
            var imported = 0;
            for (final file in files.where((f) => selected.contains(f.id))) {
              final path = await drive.downloadTo(file, AppPaths.booksDir);
              if (path == null) continue;
              final book = await lib.importFile(path);
              if (book != null) imported++;
            }
            _snack(context, '${L.t('已导入')} $imported ${L.t('本新书')}');
            unawaited(CoverService.instance.ensureCovers());
          }

          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.66,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Text(
                        L.t('从云端导入'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryText,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        files.isEmpty ? '' : 'OneDrive · ${files.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 20,
                          color: AppTheme.secondaryText,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Expanded(
                  child: loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.accent,
                          ),
                        )
                      : files.isEmpty
                      ? Center(
                          child: Text(
                            '网盘书库还是空的',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.secondaryText,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: files.length,
                          itemBuilder: (c, i) {
                            final file = files[i];
                            return CheckboxListTile(
                              value: selected.contains(file.id),
                              activeColor: AppTheme.accent,
                              dense: true,
                              title: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primaryText,
                                ),
                              ),
                              subtitle: Text(
                                '${(file.size / 1024).toStringAsFixed(0)} KB',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.secondaryText,
                                ),
                              ),
                              onChanged: (v) => setSheetState(() {
                                if (v == true) {
                                  selected.add(file.id);
                                } else {
                                  selected.remove(file.id);
                                }
                              }),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: selected.isEmpty ? null : downloadSelected,
                        child: Text('${L.t('从云端导入')}（${selected.length}）'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
