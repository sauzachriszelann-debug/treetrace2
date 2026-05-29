import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/auth_provider.dart';
import 'services/theme.dart';
import 'screens/splash_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tree_list_screen.dart';
import 'screens/map_screen.dart';
import 'screens/scan_qr_screen.dart';
import 'screens/add_tree_screen.dart';
import 'screens/ai_identify_screen.dart';
import 'screens/public_portal_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  api.init();
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
        if (auth.loading) return const SplashScreen();
        if (!auth.isLoggedIn) return const LandingScreen();
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
  _NavItem('AI Identify', Icons.auto_awesome_outlined, Icons.auto_awesome),
  _NavItem('Map', Icons.map_outlined, Icons.map),
  _NavItem('More', Icons.more_horiz_rounded, Icons.more_horiz),
];

class AdminMainShell extends StatefulWidget {
  const AdminMainShell({super.key});
  @override
  State<AdminMainShell> createState() => _AdminMainShellState();
}

class _AdminMainShellState extends State<AdminMainShell> {
  int _index = 0;
  int _mapRefreshKey = 0;

  void _goHome() => setState(() => _index = 0);

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),
      const TreeListScreen(),
      AIIdentifyScreen(onBack: _goHome),
      MapScreen(onBack: _goHome, refreshKey: _mapRefreshKey),
      const ProfileScreen(toolsOnly: true),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: screens),
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onPressed: () async {
                final saved = await Navigator.push<bool>(context,
                    MaterialPageRoute(builder: (_) => const AddTreeScreen()));
                if (saved == true) {
                  setState(() => _mapRefreshKey++);
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: _TreeTraceBottomNav(
        items: _adminNavItems,
        selectedIndex: _index,
        emphasizedIndex: 2,
        emphasizedLabel: 'AI Scan',
        onSelected: (i) => setState(() {
          _index = i;
          if (i == 3) _mapRefreshKey++;
        }),
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
  _NavItem('More', Icons.more_horiz_rounded, Icons.more_horiz),
];

class PublicMainShell extends StatefulWidget {
  const PublicMainShell({super.key});
  @override
  State<PublicMainShell> createState() => _PublicMainShellState();
}

class _PublicMainShellState extends State<PublicMainShell> {
  int _index = 0;

  void _goHome() => setState(() => _index = 0);

  @override
  Widget build(BuildContext context) {
    final screens = [
      PublicPortalScreen(
        onOpenMap: () => setState(() => _index = 1),
      ),
      MapScreen(onBack: _goHome),
      AIIdentifyScreen(onBack: _goHome),
      ScanQRScreen(onBack: _goHome),
      const ProfileScreen(toolsOnly: true),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: _TreeTraceBottomNav(
        items: _publicNavItems,
        selectedIndex: _index,
        emphasizedIndex: 2,
        emphasizedLabel: 'AI Scan',
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _TreeTraceBottomNav extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final int emphasizedIndex;
  final String emphasizedLabel;
  final ValueChanged<int> onSelected;
  const _TreeTraceBottomNav({
    required this.items,
    required this.selectedIndex,
    required this.emphasizedIndex,
    required this.emphasizedLabel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 78,
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
        decoration: BoxDecoration(
          color: kCard,
          border: const Border(top: BorderSide(color: kBorder, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (index) {
            if (index == emphasizedIndex) {
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelected(index),
                  child: SizedBox(
                    height: 78,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Positioned(
                          top: -18,
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: kPrimary,
                              shape: BoxShape.circle,
                              border: Border.all(color: kCard, width: 5),
                              boxShadow: [
                                BoxShadow(
                                  color: kPrimary.withOpacity(0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          child: Text(
                            emphasizedLabel,
                            maxLines: 1,
                            style: TextStyle(
                              color: selectedIndex == index
                                  ? kPrimary
                                  : kMutedFg,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final item = items[index];
            final selected = selectedIndex == index;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? item.activeIcon : item.icon,
                      color: selected ? kPrimary : kMutedFg,
                      size: 21,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? kPrimary : kMutedFg,
                        fontSize: 9,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
