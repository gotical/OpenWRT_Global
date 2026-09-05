import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'l10n/app_strings.dart';
import 'screens/login_screen.dart';
import 'services/app_logger.dart';
import 'services/di_container.dart';
import 'services/notification_service.dart';
import 'services/router_monitor.dart';
import 'services/secure_screen.dart';
import 'services/storage_service.dart';
import 'services/update_service.dart';
import 'services/app_version.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Глобальный перехват необработанных ошибок — иначе они теряются молча.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e('Unhandled Flutter error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('Unhandled platform error', error, stack);
    return true;
  };
  setupDi();
  // Инициализация фоновой задачи мониторинга.
  try {
    await Workmanager().initialize(routerMonitorCallback);
  } catch (e) {
    AppLogger.w('WorkManager init failed: $e');
  }
  // Инициализация уведомлений.
  await NotificationService.init();
  // Текущая версия (используется в AppBar, About, UpdateService).
  UpdateService.setCurrentVersion(AppVersion.version);
  if (await StorageService.loadSecureScreen()) {
    SecureScreen.enable();
  } else {
    SecureScreen.disable();
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const OpenWrtManagerApp());
}

class OpenWrtManagerApp extends StatefulWidget {
  const OpenWrtManagerApp({super.key});

  static OpenWrtManagerAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<OpenWrtManagerAppState>();

  @override
  State<OpenWrtManagerApp> createState() => OpenWrtManagerAppState();
}

class OpenWrtManagerAppState extends State<OpenWrtManagerApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('ru');

  ThemeMode get currentThemeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    StorageService.loadLocale().then((code) {
      if (!mounted || code == null) return;
      if (AppStrings.supportedLocales.any((locale) => locale.languageCode == code)) {
        setState(() => _locale = Locale(code));
      }
    });
    // Сохранённый выбор темы (Системная/Светлая/Тёмная).
    StorageService.loadThemeMode().then((mode) {
      if (!mounted) return;
      setState(() {
        _themeMode = switch (mode) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
      });
    });
  }

  void toggleTheme(ThemeMode mode) => setThemeMode(mode);

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await StorageService.saveThemeMode(switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setLocale(Locale locale) async {
    setState(() => _locale = locale);
    await StorageService.saveLocale(locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = _locale != null && (_locale!.languageCode == 'ar' ||
        _locale!.languageCode == 'he' || _locale!.languageCode == 'fa');
    return MaterialApp(
      title: 'OPENWRT - Global',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // RTL для арабского (и других арабопишущих языков в будущем).
      builder: (ctx, child) =>
          Directionality(textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr, child: child!),
      themeMode: _themeMode,
      theme: _light(),
      darkTheme: _dark(),
      home: const LoginScreen(),
    );
  }

  ThemeData _light() {
    const seed = Color(0xFF0077CC);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _base(scheme, Brightness.light).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF2F5F9),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontWeight: FontWeight.w700, fontSize: 11);
          }
          return const TextStyle(fontSize: 11);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEEF2F7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
    );
  }

  ThemeData _dark() {
    const seed = Color(0xFF4DA8FF);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return _base(scheme, Brightness.dark).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0D1117),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: const Color(0xFF161B22),
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF161B22),
        surfaceTintColor: Colors.transparent,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontWeight: FontWeight.w700, fontSize: 11);
          }
          return const TextStyle(fontSize: 11);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF161B22),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
      ),
    );
  }

  ThemeData _base(ColorScheme scheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    );
  }
}
