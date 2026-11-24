import 'dart:typed_data';

import 'html_text.dart';
import 'zip_reader.dart';

class RawChapter {
  final String title;
  final String text;

  /// 该章对应的 EPUB 内部文件路径，用来识别 `cave.xhtml` 这类内部文件名标题。
  final String sourcePath;

  const RawChapter(this.title, this.text, {this.sourcePath = ''});
}

class EpubBook {
  final String title;
  final String author;
  final List<RawChapter> chapters;
  const EpubBook({
    required this.title,
    required this.author,
    required this.chapters,
  });
}

/// EPUB 解析：ZIP → container.xml → OPF（manifest + spine）→ 依次抽取 XHTML 正文。
/// 目录标题优先取 NCX 导航，其次取正文里的 h1/h2。
class EpubParser {
  static EpubBook? parse(Uint8List bytes) {
    final zip = ZipArchive.open(bytes);
    if (zip == null) return null;

    // 1. 找 OPF 路径
    var opfPath = '';
    final container = zip.readText('META-INF/container.xml');
    if (container != null) {
      final m = RegExp(r'full-path\s*=\s*"([^"]+)"').firstMatch(container);
      if (m != null) opfPath = m.group(1)!;
    }
    if (opfPath.isEmpty || zip.findEntry(opfPath) == null) {
      // 兜底：直接找 .opf 文件
      for (final name in zip.entries.keys) {
        if (name.toLowerCase().endsWith('.opf')) {
          opfPath = name;
          break;
        }
      }
    }
    final opfKey = zip.findEntry(opfPath);
    if (opfKey == null) return null;
    final opf = zip.readText(opfKey);
    if (opf == null) return null;

    final baseDir = opfKey.contains('/')
        ? opfKey.substring(0, opfKey.lastIndexOf('/') + 1)
        : '';

    // 2. 元数据
    final title = _metaText(opf, 'dc:title') ?? '未命名';
    final author = _metaText(opf, 'dc:creator') ?? '佚名';

    // 3. manifest：id → href
    final manifest = <String, String>{};
    String? ncxHref;
    String? navHref;
    for (final m in RegExp(
      r'<item\s+[^>]*>',
      caseSensitive: false,
    ).allMatches(opf)) {
      final tag = m.group(0)!;
      final id = _attr(tag, 'id');
      final href = _attr(tag, 'href');
      if (id == null || href == null) continue;
      manifest[id] = href;
      final media = _attr(tag, 'media-type') ?? '';
      final properties = _attr(tag, 'properties') ?? '';
      if (media.contains('dtbncx')) ncxHref = href;
      if (properties.split(RegExp(r'\s+')).contains('nav')) navHref = href;
    }

    // 4. spine 顺序
    final spine = <String>[];
    for (final m in RegExp(
      r'<itemref\s+[^>]*>',
      caseSensitive: false,
    ).allMatches(opf)) {
      final idref = _attr(m.group(0)!, 'idref');
      if (idref != null && manifest.containsKey(idref))
        spine.add(manifest[idref]!);
    }
    if (spine.isEmpty) {
      // 没有 spine 就按 manifest 里的 html 文件顺序
      for (final m in RegExp(
        r'<item\s+[^>]*>',
        caseSensitive: false,
      ).allMatches(opf)) {
        final tag = m.group(0)!;
        final media = _attr(tag, 'media-type') ?? '';
        final href = _attr(tag, 'href');
        if (href != null && media.contains('xhtml')) spine.add(href);
      }
    }
    if (spine.isEmpty) return null;

    // 5. NCX 目录标题映射：规范化路径 → 章节名
    final tocTitles = <String, String>{};
    if (ncxHref != null) {
      final ncxKey = zip.findEntry(_resolve(baseDir, ncxHref));
      final ncx = ncxKey == null ? null : zip.readText(ncxKey);
      if (ncx != null) {
        for (final m in RegExp(
          r'<navPoint[\s\S]*?</navPoint>',
          caseSensitive: false,
        ).allMatches(ncx)) {
          final block = m.group(0)!;
          final label = RegExp(
            r'<text[^>]*>([\s\S]*?)</text>',
            caseSensitive: false,
          ).firstMatch(block)?.group(1);
          final src = _attr(
            RegExp(
                  r'<content\s+[^>]*>',
                  caseSensitive: false,
                ).firstMatch(block)?.group(0) ??
                '',
            'src',
          );
          if (label != null && src != null) {
            final key = _resolve(baseDir, src.split('#').first);
            tocTitles[key] = decodeHtmlEntities(label).trim();
          }
        }
      }
    }

    // 5.1 EPUB3 目录文档兜底：解析 nav.xhtml 里 toc 列表的链接文字
    if (navHref != null) {
      final navKey = zip.findEntry(_resolve(baseDir, navHref));
      final nav = navKey == null ? null : zip.readText(navKey);
      if (nav != null) {
        final tocBlock =
            RegExp(
              r'''<nav[^>]*epub:type\s*=\s*["']toc["'][\s\S]*?</nav>''',
              caseSensitive: false,
            ).firstMatch(nav)?.group(0) ??
            nav;
        for (final m in RegExp(
          r'<a\s+[^>]*>[\s\S]*?</a>',
          caseSensitive: false,
        ).allMatches(tocBlock)) {
          final block = m.group(0)!;
          final open = RegExp(
            r'^<a\s+[^>]*>',
            caseSensitive: false,
          ).firstMatch(block)?.group(0);
          final href = open == null ? null : _attr(open, 'href');
          if (href == null || href.startsWith('http')) continue;
          final label = htmlToText(
            block.replaceFirst(RegExp(r'^<a\s+[^>]*>', caseSensitive: false), '')
                .replaceFirst(RegExp(r'</a\s*>$', caseSensitive: false), ''),
          ).trim();
          if (label.isEmpty) continue;
          final key = _resolve(baseDir, href.split('#').first);
          tocTitles.putIfAbsent(key, () => label);
        }
      }
    }

    // 6. 逐章抽取正文
    final chapters = <RawChapter>[];
    for (var i = 0; i < spine.length; i++) {
      final path = _resolve(baseDir, spine[i]);
      final key = zip.findEntry(path);
      if (key == null) continue;
      final html = zip.readText(key);
      if (html == null) continue;
      final text = htmlToText(html).trim();
      if (text.isEmpty) continue;
      final title =
          tocTitles[path] ??
          extractHtmlTitle(html) ??
          '第 ${chapters.length + 1} 节';
      chapters.add(RawChapter(title, text, sourcePath: path));
    }
    if (chapters.isEmpty) return null;
    return EpubBook(title: title, author: author, chapters: chapters);
  }

  static String? _metaText(String opf, String tag) {
    final m = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(opf);
    if (m == null) return null;
    final text = decodeHtmlEntities(m.group(1)!).trim();
    return text.isEmpty ? null : text;
  }

  static String? _attr(String tag, String name) {
    final m =
        RegExp(
          '$name\\s*=\\s*"([^"]*)"',
          caseSensitive: false,
        ).firstMatch(tag) ??
        RegExp("$name\\s*=\\s*'([^']*)'", caseSensitive: false).firstMatch(tag);
    return m?.group(1);
  }

  /// 把 OPF 里的相对 href 规范化成 zip 内路径，并做 URL 解码
  static String _resolve(String baseDir, String href) {
    var path = Uri.decodeFull(href.split('#').first).replaceAll('\\', '/');
    final parts = <String>[];
    for (final seg
        in (path.startsWith('/') ? path.substring(1) : baseDir + path).split(
          '/',
        )) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }
}
