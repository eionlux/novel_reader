class Chapter {
  final int index;
  final String title;
  final int charStart;
  final String text;

  const Chapter({
    required this.index,
    required this.title,
    required this.charStart,
    required this.text,
  });

  int get charCount => text.length;
}

class Book {
  final String id;
  String title;
  String author;
  String filePath;
  int charCount;
  int chapterCount;
  int lastChapter;
  int lastCharOffset;
  double progress;
  DateTime addedAt;
  DateTime lastOpenedAt;
  int fileSize;
  int parserVersion;
  bool inShelf;
  String format;
  bool favorite;
  bool trashed;
  String shelfId;
  String coverPath;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.charCount,
    required this.chapterCount,
    required this.addedAt,
    required this.lastOpenedAt,
    this.lastChapter = 0,
    this.lastCharOffset = 0,
    this.progress = 0,
    this.fileSize = -1,
    this.parserVersion = 0,
    this.inShelf = false,
    this.format = 'txt',
    this.favorite = false,
    this.trashed = false,
    this.shelfId = '',
    this.coverPath = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'filePath': filePath,
    'charCount': charCount,
    'chapterCount': chapterCount,
    'lastChapter': lastChapter,
    'lastCharOffset': lastCharOffset,
    'progress': progress,
    'addedAt': addedAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'fileSize': fileSize,
    'parserVersion': parserVersion,
    'inShelf': inShelf,
    'format': format,
    'favorite': favorite,
    'trashed': trashed,
    'shelfId': shelfId,
    'coverPath': coverPath,
  };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String,
    title: json['title'] as String? ?? '未命名',
    author: json['author'] as String? ?? '佚名',
    filePath: json['filePath'] as String? ?? '',
    charCount: (json['charCount'] as num?)?.toInt() ?? 0,
    chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
    lastChapter: (json['lastChapter'] as num?)?.toInt() ?? 0,
    lastCharOffset: (json['lastCharOffset'] as num?)?.toInt() ?? 0,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    addedAt:
        DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
    lastOpenedAt:
        DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
        DateTime.now(),
    fileSize: (json['fileSize'] as num?)?.toInt() ?? -1,
    parserVersion: (json['parserVersion'] as num?)?.toInt() ?? 0,
    inShelf: json['inShelf'] as bool? ?? true,
    format: json['format'] as String? ?? 'txt',
    favorite: json['favorite'] as bool? ?? false,
    trashed: json['trashed'] as bool? ?? false,
    shelfId: json['shelfId'] as String? ?? '',
    coverPath: json['coverPath'] as String? ?? '',
  );
}
