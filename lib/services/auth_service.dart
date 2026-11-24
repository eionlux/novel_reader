import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'password_hasher.dart';

class LocalUser {
  final String username;
  final String salt;
  final String passwordHash;
  final DateTime createdAt;

  const LocalUser({
    required this.username,
    required this.salt,
    required this.passwordHash,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'salt': salt,
    'passwordHash': passwordHash,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LocalUser.fromJson(Map<String, dynamic> json) => LocalUser(
    username: json['username'] as String? ?? '',
    salt: json['salt'] as String? ?? '',
    passwordHash: json['passwordHash'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// 本地离线账户系统：注册 / 登录 / 退出 / 记住登录状态。
/// 数据只保存在本机 %APPDATA%\DanQingReader，不联网；每个账户有独立的书库索引。
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String guestAccount = 'guest';

  List<LocalUser> _users = [];
  String _current = guestAccount;
  bool _loaded = false;

  String get currentAccount => _current;
  bool get isLoggedIn => _current != guestAccount;
  String get displayName => isLoggedIn ? _current : '游客';

  Future<void> load() async {
    await AppPaths.ensureDirs();
    try {
      final file = File(AppPaths.usersFile);
      if (await file.exists()) {
        _users = (jsonDecode(await file.readAsString()) as List)
            .map((e) => LocalUser.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _users = [];
    }
    try {
      final session = File(AppPaths.sessionFile);
      if (await session.exists()) {
        final name =
            (jsonDecode(await session.readAsString())
                    as Map<String, dynamic>)['username']
                as String?;
        if (name != null && _users.any((u) => u.username == name))
          _current = name;
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  String? register(String username, String password) {
    final name = username.trim();
    if (name.length < 2 || name.length > 20) return '用户名需要 2-20 个字符';
    if (name.toLowerCase() == guestAccount) return '这个用户名是保留字，换一个吧';
    if (password.length < 6) return '密码至少 6 位';
    if (_users.any((u) => u.username.toLowerCase() == name.toLowerCase()))
      return '这个用户名已经被注册了';
    final salt = randomSalt();
    _users.add(
      LocalUser(
        username: name,
        salt: salt,
        passwordHash: hashPassword(password, salt),
        createdAt: DateTime.now(),
      ),
    );
    _saveUsers();
    _current = name;
    _saveSession();
    notifyListeners();
    return null;
  }

  String? login(String username, String password) {
    final name = username.trim();
    final user = _users
        .where((u) => u.username.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (user == null) return '没有这个账户，可以先注册';
    if (hashPassword(password, user.salt) != user.passwordHash)
      return '密码不对，再试一次';
    _current = user.username;
    _saveSession();
    notifyListeners();
    return null;
  }

  void logout() {
    _current = guestAccount;
    _saveSession();
    notifyListeners();
  }

  Future<void> _saveUsers() async {
    try {
      await File(AppPaths.usersFile).writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(_users.map((u) => u.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveSession() async {
    try {
      await File(
        AppPaths.sessionFile,
      ).writeAsString(jsonEncode({'username': _current}));
    } catch (_) {}
  }
}
