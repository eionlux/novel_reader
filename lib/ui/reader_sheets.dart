import 'dart:async';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/bookmark_service.dart';
import '../services/reader_settings.dart';

// ───────────────────────── 目录 ─────────────────────────

Future<void> showTocSheet(
  BuildContext context, {
  required List<Chapter> chapters,
  required int currentIndex,
  required ReaderSkin skin,
  required ValueChanged<int> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: skin.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Text(
                    '目录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: skin.foreground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '共 ${chapters.length} 章',
                    style: TextStyle(
                      fontSize: 12,
                      color: skin.foreground.withValues(alpha: 0.55),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: skin.foreground.withValues(alpha: 0.6),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: skin.foreground.withValues(alpha: 0.1)),
            Expanded(
              child: ListView.builder(
                itemCount: chapters.length,
                itemBuilder: (c, i) {
                  final ch = chapters[i];
                  final active = i == currentIndex;
                  return ListTile(
                    dense: true,
                    title: Text(
                      ch.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: active
                            ? skin.accent
                            : skin.foreground.withValues(alpha: 0.84),
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: active
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: skin.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '在读',
                              style: TextStyle(
                                fontSize: 11,
                                color: skin.accent,
                              ),
                            ),
                          )
                        : Text(
                            '${ch.charCount} 字',
                            style: TextStyle(
                              fontSize: 11,
                              color: skin.foreground.withValues(alpha: 0.4),
                            ),
                          ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onSelected(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ───────────────────────── 主题 / 排版设置 ─────────────────────────

Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderSettings initial,
  required void Function(ReaderSettings) onChanged,
}) {
  var settings = initial;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: settings.skin.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void update(ReaderSettings next) {
            setSheetState(() => settings = next);
            onChanged(next);
          }

          final skin = settings.skin;
          final labelStyle = TextStyle(
            fontSize: 13,
            color: skin.foreground.withValues(alpha: 0.72),
          );
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '主题设置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: skin.foreground,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('完成', style: TextStyle(color: skin.accent)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('主题', style: labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: readerSkins.map((s) {
                      final active = s.id == settings.skinId;
                      return GestureDetector(
                        onTap: () => update(settings.copyWith(skinId: s.id)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: s.background,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: active
                                  ? skin.accent
                                  : skin.foreground.withValues(alpha: 0.18),
                              width: active ? 2 : 1,
                            ),
                          ),
                          child: Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: active ? s.accent : s.foreground,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Text('字体', style: labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: readerFonts.map((f) {
                      final active = f.family == settings.fontFamily;
                      return ChoiceChip(
                        selected: active,
                        label: Text(
                          f.label,
                          style: TextStyle(
                            fontFamily: f.family,
                            fontSize: 13,
                            color: skin.foreground,
                          ),
                        ),
                        selectedColor: skin.accent.withValues(alpha: 0.16),
                        backgroundColor: Colors.transparent,
                        side: BorderSide(
                          color: skin.foreground.withValues(
                            alpha: active ? 0.5 : 0.14,
                          ),
                        ),
                        onSelected: (_) =>
                            update(settings.copyWith(fontFamily: f.family)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  _sliderRow(
                    ctx,
                    '字号',
                    settings.fontSize,
                    14,
                    34,
                    skin,
                    (v) => update(settings.copyWith(fontSize: v)),
                  ),
                  _sliderRow(
                    ctx,
                    '行距',
                    settings.lineHeight,
                    1.3,
                    2.6,
                    skin,
                    (v) => update(settings.copyWith(lineHeight: v)),
                  ),
                  _sliderRow(
                    ctx,
                    '左右边距',
                    settings.marginH,
                    12,
                    56,
                    skin,
                    (v) => update(settings.copyWith(marginH: v)),
                  ),
                  _sliderRow(
                    ctx,
                    '上下边距',
                    settings.marginV,
                    16,
                    64,
                    skin,
                    (v) => update(settings.copyWith(marginV: v)),
                  ),
                  const SizedBox(height: 12),
                  Text('翻页风格', style: labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: readerFlipStyles
                        .map(
                          (f) =>
                              _flipChip(f.id, f.name, skin, settings, update),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  Text('点击翻页', style: labelStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _tapZoneChip('leftPrev', '左侧上一页', skin, settings, update),
                      _tapZoneChip(
                        'rightPrev',
                        '右侧上一页',
                        skin,
                        settings,
                        update,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _toggleRow(
                    '沉浸式全屏',
                    '隐藏系统状态栏与导航栏',
                    settings.immersive,
                    skin,
                    (v) => update(settings.copyWith(immersive: v)),
                  ),
                  _toggleRow(
                    '显示底部状态栏',
                    '时间、电量、书名与阅读进度',
                    settings.showStatusBar,
                    skin,
                    (v) => update(settings.copyWith(showStatusBar: v)),
                  ),
                  _toggleRow(
                    '正文两端对齐',
                    '让段落左右两侧更整齐',
                    settings.textAlign == 'justify',
                    skin,
                    (v) => update(
                      settings.copyWith(textAlign: v ? 'justify' : 'left'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _tapZoneChip(
  String id,
  String label,
  ReaderSkin skin,
  ReaderSettings settings,
  void Function(ReaderSettings) update,
) {
  final active = settings.tapZone == id;
  return ChoiceChip(
    selected: active,
    label: Text(label, style: TextStyle(fontSize: 13, color: skin.foreground)),
    selectedColor: skin.accent.withValues(alpha: 0.16),
    backgroundColor: Colors.transparent,
    side: BorderSide(
      color: skin.foreground.withValues(alpha: active ? 0.5 : 0.14),
    ),
    onSelected: (_) => update(settings.copyWith(tapZone: id)),
  );
}

Widget _toggleRow(
  String title,
  String subtitle,
  bool value,
  ReaderSkin skin,
  ValueChanged<bool> onChanged,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 13.5, color: skin.foreground),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: skin.foreground.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: skin.accent.withValues(alpha: 0.32),
          activeColor: skin.accent,
        ),
      ],
    ),
  );
}

Widget _flipChip(
  String id,
  String label,
  ReaderSkin skin,
  ReaderSettings settings,
  void Function(ReaderSettings) update,
) {
  final active = settings.flipStyle == id;
  return ChoiceChip(
    selected: active,
    label: Text(label, style: TextStyle(fontSize: 13, color: skin.foreground)),
    selectedColor: skin.accent.withValues(alpha: 0.16),
    backgroundColor: Colors.transparent,
    side: BorderSide(
      color: skin.foreground.withValues(alpha: active ? 0.5 : 0.14),
    ),
    onSelected: (_) => update(settings.copyWith(flipStyle: id)),
  );
}

Widget _sliderRow(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  ReaderSkin skin,
  ValueChanged<double> onChanged,
) {
  return Row(
    children: [
      SizedBox(
        width: 62,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: skin.foreground.withValues(alpha: 0.72),
          ),
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: skin.accent,
            inactiveTrackColor: skin.foreground.withValues(alpha: 0.16),
            thumbColor: skin.accent,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
            trackHeight: 2,
          ),
          child: Slider(
            min: min,
            max: max,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 40,
        child: Text(
          value.toStringAsFixed(1),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            color: skin.foreground.withValues(alpha: 0.55),
          ),
        ),
      ),
    ],
  );
}

// ───────────────────────── 顶栏「选项」快调面板 ─────────────────────────

Future<void> showQuickOptionsSheet(
  BuildContext context, {
  required ReaderSettings initial,
  required void Function(ReaderSettings) onChanged,
}) {
  var settings = initial;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: settings.skin.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          void update(ReaderSettings next) {
            setSheetState(() => settings = next);
            onChanged(next);
          }

          final skin = settings.skin;
          final night = settings.skinId == 'night';
          final eyeCare = settings.skinId == 'green';

          void toggleNight(bool value) {
            if (value) {
              update(settings.copyWith(skinId: 'night'));
            } else if (settings.skinId == 'night') {
              update(settings.copyWith(skinId: 'paper'));
            }
          }

          void toggleEye(bool value) {
            if (value) {
              update(settings.copyWith(skinId: 'green'));
            } else if (settings.skinId == 'green') {
              update(settings.copyWith(skinId: 'paper'));
            }
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '显示选项',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: skin.foreground,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('完成', style: TextStyle(color: skin.accent)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '字号',
                        style: TextStyle(
                          fontSize: 13,
                          color: skin.foreground.withValues(alpha: 0.72),
                        ),
                      ),
                      const Spacer(),
                      _stepButton(
                        ctx,
                        skin,
                        Icons.text_decrease,
                        () => update(
                          settings.copyWith(
                            fontSize: (settings.fontSize - 1).clamp(14, 34),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          settings.fontSize.toStringAsFixed(0),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: skin.foreground,
                          ),
                        ),
                      ),
                      _stepButton(
                        ctx,
                        skin,
                        Icons.text_increase,
                        () => update(
                          settings.copyWith(
                            fontSize: (settings.fontSize + 1).clamp(14, 34),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      activeTrackColor: skin.accent,
                      inactiveTrackColor: skin.foreground.withValues(
                        alpha: 0.16,
                      ),
                      thumbColor: skin.accent,
                      trackHeight: 2,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 10,
                      ),
                    ),
                    child: Slider(
                      min: 14,
                      max: 34,
                      value: settings.fontSize.clamp(14, 34),
                      onChanged: (v) => update(settings.copyWith(fontSize: v)),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '夜间模式',
                      style: TextStyle(fontSize: 14, color: skin.foreground),
                    ),
                    value: night,
                    activeThumbColor: skin.accent,
                    onChanged: toggleNight,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '护眼模式',
                      style: TextStyle(fontSize: 14, color: skin.foreground),
                    ),
                    value: eyeCare,
                    activeThumbColor: skin.accent,
                    onChanged: toggleEye,
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _stepButton(
  BuildContext ctx,
  ReaderSkin skin,
  IconData icon,
  VoidCallback onTap,
) {
  return InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      width: 34,
      height: 30,
      decoration: BoxDecoration(
        color: skin.foreground.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 18,
        color: skin.foreground.withValues(alpha: 0.72),
      ),
    ),
  );
}

// ───────────────────────── 书签 ─────────────────────────

Future<void> showBookmarksSheet(
  BuildContext context, {
  required ReaderSkin skin,
  required List<Bookmark> Function() bookmarksOf,
  required Future<void> Function() onAdd,
  required Future<void> Function(Bookmark) onDelete,
  required void Function(Bookmark) onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: skin.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final marks = bookmarksOf();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.55,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        '书签',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: skin.foreground,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${marks.length} 条',
                        style: TextStyle(
                          fontSize: 12,
                          color: skin.foreground.withValues(alpha: 0.55),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await onAdd();
                          setSheetState(() {});
                        },
                        child: Text(
                          '添加当前位置',
                          style: TextStyle(fontSize: 13, color: skin.accent),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 20,
                          color: skin.foreground.withValues(alpha: 0.6),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: skin.foreground.withValues(alpha: 0.1),
                ),
                Expanded(
                  child: marks.isEmpty
                      ? Center(
                          child: Text(
                            '还没有书签，点「添加当前位置」即可',
                            style: TextStyle(
                              fontSize: 13,
                              color: skin.foreground.withValues(alpha: 0.45),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: marks.length,
                          itemBuilder: (c, i) {
                            final m = marks[i];
                            return ListTile(
                              dense: true,
                              title: Text(
                                m.chapterTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: skin.foreground.withValues(
                                    alpha: 0.86,
                                  ),
                                ),
                              ),
                              subtitle: Text(
                                m.snippet,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: skin.foreground.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.bookmark_remove_outlined,
                                  size: 18,
                                  color: skin.foreground.withValues(alpha: 0.4),
                                ),
                                onPressed: () async {
                                  await onDelete(m);
                                  setSheetState(() {});
                                },
                              ),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                onJump(m);
                              },
                            );
                          },
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

// ───────────────────────── 全书搜索 ─────────────────────────

class _Hit {
  final int chapter;
  final int offset;
  final String chapterTitle;
  final String snippet;
  const _Hit(this.chapter, this.offset, this.chapterTitle, this.snippet);
}

Future<void> showSearchSheet(
  BuildContext context, {
  required List<Chapter> chapters,
  required ReaderSkin skin,
  required void Function(int chapter, int offset) onJump,
}) {
  final controller = TextEditingController();
  var searching = false;
  var hits = <_Hit>[];
  var queryText = '';

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: skin.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> runSearch(String raw) async {
            final query = raw.trim();
            if (query.isEmpty) {
              setSheetState(() {
                hits = [];
                queryText = '';
                searching = false;
              });
              return;
            }
            setSheetState(() {
              searching = true;
              queryText = query;
            });
            final results = <_Hit>[];
            final lower = query.toLowerCase();
            for (final ch in chapters) {
              final text = ch.text;
              final hay = text.toLowerCase();
              var from = 0;
              var count = 0;
              while (count < 6 && results.length < 100) {
                final idx = hay.indexOf(lower, from);
                if (idx < 0) break;
                results.add(
                  _Hit(
                    ch.index,
                    idx,
                    ch.title,
                    _snippetOf(text, idx, query.length),
                  ),
                );
                count++;
                from = idx + lower.length;
              }
              if (results.length >= 100) break;
            }
            if (!ctx.mounted) return;
            setSheetState(() {
              hits = results;
              searching = false;
            });
          }

          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.78,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
                    child: Row(
                      children: [
                        Text(
                          '搜索本书',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: skin.foreground,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 20,
                            color: skin.foreground.withValues(alpha: 0.6),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: TextStyle(fontSize: 14, color: skin.foreground),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '输入关键词，回车搜索',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: skin.foreground.withValues(alpha: 0.38),
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          size: 18,
                          color: skin.foreground.withValues(alpha: 0.5),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: skin.foreground.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: runSearch,
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: skin.foreground.withValues(alpha: 0.1),
                  ),
                  Expanded(
                    child: searching
                        ? Center(
                            child: CircularProgressIndicator(
                              color: skin.accent,
                              strokeWidth: 2,
                            ),
                          )
                        : hits.isEmpty
                        ? Center(
                            child: Text(
                              queryText.isEmpty
                                  ? '输入关键词开始搜索全书'
                                  : '没有找到「$queryText」',
                              style: TextStyle(
                                fontSize: 13,
                                color: skin.foreground.withValues(alpha: 0.45),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: hits.length,
                            itemBuilder: (c, i) {
                              final hit = hits[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  hit.chapterTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: skin.foreground.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                                subtitle: Text(
                                  hit.snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: skin.foreground.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  onJump(hit.chapter, hit.offset);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _snippetOf(String text, int index, int length) {
  final start = (index - 18).clamp(0, text.length);
  final end = (index + length + 30).clamp(0, text.length);
  final raw = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
  return '${start > 0 ? '…' : ''}$raw${end < text.length ? '…' : ''}';
}
