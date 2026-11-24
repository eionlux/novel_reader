import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_paths.dart';

/// 阅读纸张的底纹类型，由 CustomPainter 程序化绘制，不依赖图片资源。
enum PaperTexture {
  none,
  fiber,
  laid,
  oldPage,
  kraft,
  ruled,
  grid,
  newsprint,
  inkWash,
}

class ReaderSkin {
  final String id;
  final String name;
  final Color background;
  final Color foreground;
  final Color accent;
  final PaperTexture texture;

  const ReaderSkin({
    required this.id,
    required this.name,
    required this.background,
    required this.foreground,
    required this.accent,
    this.texture = PaperTexture.none,
  });
}

const List<ReaderSkin> readerSkins = [
  ReaderSkin(
    id: 'paper',
    name: '米黄',
    background: Color(0xFFFAF3E3),
    foreground: Color(0xFF322C21),
    accent: Color(0xFFA8794B),
    texture: PaperTexture.fiber,
  ),
  ReaderSkin(
    id: 'white',
    name: '纯白',
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF1F2023),
    accent: Color(0xFF6B7280),
  ),
  ReaderSkin(
    id: 'sepia',
    name: '牛皮',
    background: Color(0xFFF0E1C2),
    foreground: Color(0xFF4A3A20),
    accent: Color(0xFF95692F),
    texture: PaperTexture.laid,
  ),
  ReaderSkin(
    id: 'green',
    name: '护眼',
    background: Color(0xFFDCE8D6),
    foreground: Color(0xFF2A3A2C),
    accent: Color(0xFF5F7A5C),
  ),
  ReaderSkin(
    id: 'night',
    name: '夜间',
    background: Color(0xFF141416),
    foreground: Color(0xFF9FA2A7),
    accent: Color(0xFF565E6B),
  ),
  ReaderSkin(
    id: 'xuan',
    name: '宣纸',
    background: Color(0xFFF7F1E4),
    foreground: Color(0xFF3B3427),
    accent: Color(0xFF9B7A52),
    texture: PaperTexture.fiber,
  ),
  ReaderSkin(
    id: 'oldbook',
    name: '旧书页',
    background: Color(0xFFF0E3CA),
    foreground: Color(0xFF4B3A26),
    accent: Color(0xFF9A7142),
    texture: PaperTexture.oldPage,
  ),
  ReaderSkin(
    id: 'kraft',
    name: '牛皮纸',
    background: Color(0xFFD8BB8F),
    foreground: Color(0xFF3F2E1B),
    accent: Color(0xFF7D5830),
    texture: PaperTexture.kraft,
  ),
  ReaderSkin(
    id: 'ruled',
    name: '横线稿纸',
    background: Color(0xFFFBFAF3),
    foreground: Color(0xFF26303B),
    accent: Color(0xFF6F7F8F),
    texture: PaperTexture.ruled,
  ),
  ReaderSkin(
    id: 'grid',
    name: '方格稿纸',
    background: Color(0xFFFBF8EE),
    foreground: Color(0xFF35382C),
    accent: Color(0xFF8A8E76),
    texture: PaperTexture.grid,
  ),
  ReaderSkin(
    id: 'news',
    name: '旧报纸',
    background: Color(0xFFEDE7D6),
    foreground: Color(0xFF37342D),
    accent: Color(0xFF7C705C),
    texture: PaperTexture.newsprint,
  ),
  ReaderSkin(
    id: 'ink',
    name: '水墨纸',
    background: Color(0xFFF2EFE6),
    foreground: Color(0xFF25282A),
    accent: Color(0xFF56636A),
    texture: PaperTexture.inkWash,
  ),
];

class FlipStyleOption {
  final String id;
  final String name;
  const FlipStyleOption(this.id, this.name);
}

const List<FlipStyleOption> readerFlipStyles = [
  FlipStyleOption('slide', '横向滑动'),
  FlipStyleOption('fade', '淡入淡出'),
  FlipStyleOption('none', '无动画'),
  FlipStyleOption('cover', '覆盖翻页'),
  FlipStyleOption('push', '推移翻页'),
  FlipStyleOption('cube', '立方翻转'),
  FlipStyleOption('flip', '纸页翻转'),
  FlipStyleOption('curl', '书页卷动'),
  FlipStyleOption('zoom', '缩放穿越'),
  FlipStyleOption('blur', '雾化过渡'),
  FlipStyleOption('vertical', '上下滑动'),
  FlipStyleOption('rotate', '旋转翻页'),
  FlipStyleOption('paper', '纸片飘移'),
];

String flipStyleName(String id) => readerFlipStyles
    .firstWhere((f) => f.id == id, orElse: () => readerFlipStyles.first)
    .name;

ReaderSkin skinById(String id) =>
    readerSkins.firstWhere((s) => s.id == id, orElse: () => readerSkins.first);

class ApiFont {
  final String family;
  final String label;
  const ApiFont(this.family, this.label);
}

const List<ApiFont> readerFonts = [
  ApiFont('Microsoft YaHei', '微软雅黑'),
  ApiFont('SimSun', '宋体'),
  ApiFont('KaiTi', '楷体'),
  ApiFont('FangSong', '仿宋'),
  ApiFont('Segoe UI', '西文'),
];

class ReaderSettings {
  double fontSize;
  double lineHeight;
  double marginH;
  double marginV;
  String fontFamily;
  String skinId;

  /// 翻页风格：见 readerFlipStyles，共 13 种。
  String flipStyle;

  /// 点击翻页：leftPrev（左侧上一页）/ rightPrev（右侧上一页）
  String tapZone;

  /// 正文对齐：left（左对齐）/ justify（两端对齐）
  String textAlign;

  /// 沉浸式阅读：隐藏系统状态栏与导航栏
  bool immersive;

  /// 阅读页底部状态栏：时间、电量、书名、进度
  bool showStatusBar;

  ReaderSettings({
    this.fontSize = 19,
    this.lineHeight = 1.9,
    this.marginH = 28,
    this.marginV = 34,
    this.fontFamily = 'Microsoft YaHei',
    this.skinId = 'paper',
    this.flipStyle = 'slide',
    this.tapZone = 'leftPrev',
    this.textAlign = 'left',
    this.immersive = false,
    this.showStatusBar = true,
  });

  ReaderSkin get skin => skinById(skinId);

  Duration get pageTurnDuration => switch (flipStyle) {
    'none' => Duration.zero,
    'fade' => const Duration(milliseconds: 220),
    'blur' => const Duration(milliseconds: 260),
    'cube' || 'flip' || 'curl' || 'rotate' => const Duration(milliseconds: 360),
    _ => const Duration(milliseconds: 300),
  };

  TextStyle get textStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: lineHeight,
    color: skin.foreground,
    letterSpacing: 0.2,
  );

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? marginH,
    double? marginV,
    String? fontFamily,
    String? skinId,
    String? flipStyle,
    String? tapZone,
    String? textAlign,
    bool? immersive,
    bool? showStatusBar,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    marginH: marginH ?? this.marginH,
    marginV: marginV ?? this.marginV,
    fontFamily: fontFamily ?? this.fontFamily,
    skinId: skinId ?? this.skinId,
    flipStyle: flipStyle ?? this.flipStyle,
    tapZone: tapZone ?? this.tapZone,
    textAlign: textAlign ?? this.textAlign,
    immersive: immersive ?? this.immersive,
    showStatusBar: showStatusBar ?? this.showStatusBar,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'marginH': marginH,
    'marginV': marginV,
    'fontFamily': fontFamily,
    'skinId': skinId,
    'flipStyle': flipStyle,
    'tapZone': tapZone,
    'textAlign': textAlign,
    'immersive': immersive,
    'showStatusBar': showStatusBar,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 19,
    lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.9,
    marginH: (json['marginH'] as num?)?.toDouble() ?? 28,
    marginV: (json['marginV'] as num?)?.toDouble() ?? 34,
    fontFamily: json['fontFamily'] as String? ?? 'Microsoft YaHei',
    skinId: json['skinId'] as String? ?? 'paper',
    flipStyle: json['flipStyle'] as String? ?? 'slide',
    tapZone: json['tapZone'] as String? ?? 'leftPrev',
    textAlign: json['textAlign'] as String? ?? 'left',
    immersive: json['immersive'] as bool? ?? false,
    showStatusBar: json['showStatusBar'] as bool? ?? true,
  );

  static Future<ReaderSettings> load() async {
    try {
      final file = File(AppPaths.settingsFile);
      if (await file.exists()) {
        return ReaderSettings.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return ReaderSettings();
  }

  Future<void> save() async {
    try {
      await AppPaths.ensureDirs();
      await File(AppPaths.settingsFile).writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }
}
