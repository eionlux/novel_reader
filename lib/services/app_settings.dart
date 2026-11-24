import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_paths.dart';

/// 应用级设置：布局、排序、语言、屏幕方向、同步开关。
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// compact = 紧凑（更多列）；loose = 宽松（大封面）
  String layout = 'compact';

  /// added = 按导入时间；viewed = 按查看时间
  String sortMode = 'added';

  /// 降序 = 新的在前
  bool sortDesc = true;

  /// zh / en
  String language = 'zh';

  /// system / portrait / landscape
  String orientation = 'system';

  bool autoSync = true;

  /// 同步时把云端有、本地没有的书下载下来
  bool syncDownload = true;

  /// 当前同步数据源（当前只有 OneDrive）
  String syncProvider = 'onedrive';

  /// 应用配色：mono / night / paper
  String palette = 'mono';

  bool get isEnglish => language == 'en';

  Future<void> load() async {
    try {
      final file = File(AppPaths.appSettingsFile);
      if (await file.exists()) {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        layout = json['layout'] as String? ?? layout;
        sortMode = json['sortMode'] as String? ?? sortMode;
        sortDesc = json['sortDesc'] as bool? ?? sortDesc;
        language = json['language'] as String? ?? language;
        orientation = json['orientation'] as String? ?? orientation;
        palette = json['palette'] as String? ?? palette;
        autoSync = json['autoSync'] as bool? ?? autoSync;
        syncDownload = json['syncDownload'] as bool? ?? syncDownload;
        syncProvider = json['syncProvider'] as String? ?? syncProvider;
      }
    } catch (_) {}
    await applyOrientation();
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await AppPaths.ensureDirs();
      await File(AppPaths.appSettingsFile).writeAsString(
        jsonEncode({
          'layout': layout,
          'sortMode': sortMode,
          'sortDesc': sortDesc,
          'language': language,
          'orientation': orientation,
          'palette': palette,
          'autoSync': autoSync,
          'syncDownload': syncDownload,
          'syncProvider': syncProvider,
        }),
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setLayout(String value) async {
    layout = value;
    await save();
  }

  Future<void> setSortMode(String value) async {
    sortMode = value;
    await save();
  }

  Future<void> toggleSortOrder() async {
    sortDesc = !sortDesc;
    await save();
  }

  Future<void> setLanguage(String value) async {
    language = value;
    await save();
  }

  Future<void> setOrientation(String value) async {
    orientation = value;
    await applyOrientation();
    await save();
  }

  Future<void> setPalette(String value) async {
    palette = value;
    await save();
  }

  Future<void> applyOrientation() async {
    if (kIsWeb) return;
    switch (orientation) {
      case 'portrait':
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
      case 'landscape':
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      default:
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }
}
