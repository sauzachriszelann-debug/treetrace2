import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/auth_provider.dart';
import 'services/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tree_list_screen.dart';
import 'screens/map_screen.dart';
import 'screens/scan_qr_screen.dart';
import 'screens/add_tree_screen.dart';
import 'screens/ai_identify_screen.dart';
import 'screens/public_portal_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  debugPrint("DEBUG: main() started");
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  debugPrint("DEBUG: Initializing API...");
  api.init();
  debugPrint("DEBUG: Running App...");
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..init(),
      child: const TreeTraceApp(),
    ),
  );
}

class TreeTraceApp extends StatelessWidget {
  const TreeTraceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TreeTrace',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Consumer<AuthProvider>(builder: (_, auth, __) {
        debugPrint("DEBUG: Consumer Build - Loading: ${auth.loading}, LoggedIn: ${auth.isLoggedIn}");
        if (auth.loading) return const SplashScreen();
        if (!auth.isLoggedIn) return const LoginScreen();
        if (auth.user?.role == 'citizen') return const PublicMainShell();
        return const AdminMainShell();
      }),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem(this.label, this.icon, this.activeIcon);
}

// ── Admin/Field Worker Shell ──────────────────────────────────────────────────
const _adminNavItems = [
  _NavItem('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  _NavItem('Trees', Icons.forest_outlined, Icons.forest),
  _NavItem('Map', Icons.map_outlined, Icons.map),
  _NavItem('AI Identify', Icons.auto_awesome_outlined, Icons.auto_awesome),
  _NavItem('Scan QR', Icons.qr_code_scanner_outlined, Icons.qr_code_scanner),
];

class AdminMainShell extends StatefulWidget {
  const AdminMainShell({super.key});
  @override
  State<AdminMainShell> createState() => _AdminMainShellState();
}

class _AdminMainShellState extends State<AdminMainShell> {
  int _index = 0;
  final _screens = const [
    DashboardScreen(),
    TreeListScreen(),
    MapScreen(),
    AIIdentifyScreen(),
    ScanQRScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AddTreeScreen()));
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kBorder, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: kCard,
          indicatorColor: kPrimary.withOpacity(0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _adminNavItems.map((item) => NavigationDestination(
            icon: Icon(item.icon, color: kMutedFg),
            selectedIcon: Icon(item.activeIcon, color: kPrimary),
            label: item.label,
          )).toList(),
        ),
      ),
    );
  }
}

// ── Public/Citizen Shell ──────────────────────────────────────────────────────
const _publicNavItems = [
  _NavItem('Explore', Icons.explore_outlined, Icons.explore),
  _NavItem('Map', Icons.map_outlined, Icons.map),
  _NavItem('AI Scan', Icons.auto_awesome_outlined, Icons.auto_awesome),
  _NavItem('Scan QR', Icons.qr_code_scanner_outlined, Icons.qr_code_scanner),
  _NavItem('Profile', Icons.person_outline, Icons.person),
];

class PublicMainShell extends StatefulWidget {
  const PublicMainShell({super.key});
  @override
  State<PublicMainShell> createState() => _PublicMainShellState();
}

class _PublicMainShellState extends State<PublicMainShell> {
  int _index = 0;
  final _screens = const [
    PublicPortalScreen(),
    MapScreen(),
    AIIdentifyScreen(),
    ScanQRScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kBorder, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: kCard,
          indicatorColor: kPrimary.withOpacity(0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _publicNavItems.map((item) => NavigationDestination(
            icon: Icon(item.icon, color: kMutedFg),
            selectedIcon: Icon(item.activeIcon, color: kPrimary),
            label: item.label,
          )).toList(),
        ),
      ),
    );
  }
}
