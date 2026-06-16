import 'package:flutter/material.dart';

import '../widgets/app_bottom_nav.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'seller_dashboard_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _navIndex;

  @override
  void initState() {
    super.initState();
    _navIndex = widget.initialIndex;
  }

  void _selectTab(int index) {
    setState(() => _navIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _navIndex,
        children: [
          const HomeScreen(),
          OrdersScreen(onExploreHome: () => _selectTab(0)),
          const SellerDashboardScreen(),
          ProfileScreen(onSelectTab: _selectTab),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _navIndex,
        onTap: _selectTab,
      ),
    );
  }
}
