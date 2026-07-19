import 'package:flutter/material.dart';

import 'admin_dashboard_screen.dart';
import 'admin_users_screen.dart';
import 'admin_societies_screen.dart';
import 'admin_listings_screen.dart';
import 'admin_orders_screen.dart';
import 'admin_reviews_screen.dart';
import 'admin_audit_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _selectedIndex = 0;

  static const _navItems = <_NavItem>[
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _NavItem(icon: Icons.people_rounded, label: 'Users'),
    _NavItem(icon: Icons.apartment_rounded, label: 'Societies'),
    _NavItem(icon: Icons.fastfood_rounded, label: 'Listings'),
    _NavItem(icon: Icons.shopping_bag_rounded, label: 'Orders'),
    _NavItem(icon: Icons.star_rounded, label: 'Reviews'),
    _NavItem(icon: Icons.history_rounded, label: 'Audit Log'),
  ];

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const AdminDashboardScreen();
      case 1:
        return const AdminUsersScreen();
      case 2:
        return const AdminSocietiesScreen();
      case 3:
        return const AdminListingsScreen();
      case 4:
        return const AdminOrdersScreen();
      case 5:
        return const AdminReviewsScreen();
      case 6:
        return const AdminAuditScreen();
      default:
        return const AdminDashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAF9),
            body: Row(
              children: [
                _SideNav(
                  items: _navItems,
                  selectedIndex: _selectedIndex,
                  onSelected: (i) => setState(() => _selectedIndex = i),
                  onBack: () => Navigator.pop(context),
                ),
                Expanded(child: _buildBody()),
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
          body: _buildBody(),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF0E5A47),
            unselectedItemColor: const Color(0xFF8A9491),
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: _navItems
                .map((item) => BottomNavigationBarItem(
                      icon: Icon(item.icon),
                      label: item.label,
                    ))
                .toList(),
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
