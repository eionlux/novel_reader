import 'dart:io';

import 'package:flutter/services.dart';

/// 应用数据目录与书库目录（Windows / Android）
class AppPaths {
  static const MethodChannel _androidPaths = MethodChannel(
    'com.danqing.novel_reader/app_paths',
  );

  /// Android 私有目录由系统 API 提供，避免直接操作受限的共享存储路径。
  static String? _androidRoot;

  static String get _androidDataRoot {
    final root = _androidRoot;
    if (root == null) {
      throw StateError('Android app data directory has not been initialized');
    }
    return root;
  }

  static String get _home =>
      Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '.';

  static String get appData {
    if (Platform.isAndroid) return _androidDataRoot;
    final appDataEnv = Platform.environment['APPDATA'];
    if (appDataEnv != null && appDataEnv.isNotEmpty) {
      return '$appDataEnv\\DanQingReader';
    }
    return '$_home\\.danqing_reader';
  }

  static String get booksDir => Platform.isAndroid
      ? '$_androidDataRoot/books'
      : '$_home\\Documents\\丹青阅读\\书库';

  static String get libraryFile =>
      Platform.isAndroid ? '$appData/library.json' : '$appData\\library.json';

  /// 每个账户独立的书库索引；游客使用 guest。
  static String libraryFileFor(String account) => Platform.isAndroid
      ? '$appData/library_$account.json'
      : '$appData\\library_$account.json';

  static String get usersFile =>
      Platform.isAndroid ? '$appData/users.json' : '$appData\\users.json';

  static String get sessionFile =>
      Platform.isAndroid ? '$appData/session.json' : '$appData\\session.json';

  static String get settingsFile =>
      Platform.isAndroid ? '$appData/settings.json' : '$appData\\settings.json';

  static String get appSettingsFile => Platform.isAndroid
      ? '$appData/app_settings.json'
      : '$appData\\app_settings.json';

  static String get shelvesFile =>
      Platform.isAndroid ? '$appData/shelves.json' : '$appData\\shelves.json';

  /// OneDrive 网盘挂载点配置：只记录用户选择的本地已同步文件夹路径，
  /// 或 Android SAF 授权的 content:// 目录。
  static String get oneDriveMountFile => Platform.isAndroid
      ? '$appData/onedrive_mount.json'
      : '$appData\\onedrive_mount.json';

  /// 每个账户独立的书签文件。
  static String bookmarksFileFor(String account) => Platform.isAndroid
      ? '$appData/bookmarks_$account.json'
      : '$appData\\bookmarks_$account.json';

  /// 封面图缓存目录（从 EPUB/MOBI 提取，或同名 sidecar 图片）。
  static String get coversDir =>
      Platform.isAndroid ? '$appData/covers' : '$appData\\covers';

  static Future<void> ensureDirs() async {
    if (Platform.isAndroid && _androidRoot == null) {
      final root = await _androidPaths.invokeMethod<String>('appDataDirectory');
      if (root == null || root.isEmpty) {
        throw StateError('Android did not provide an app data directory');
      }
      _androidRoot = root;
    }

    for (final d in [appData, booksDir, coversDir]) {
      final dir = Directory(d);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }
}
