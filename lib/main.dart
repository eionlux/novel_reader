import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'services/app_settings.dart';
import 'ui/app_theme.dart';
import 'ui/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const DanQingReaderApp());
}

class DanQingReaderApp extends StatefulWidget {
  const DanQingReaderApp({super.key});

  @override
  State<DanQingReaderApp> createState() => _DanQingReaderAppState();
}

class _DanQingReaderAppState extends State<DanQingReaderApp> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    AppTheme.palette = switch (AppSettings.instance.palette) {
      'night' => AppPalette.night,
      'paper' => AppPalette.paper,
      _ => AppPalette.mono,
    };
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.palette = switch (AppSettings.instance.palette) {
      'night' => AppPalette.night,
      'paper' => AppPalette.paper,
      _ => AppPalette.mono,
    };
    return MaterialApp(
      title: '丹青阅读',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _AppScrollBehavior(),
      theme: AppTheme.light,
      home: const SplashGate(),
    );
  }
}

/// 桌面端允许用鼠标拖动书库抽屉与列表（Flutter 默认只接受触摸拖动）。
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

/// 开场动画：先让主框架在后台完成启动，开屏层保持完全不透明，
/// 等启动完成且至少展示 1.5 秒后再淡出，避免先闪出主界面/加载页。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  Timer? _minTimer;
  Timer? _removeTimer;
  bool _bootReady = false;
  bool _minElapsed = false;
  bool _fading = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _minTimer = Timer(const Duration(milliseconds: 1500), () {
      _minElapsed = true;
      _maybeReveal();
    });
  }

  void _onBootReady() {
    _bootReady = true;
    _maybeReveal();
  }

  void _maybeReveal() {
    if (!mounted || !_visible || _fading) return;
    if (!_bootReady || !_minElapsed) return;
    setState(() => _fading = true);
    _removeTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _minTimer?.cancel();
    _removeTimer?.cancel();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MainShell(onBootSettled: _onBootReady),
        if (_visible)
          Positioned.fill(
            child: AbsorbPointer(
              child: AnimatedOpacity(
                opacity: _fading ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                child: _splashSurface(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _splashSurface() {
    return Container(
      decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_intro.value);
          // 只缩放中间的品牌内容，整块背景始终铺满窗口，不能露出底层。
          return Center(
            child: Opacity(
              opacity: (0.55 + 0.45 * t).clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'W',
              style: TextStyle(
                fontSize: 112,
                height: 1,
                fontWeight: FontWeight.w700,
                fontFamily: 'Georgia',
                letterSpacing: 3,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
                color: AppTheme.primaryText,
              ),
            ),
            const SizedBox(height: 20),
            Container(width: 34, height: 1, color: AppTheme.divider),
            const SizedBox(height: 18),
            Text(
              '万物皆可阅',
              style: TextStyle(
                fontSize: 14,
                letterSpacing: 7,
                decoration: TextDecoration.none,
                decorationColor: Colors.transparent,
                color: AppTheme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
