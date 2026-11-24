import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart';

/// 接收从系统「打开方式 / 分享」进来的电子书文件。
/// Android 通过 MethodChannel，Windows 通过 %APPDATA%\DanQingReader\open_request.txt。
class OpenFileService {
  OpenFileService._();

  static final OpenFileService instance = OpenFileService._();

  static const MethodChannel _channel = MethodChannel(
    'com.danqing.novel_reader/open_file',
  );

  Timer? _poll;

  Future<String?> _takeWindowsRequest() async {
    try {
      final file = File(
        '${AppPaths.appData}${Platform.pathSeparator}open_request.txt',
      );
      if (!await file.exists()) return null;
      final text = (await file.readAsString()).trim();
      await file.delete();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  /// 冷启动时取出待打开的路径
  Future<String?> takeInitial() async {
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('getPendingFile');
      } catch (_) {
        return null;
      }
    }
    return _takeWindowsRequest();
  }

  /// 运行中监听新的打开请求
  void startWatching(void Function(String path) onFile) {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'openFile') {
          final path = call.arguments as String?;
          if (path != null && path.isNotEmpty) onFile(path);
        }
        return null;
      });
      unawaited(_channel.invokeMethod<void>('notifyReady').catchError((_) {}));
    }
    _poll?.cancel();
    if (Platform.isAndroid) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final path = await _takeWindowsRequest();
      if (path != null) onFile(path);
    });
  }

  void dispose() {
    _poll?.cancel();
    _poll = null;
  }
}
