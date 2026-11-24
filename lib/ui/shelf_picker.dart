import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/library_service.dart';
import '../services/shelf_service.dart';
import 'app_theme.dart';
import 'strings.dart';

/// 弹出「新建书架」输入框，创建成功返回新书架。
Future<Shelf?> promptCreateShelf(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        L.t('新建书架'),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryText,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(fontSize: 14, color: AppTheme.primaryText),
        decoration: InputDecoration(
          hintText: L.t('给书架起个名字'),
          hintStyle: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
        ),
        onSubmitted: (value) => Navigator.of(ctx).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L.t('取消')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.onAccent,
          ),
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(L.t('创建')),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final shelf = await ShelfService.instance.create(trimmed);
  if (shelf == null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('已有同名书架')));
  }
  return shelf;
}

/// 在首页 / 详情页把某本书加入书架。
Future<void> showAddToShelfSheet(BuildContext context, Book book) async {
  final shelves = ShelfService.instance.shelves;
  final selected = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.secondaryText.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shelves.isEmpty ? L.t('先创建一个书架') : L.t('加入书架'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          for (final shelf in shelves)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.collections_bookmark_outlined,
                size: 20,
                color: AppTheme.secondaryText,
              ),
              title: Text(
                shelf.name,
                style: TextStyle(fontSize: 14, color: AppTheme.primaryText),
              ),
              trailing: book.inShelf && book.shelfId == shelf.id
                  ? Icon(Icons.check, size: 19, color: AppTheme.accent)
                  : null,
              onTap: () => Navigator.of(ctx).pop('shelf:${shelf.id}'),
            ),
          ListTile(
            dense: true,
            leading: Icon(Icons.add, size: 20, color: AppTheme.accent),
            title: Text(
              L.t('新建书架'),
              style: TextStyle(fontSize: 14, color: AppTheme.accent),
            ),
            onTap: () => Navigator.of(ctx).pop('__create__'),
          ),
          if (book.shelfId.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.bookmark_remove_outlined,
                size: 20,
                color: Colors.redAccent,
              ),
              title: Text(
                L.t('移出书架'),
                style: const TextStyle(fontSize: 14, color: Colors.redAccent),
              ),
              onTap: () => Navigator.of(ctx).pop('__remove__'),
            ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (selected == null) return;

  final lib = LibraryService.instance;
  if (selected == '__create__') {
    final shelf = await promptCreateShelf(context);
    if (shelf == null) return;
    await lib.setShelfOf(book, shelf.id);
  } else if (selected == '__remove__') {
    book.inShelf = false;
    book.shelfId = '';
    await lib.save();
    lib.refresh();
  } else if (selected.startsWith('shelf:')) {
    await lib.setShelfOf(book, selected.substring(6));
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(selected == '__remove__' ? L.t('已从书架移除') : L.t('已加入书架')),
        duration: const Duration(milliseconds: 1400),
      ),
    );
}
