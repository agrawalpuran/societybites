import 'package:flutter/material.dart';

import '../services/push_notification_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'seller_dashboard_screen.dart';
import 'tab_preload.dart';
import 'tab_select_load.dart';

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

  late final HomeFirstPreload _preload;
  var _ordersMounted = false;
  var _dashboardMounted = false;
  var _profileMounted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navIndex = widget.initialIndex;
    _ordersMounted = _navIndex == 1;
    _dashboardMounted = _navIndex == 2;
    _profileMounted = _navIndex == 3;
    _preload = HomeFirstPreload(
      onMountOrders: _mountOrders,
      onMountDashboard: _mountDashboard,
    );
    PushNotificationService.onForegroundOrderUpdate = _refreshVisibleTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.registerIfPossible();
    });
  }

  @override
  void dispose() {
    _preload.dispose();
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

  void _mountOrders() {
    if (!mounted || _ordersMounted) return;
    setState(() => _ordersMounted = true);
  }

  void _mountDashboard() {
    if (!mounted || _dashboardMounted) return;
    setState(() => _dashboardMounted = true);
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
    final wasOrdersMounted = _ordersMounted;
    final wasDashboardMounted = _dashboardMounted;

    setState(() {
      _navIndex = index;
      if (index == 1) _ordersMounted = true;
      if (index == 2) _dashboardMounted = true;
      if (index == 3) _profileMounted = true;
    });

    switch (index) {
      case 0:
        final home = _homeKey.currentState;
        if (home != null &&
            shouldFetchOnTabSelect(
              hasSuccessfullyLoaded: home.hasSuccessfullyLoaded,
              isLoadInProgress: home.isLoadInProgress,
            )) {
          home.refresh();
        }
        break;
      case 1:
        if (!wasOrdersMounted) break;
        final orders = _ordersKey.currentState;
        if (orders != null &&
            shouldFetchOnTabSelect(
              hasSuccessfullyLoaded: orders.hasSuccessfullyLoaded,
              isLoadInProgress: orders.isLoadInProgress,
            )) {
          orders.refresh();
        }
        break;
      case 2:
        if (!wasDashboardMounted) break;
        final dashboard = _dashboardKey.currentState;
        if (dashboard != null &&
            shouldFetchOnTabSelect(
              hasSuccessfullyLoaded: dashboard.hasSuccessfullyLoaded,
              isLoadInProgress: dashboard.isLoadInProgress,
            )) {
          dashboard.refresh();
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _navIndex,
        children: [
          HomeScreen(
            key: _homeKey,
            onInitialLoadSuccess: _preload.onHomeInitialLoadSuccess,
          ),
          _ordersMounted
              ? OrdersScreen(
                  key: _ordersKey,
                  onExploreHome: () => _selectTab(0),
                  onInitialLoadSettled: _preload.onOrdersInitialLoadSettled,
                )
              : const SizedBox.shrink(),
          _dashboardMounted
              ? SellerDashboardScreen(
                  key: _dashboardKey,
                  onInitialLoadSettled: _preload.onDashboardInitialLoadSettled,
                )
              : const SizedBox.shrink(),
          _profileMounted
              ? ProfileScreen(onSelectTab: _selectTab)
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _navIndex,
        onTap: _selectTab,
      ),
    );
  }
}
