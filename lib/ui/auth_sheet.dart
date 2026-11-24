import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/library_service.dart';
import 'app_theme.dart';

/// 登录 / 注册弹层：本地离线账户，数据只存本机
Future<void> showAuthSheet(BuildContext context) async {
  final auth = AuthService.instance;
  await auth.ensureLoaded();

  final userController = TextEditingController();
  final passController = TextEditingController();
  var isRegister = false;
  String? error;
  var busy = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> submit() async {
            final username = userController.text.trim();
            final password = passController.text;
            if (username.isEmpty || password.isEmpty) {
              setSheetState(() => error = '用户名和密码都要填');
              return;
            }
            setSheetState(() {
              busy = true;
              error = null;
            });
            final result = isRegister
                ? auth.register(username, password)
                : auth.login(username, password);
            if (result != null) {
              setSheetState(() {
                busy = false;
                error = result;
              });
              return;
            }
            await LibraryService.instance.loadFor(auth.currentAccount);
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isRegister ? '注册成功，已登录 $username' : '欢迎回来，$username',
                ),
                duration: Duration(milliseconds: 1500),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 22, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isRegister ? '注册账户' : '登录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryText,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 20,
                          color: AppTheme.secondaryText,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  Text(
                    '账户只保存在这台电脑上，书库和阅读进度按账户独立。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 20),
                  TextField(
                    controller: userController,
                    style: TextStyle(fontSize: 14),
                    decoration: _inputDecoration('用户名'),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    style: TextStyle(fontSize: 14),
                    decoration: _inputDecoration('密码（至少 6 位）'),
                    onSubmitted: (_) => submit(),
                  ),
                  if (error != null) ...[
                    SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
                    ),
                  ],
                  SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: busy ? null : submit,
                      child: Text(isRegister ? '注册并登录' : '登录'),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => setSheetState(() {
                        isRegister = !isRegister;
                        error = null;
                      }),
                      child: Text(
                        isRegister ? '已有账户？去登录' : '没有账户？注册一个',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.accent,
                        ),
                      ),
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
  userController.dispose();
  passController.dispose();
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 13, color: AppTheme.secondaryText),
    filled: true,
    fillColor: AppTheme.subtleCanvas,
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );
}
