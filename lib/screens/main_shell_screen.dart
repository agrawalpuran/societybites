import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
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

class _MainShellScreenState extends State<MainShellScreen>
    with WidgetsBindingObserver {
  late int _navIndex;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _ordersKey = GlobalKey<OrdersScreenState>();
  final _dashboardKey = GlobalKey<SellerDashboardScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navIndex = widget.initialIndex;
    PushNotificationService.onForegroundOrderUpdate = _refreshVisibleTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.registerIfPossible();
    });
  }

  @override
  void dispose() {
    if (PushNotificationService.onForegroundOrderUpdate == _refreshVisibleTab) {
      PushNotificationService.onForegroundOrderUpdate = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshVisibleTab();
    }
  }

  void _refreshVisibleTab() {
    switch (_navIndex) {
      case 0:
        _homeKey.currentState?.refresh();
        break;
      case 1:
        _ordersKey.currentState?.refresh();
        break;
      case 2:
        _dashboardKey.currentState?.refresh();
        break;
    }
  }

  void _selectTab(int index) {
    setState(() => _navIndex = index);
    switch (index) {
      case 0:
        _homeKey.currentState?.refresh();
        break;
      case 1:
        _ordersKey.currentState?.refresh();
        break;
      case 2:
        _dashboardKey.currentState?.refresh();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _navIndex,
        children: [
          HomeScreen(key: _homeKey),
          OrdersScreen(key: _ordersKey, onExploreHome: () => _selectTab(0)),
          SellerDashboardScreen(key: _dashboardKey),
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
