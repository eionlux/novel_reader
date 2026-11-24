import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'library_service.dart';

class Shelf {
  final String id;
  String name;
  final DateTime createdAt;

  Shelf({required this.id, required this.name, required this.createdAt});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Shelf.fromJson(Map<String, dynamic> json) => Shelf(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 多书架（分组）管理。默认没有任何书架，由用户自行创建。
class ShelfService extends ChangeNotifier {
  ShelfService._();
  static final ShelfService instance = ShelfService._();

  /// 兼容旧数据里的默认书架 id，不再自动创建。
  static const String defaultId = 'default';

  final List<Shelf> shelves = [];

  Future<void> load() async {
    try {
      final file = File(AppPaths.shelvesFile);
      if (await file.exists()) {
        shelves
          ..clear()
          ..addAll(
            (jsonDecode(await file.readAsString()) as List).map(
              (e) => Shelf.fromJson(e as Map<String, dynamic>),
            ),
          );
      }
    } catch (_) {}
    notifyListeners();
  }

  Shelf? byId(String id) {
    for (final shelf in shelves) {
      if (shelf.id == id) return shelf;
    }
    return null;
  }

  Future<Shelf?> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    if (shelves.any((s) => s.name == trimmed)) return null;
    final shelf = Shelf(
      id: 'sh_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      createdAt: DateTime.now(),
    );
    shelves.add(shelf);
    await save();
    return shelf;
  }

  Future<void> rename(Shelf shelf, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    shelf.name = trimmed;
    await save();
  }

  /// 删除书架：里面的书移出书架，回到「全部书籍」。
  Future<void> delete(Shelf shelf) async {
    shelves.removeWhere((s) => s.id == shelf.id);
    var changed = false;
    for (final book in LibraryService.instance.books) {
      if (book.shelfId == shelf.id) {
        book.shelfId = '';
        book.inShelf = false;
        changed = true;
      }
    }
    if (changed) await LibraryService.instance.save();
    await save();
  }

  Future<void> save() async {
    try {
      await AppPaths.ensureDirs();
      await File(AppPaths.shelvesFile).writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(shelves.map((s) => s.toJson()).toList()),
      );
    } catch (_) {}
    notifyListeners();
  }
}
