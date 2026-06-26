import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'services/cache_service.dart';
import 'services/search_service.dart';
import 'services/database_service.dart';
import 'services/background_service.dart';
import 'services/sync_service.dart';

// Brand colors
class AppColors {
  static const primary = Color(0xFF1C4220);
  static const dark = Color(0xFF081A0A);
  static const surface = Color(0xFF0E2410);
  static const highlight = Color(0xFF86CC8D);
  static const memberOffer = Color(0xFFD8B56A);
  static const memberOfferDark = Color(0xFF9E7D2E);
  static const memberOfferBg = Color(0xFFFDF6E8);
  static const memberOfferBgDark = Color(0xFF3D3020);
  static const spendAndGet = Color(0xFFAF1685);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error logging
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    print('[CRASH] Flutter: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    print('[CRASH] Platform: $error\n$stack');
    return true;
  };

  await DatabaseService.init();
  await SearchService.init();
  await SyncService.init(); // WorkManager background sync
  SyncService.schedule(); // schedule nightly task
  BackgroundUpdater.checkAndRun();
  BackgroundUpdater.syncCatalogIfScheduled();
  runApp(const MyDansApp());
}

class MyDansApp extends StatefulWidget {
  const MyDansApp({super.key});

  @override
  State<MyDansApp> createState() => _MyDansAppState();
}

class _MyDansAppState extends State<MyDansApp> {
  String _themeMode = 'system'; // system, light, dark
  final int _catalogCount = 0;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await CacheService.getThemeMode();
    if (mounted) setState(() => _themeMode = mode);
  }

  void setThemeMode(String mode) async {
    setState(() => _themeMode = mode);
    await CacheService.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "MY Dan's",
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode == 'dark'
          ? ThemeMode.dark
          : _themeMode == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      home: HomeScreen(
        themeMode: _themeMode,
        catalogCount: _catalogCount,
        onThemeModeChanged: setThemeMode,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        brightness: brightness,
        surface: isDark ? const Color(0xFF152B1A) : null,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? AppColors.dark : null,
      cardColor: isDark ? AppColors.surface : Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String themeMode;
  final int catalogCount;
  final ValueChanged<String> onThemeModeChanged;

  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.catalogCount,
    required this.onThemeModeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const SearchScreen(),
      SettingsScreen(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search, color: AppColors.highlight),
            label: 'Search',
          ),
          NavigationDestination(
            icon: _buildSettingsIcon(false),
            selectedIcon: _buildSettingsIcon(true),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsIcon(bool selected) {
    return Icon(Icons.settings, color: selected ? AppColors.highlight : null);
  }
}
