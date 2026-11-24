import '../models/book.dart';

/// 解析器版本：解析规则发生变化时递增，书库中记录的旧版本会在启动时自动重新解析。
const int kParserVersion = 7;

const Map<String, int> _englishNumbers = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
  'twenty': 20,
};

/// 没有数字的纯结构词：EPUB/NCX 里常见的内部标题。
/// 用中文替代，避免目录里出现 `Chapter`、`Cover`、`Cave` 等英文文件片段。
const Map<String, String> _structuralTitles = {
  'chapter': '第 {n} 章',
  'chap': '第 {n} 章',
  'ch': '第 {n} 章',
  'cave': '第 {n} 章',
  'file': '第 {n} 章',
  'section': '第 {n} 节',
  'sec': '第 {n} 节',
  'part': '第 {n} 部分',
  'pt': '第 {n} 部分',
  'book': '第 {n} 卷',
  'volume': '第 {n} 卷',
  'vol': '第 {n} 卷',
  'contents': '目录',
  'content': '目录',
  'toc': '目录',
  'cover': '封面',
  'titlepage': '书名页',
  'title-page': '书名页',
  'copyright': '版权页',
  'prologue': '序章',
  'epilogue': '尾声',
  'foreword': '前言',
  'preface': '前言',
  'dedication': '题献',
  'acknowledgements': '致谢',
  'acknowledgments': '致谢',
  'index': '索引',
  'about': '关于',
};

String _normalizedKey(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\-_.:#·•]+'), '')
    .trim();

/// 把 EPUB 内部文件名 / HTML title / NCX 标签里的 `chapter-1`、`CHAPTER 1`、
/// `C H A P T E R - 1` 等统一成「第 1 章」，避免目录里出现内部英文名。
String cleanChapterTitle(
  String raw, {
  int fallbackIndex = 0,
  String? sourcePath,
}) {
  var title = raw
      .replaceAll(RegExp(r'[\u200b\uFEFF\u00a0]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (title.isEmpty) return '第 ${fallbackIndex + 1} 章';

  // 去掉扩展名与路径，只保留最后一个片段
  title = title.replaceAll(
    RegExp(r'\.(x?html?|xml|txt|md)$', caseSensitive: false),
    '',
  );
  if (title.contains('/') || title.contains('\\')) {
    title = title.split(RegExp(r'[\\/]')).last.trim();
  }

  final titleKey = _normalizedKey(title);
  if (titleKey.isEmpty) return '第 ${fallbackIndex + 1} 章';

  // NCX 标签和正文文件名一模一样时，它只是内部文件名，不是真正的章节名。
  if (sourcePath != null && sourcePath.trim().isNotEmpty) {
    final stem = sourcePath
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    if (stem.isNotEmpty && titleKey == _normalizedKey(stem)) {
      final number = int.tryParse(
        RegExp(r'([0-9]{1,4})$').firstMatch(titleKey)?.group(1) ?? '',
      );
      return '第 ${number ?? fallbackIndex + 1} 章';
    }
  }

  // 纯数字文件名，如 001.xhtml 的 title 就是 001
  final pureNumber = RegExp(r'^[0-9]{1,4}$').firstMatch(titleKey);
  if (pureNumber != null) {
    return '第 ${int.parse(pureNumber.group(0)!)} 章';
  }

  final bare = _structuralTitles[titleKey];
  if (bare != null) {
    return bare.replaceAll('{n}', '${fallbackIndex + 1}');
  }

  final match = RegExp(
    r'^(?:c\s*h\s*a\s*p\s*t\s*e\s*r|chapter|chap|ch|c|section|sec|part|pt|book|volume|vol|file)'
    r'[\s\-_.:#]*'
    r'([0-9]{1,4}|[ivxlc]{1,8}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)'
    r'(.*)$',
    caseSensitive: false,
  ).firstMatch(title);
  if (match != null) {
    final token = match.group(1)!.toLowerCase();
    final number =
        int.tryParse(token) ?? _englishNumbers[token] ?? _romanToInt(token);
    if (number != null) {
      var rest = (match.group(2) ?? '').trim();
      rest = rest.replaceFirst(RegExp(r'^[\s\-_.:#·•]+'), '').trim();
      if (rest.length > 45) rest = rest.substring(0, 45).trim();
      return rest.isEmpty ? '第 $number 章' : '第 $number 章 · $rest';
    }
  }
  return title;
}

int? _romanToInt(String input) {
  const values = {'i': 1, 'v': 5, 'x': 10, 'l': 50, 'c': 100};
  var total = 0;
  var previous = 0;
  for (final char in input.split('').reversed) {
    final value = values[char];
    if (value == null) return null;
    if (value < previous) {
      total -= value;
    } else {
      total += value;
      previous = value;
    }
  }
  return total > 0 ? total : null;
}

class ParsedBook {
  final String title;
  final String author;
  final List<Chapter> chapters;
  final int charCount;

  const ParsedBook({
    required this.title,
    required this.author,
    required this.chapters,
    required this.charCount,
  });
}

final _chapterLinePattern = RegExp(
  r'^[ \t　]*(?:'
  r'第[0-9０-９一二三四五六七八九十百千零〇两]{1,10}[章节回卷部篇][^\n]{0,30}'
  r'|(?:序章|序言|楔子|引子|前言|尾声|后记|终章|大结局)[^\n]{0,30}'
  r'|(?:Chapter|CHAPTER)[ \t._-]*(?:[0-9IVXLC]{1,6}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)[^\n]{0,30}'
  r'|(?:C[ \t　]*H[ \t　]*A[ \t　]*P[ \t　]*T[ \t　]*E[ \t　]*R)[ \t　._-]*(?:[0-9IVXLC]{1,6}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)[^\n]{0,30}'
  r'|[0-9]{1,4}[、.．][^\n]{0,25}'
  r')$',
  multiLine: true,
  caseSensitive: false,
);

final _authorPattern = RegExp(r'[作著][\s　]*者[\s　]*[：:]?[\s　]*([^\n]{1,24})');

String normalizeText(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll('\u0000', '');
  // 去掉 markdown 标题符号（#、##），只保留标题文字
  text = text.replaceAll(RegExp(r'^[ \t　]*#{1,6}[ \t　]*', multiLine: true), '');
  // 去掉行尾空白，压缩连续空行
  text = text
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t　]+$'), ''))
      .join('\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

/// 给每个非空段落加两个全角空格的首行缩进（已是缩进的不重复加）
String indentParagraphs(String text) {
  final lines = text.split('\n');
  final buffer = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      buffer.add('');
    } else if (line.startsWith('　　')) {
      buffer.add(line);
    } else {
      buffer.add('　　${line.trimLeft()}');
    }
  }
  return buffer.join('\n');
}

/// 从全文切分章节；找不到章节标记时按段落长度切片
ParsedBook parseBookText(
  String raw, {
  String fallbackTitle = '未命名',
  String? fallbackAuthor,
}) {
  final text = normalizeText(raw);
  final authorMatch = _authorPattern.firstMatch(
    text.length > 2000 ? text.substring(0, 2000) : text,
  );
  final author = (authorMatch?.group(1) ?? fallbackAuthor ?? '佚名').trim();

  final matches = _chapterLinePattern.allMatches(text).toList();
  final chapters = <Chapter>[];

  if (matches.length >= 2) {
    var index = 0;
    final first = matches.first;
    final head = text.substring(0, first.start).trim();
    if (head.length > 30) {
      chapters.add(
        Chapter(
          index: index++,
          title: '序',
          charStart: 0,
          text: indentParagraphs(head),
        ),
      );
    }
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final nextStart = i + 1 < matches.length
          ? matches[i + 1].start
          : text.length;
      final title = cleanChapterTitle(m.group(0)!, fallbackIndex: index);
      final body = text.substring(m.end, nextStart).trim();
      chapters.add(
        Chapter(
          index: index++,
          title: title.isEmpty ? '第 $index 章' : title,
          charStart: m.start,
          text: indentParagraphs(body),
        ),
      );
    }
  } else {
    for (final ch in _chunkByLength(text)) {
      chapters.add(
        Chapter(
          index: ch.index,
          title: ch.title,
          charStart: ch.charStart,
          text: indentParagraphs(ch.text),
        ),
      );
    }
  }

  // 以缩进后的正文重新计算字符起点与总字数，保证进度换算一致
  var acc = 0;
  final finalChapters = <Chapter>[];
  for (final ch in chapters) {
    finalChapters.add(
      Chapter(index: ch.index, title: ch.title, charStart: acc, text: ch.text),
    );
    acc += ch.text.length;
  }

  // 书名：优先取正文开头的一级标题（原文 '#' 已在 normalize 中剥掉），否则用文件名
  var title = fallbackTitle;
  final headLines = text
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .take(3)
      .toList();
  if (headLines.isNotEmpty) {
    final first = headLines.first.trim();
    final looksLikeTitle =
        first.length <= 30 &&
        !_chapterLinePattern.hasMatch(first) &&
        !_authorPattern.hasMatch(first) &&
        !first.startsWith('　　');
    if (looksLikeTitle) title = first;
  }

  return ParsedBook(
    title: title,
    author: author,
    chapters: finalChapters,
    charCount: acc,
  );
}

List<Chapter> _chunkByLength(String text) {
  const chunkSize = 2200;
  final chapters = <Chapter>[];
  var pos = 0;
  var idx = 0;
  while (pos < text.length) {
    var end = pos + chunkSize;
    if (end >= text.length) {
      end = text.length;
    } else {
      final nl = text.lastIndexOf('\n', end);
      if (nl > pos + chunkSize ~/ 2) end = nl;
    }
    chapters.add(
      Chapter(
        index: idx,
        title: '第 ${idx + 1} 节',
        charStart: pos,
        text: text.substring(pos, end),
      ),
    );
    pos = end;
    idx++;
  }
  if (chapters.isEmpty) {
    chapters.add(Chapter(index: 0, title: '正文', charStart: 0, text: text));
  }
  return chapters;
}
