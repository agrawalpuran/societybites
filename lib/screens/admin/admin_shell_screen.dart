import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/session_service.dart';
import '../../web/admin_content_frame.dart';
import 'admin_dashboard_screen.dart';
import 'admin_societies_screen.dart';
import 'admin_fssai_screen.dart';
import 'admin_address_proof_screen.dart';
import 'admin_listings_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reviews_screen.dart';
import 'admin_issues_screen.dart';
import 'admin_coupons_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_console_access_screen.dart';
import 'admin_users_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _selectedIndex = 0;
  List<Widget?> _pageCache = [];
  bool _isSuperAdmin = false;
  bool _roleLoaded = false;

  static const _baseNavItems = <_NavItem>[
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.apartment_rounded, label: 'Societies'),
    _NavItem(icon: Icons.badge_outlined, label: 'FSSAI'),
    _NavItem(icon: Icons.photo_camera_outlined, label: 'Address proof'),
    _NavItem(icon: Icons.fastfood_rounded, label: 'Listings'),
    _NavItem(icon: Icons.shopping_bag_rounded, label: 'Orders'),
    _NavItem(icon: Icons.star_rounded, label: 'Reviews'),
    _NavItem(icon: Icons.flag_outlined, label: 'Issues'),
    _NavItem(icon: Icons.confirmation_number_outlined, label: 'Coupons'),
    _NavItem(icon: Icons.history_rounded, label: 'Audit Log'),
  ];

  static const _usersNav = _NavItem(
    icon: Icons.people_outline_rounded,
    label: 'Users',
  );

  static const _consoleAccessNav = _NavItem(
    icon: Icons.manage_accounts_rounded,
    label: 'Console access',
  );

  List<_NavItem> get _navItems => _isSuperAdmin
      ? [..._baseNavItems, _usersNav, _consoleAccessNav]
      : _baseNavItems;

  @override
  void initState() {
    super.initState();
    _pageCache = List<Widget?>.filled(_baseNavItems.length, null);
    _pageCache[0] = _createPage(0);
    unawaited(_loadRole());
  }

  Future<void> _loadRole() async {
    final role = await SessionService.getRole();
    final consoleAdmin = await SessionService.isConsoleAdmin();
    if (!mounted) return;
    final superAdmin = role == 'super_admin';
    setState(() {
      _isSuperAdmin = superAdmin;
      _roleLoaded = true;
      if (superAdmin) {
        _pageCache = List<Widget?>.filled(_navItems.length, null);
        _pageCache[0] = _createPage(0);
      }
    });
  }

  Widget _createPage(int index) {
    if (_isSuperAdmin) {
      if (index == _baseNavItems.length) {
        return const AdminUsersScreen();
      }
      if (index == _baseNavItems.length + 1) {
        return const AdminConsoleAccessScreen();
      }
    }
    switch (index) {
      case 0:
        return const AdminDashboardScreen();
      case 1:
        return const AdminSocietiesScreen();
      case 2:
        return const AdminFssaiScreen();
      case 3:
        return const AdminAddressProofScreen();
      case 4:
        return const AdminListingsScreen();
      case 5:
        return const AdminOrdersScreen();
      case 6:
        return const AdminReviewsScreen();
      case 7:
        return const AdminIssuesScreen();
      case 8:
        return const AdminCouponsScreen();
      case 9:
        return const AdminAuditScreen();
      default:
        return const AdminDashboardScreen();
    }
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      if (index < _pageCache.length) {
        _pageCache[index] ??= _createPage(index);
      }
    });
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _selectedIndex,
      sizing: StackFit.expand,
      children: List.generate(
        _pageCache.length,
        (i) => _pageCache[i] ?? const SizedBox.shrink(),
      ),
    );
  }

  Widget _framedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_roleLoaded && !_isSuperAdmin) // view-only: consoleAdmin or legacy admin role
          const Material(
            color: Color(0xFFE8F5EE),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: Color(0xFF0E5A47),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'View only — you can browse data but cannot make changes.',
                      style: TextStyle(
                        color: Color(0xFF0E5A47),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: AdminContentFrame(child: _buildBody())),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final navItems = _navItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAF9),
            body: Row(
              children: [
                _SideNav(
                  items: navItems,
                  selectedIndex: _selectedIndex,
                  onSelected: _selectTab,
                  onBack: () => Navigator.pop(context),
                ),
                Expanded(child: _framedContent()),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAF9),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0E5A47),
            foregroundColor: Colors.white,
            title: const Text(
              'Admin Portal',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: _framedContent(),
          bottomNavigationBar: Material(
            color: Colors.white,
            child: SafeArea(
              child: SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: navItems.length,
                  itemBuilder: (context, index) {
                    final item = navItems[index];
                    final selected = index == _selectedIndex;
                    final color = selected
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFF8A9491);
                    return InkWell(
                      onTap: () => _selectTab(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.icon, color: color, size: 22),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.onBack,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF0E5A47),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white70),
                  onPressed: onBack,
                  tooltip: 'Back to App',
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Admin Portal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: isSelected
                        ? Colors.white.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 20,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              item.label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'SocietyBites Admin',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
