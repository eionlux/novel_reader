/// XHTML / HTML 正文提取：EPUB 与 MOBI 共用。
library;

/// 把 HTML 片段转成适合分页阅读的纯文本
String htmlToText(String html) {
  var s = html;
  // 去掉脚本、样式、注释
  s = s.replaceAll(
    RegExp(r'<script[\s\S]*?</script\s*>', caseSensitive: false),
    '',
  );
  s = s.replaceAll(
    RegExp(r'<style[\s\S]*?</style\s*>', caseSensitive: false),
    '',
  );
  s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  // 块级标签与换行标签转换为换行
  s = s.replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n');
  s = s.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|tr|section|article|blockquote|td)\s*>',
      caseSensitive: false,
    ),
    '\n',
  );
  s = s.replaceAll(
    RegExp(
      r'<(p|div|h[1-6]|li|tr|section|article|blockquote)(\s[^>]*)?>',
      caseSensitive: false,
    ),
    '\n',
  );
  // 剩余标签全部剥掉
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  return decodeHtmlEntities(s);
}

String decodeHtmlEntities(String s) {
  var out = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&hellip;', '…')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–')
      .replaceAll('&ldquo;', '“')
      .replaceAll('&rdquo;', '”')
      .replaceAll('&lsquo;', '‘')
      .replaceAll('&rsquo;', '’')
      .replaceAll('&amp;', '&');
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code == null ? '' : String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? '' : String.fromCharCode(code);
  });
  return out;
}

/// 从 HTML 中提取 <title> 或第一个标题标签的文字，用作章节名
String? extractHtmlTitle(String html) {
  for (final pattern in [
    RegExp(r'<h[12][^>]*>([\s\S]*?)</h[12]>', caseSensitive: false),
    RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false),
    RegExp(r'<h[3-6][^>]*>([\s\S]*?)</h[3-6]>', caseSensitive: false),
  ]) {
    final m = pattern.firstMatch(html);
    if (m != null) {
      final text = htmlToText(m.group(1)!).trim();
      if (text.isNotEmpty && text.length <= 60) return text;
    }
  }
  return null;
}
