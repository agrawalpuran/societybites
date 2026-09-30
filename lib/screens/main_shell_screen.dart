import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/cart_controller.dart';
import '../services/push_notification_service.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../web/web_breakpoints.dart';
import '../web/web_cart_dock.dart';
import '../web/web_shell_header.dart';
import '../widgets/app_bottom_nav.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'seller_dashboard_screen.dart';
import 'login_screen.dart';
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
  final _profileKey = GlobalKey<ProfileScreenState>();

  late final HomeFirstPreload _preload;
  var _ordersMounted = false;
  var _dashboardMounted = false;
  var _profileMounted = false;
  var _kitchenAttentionCount = 0;
  bool? _signedIn;
  Future<void>? _sessionCheck;
  Timer? _unreadPoll;

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
    CartController.instance.onShowOrdersAfterPlace = _showOrdersAfterCheckout;
    CartController.instance.onSelectShellTab = _selectTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.registerIfPossible();
    });
    _sessionCheck = _refreshSignedIn();
    _unreadPoll = Timer.periodic(const Duration(seconds: 12), (_) {
      _pollUnread();
    });
  }

  Future<void> _refreshSignedIn() async {
    final token = await SessionService.getToken();
    final refresh = await SessionService.getRefreshToken();
    if (!mounted) return;
    setState(() {
      _signedIn = (token != null && token.isNotEmpty) ||
          (refresh != null && refresh.isNotEmpty);
    });
  }

  void _openSignIn() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _onWebTab(int index) {
    if (kIsWeb && _signedIn == false && index != 0) {
      _openSignIn();
      return;
    }
    _selectTab(index);
  }

  void _onHomeReady() {
    unawaited(() async {
      await _sessionCheck;
      if (!mounted || (kIsWeb && _signedIn == false)) return;
      _preload.onHomeInitialLoadSuccess();
    }());
  }

  @override
  void dispose() {
    _preload.dispose();
    _unreadPoll?.cancel();
    if (PushNotificationService.onForegroundOrderUpdate == _refreshVisibleTab) {
      PushNotificationService.onForegroundOrderUpdate = null;
    }
    if (identical(
      CartController.instance.onShowOrdersAfterPlace,
      _showOrdersAfterCheckout,
    )) {
      CartController.instance.onShowOrdersAfterPlace = null;
    }
    if (identical(CartController.instance.onSelectShellTab, _selectTab)) {
      CartController.instance.onSelectShellTab = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushNotificationService.registerIfPossible();
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

  /// After checkout from Home or a listing/storefront, land on Orders.
  void _showOrdersAfterCheckout() {
    if (!mounted) return;
    final wasMounted = _ordersMounted;
    setState(() {
      _navIndex = 1;
      _ordersMounted = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (wasMounted) _ordersKey.currentState?.refresh();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Order placed',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: const Color(0xFF0E5A47),
          ),
        );
    });
  }

  void _pollUnread() {
    _ordersKey.currentState?.refreshUnread();
    _dashboardKey.currentState?.refreshUnread();
  }

  void _refreshVisibleTab() {
    _homeKey.currentState?.refresh();
    _ordersKey.currentState?.refresh();
    _dashboardKey.currentState?.refresh();
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
        final dashboard = _dashboardKey.currentState;
        dashboard?.showKitchenOrders();
        if (!wasDashboardMounted) break;
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

  Future<void> _onMarketplaceStartSelling() async {
    try {
      final enabled = await SellerOnboarding.startSelling(context);
      if (!enabled || !mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _selectTab(3);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _profileKey.currentState?.openSellerSettingsAfterEnable();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable selling: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _navIndex,
      children: [
          HomeScreen(
            key: _homeKey,
            onInitialLoadSuccess: _onHomeReady,
            onStartSelling: _onMarketplaceStartSelling,
            onSelectTab: _selectTab,
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
                  onListingCreated: () {
                    _dashboardKey.currentState?.refresh();
                    _homeKey.currentState?.refresh();
                    _selectTab(0);
                  },
                  onStartSelling: _onMarketplaceStartSelling,
                  onKitchenAttentionCount: (count) {
                    if (!mounted || count == _kitchenAttentionCount) return;
                    setState(() => _kitchenAttentionCount = count);
                  },
                )
              : const SizedBox.shrink(),
          _profileMounted
              ? ProfileScreen(
                  key: _profileKey,
                  onSelectTab: _selectTab,
                )
              : const SizedBox.shrink(),
        ],
    );
    if (useWebMarketplaceLayout(context)) {
      return Scaffold(
        backgroundColor: webPageBackground,
        body: Column(
          children: [
            WebShellHeader(
              selectedTab: _navIndex,
              kitchenAttentionCount: _kitchenAttentionCount,
              signedIn: _signedIn,
              selectedFoodType: _homeKey.currentState?.webSelectedFoodType,
              onSelectTab: _onWebTab,
              onSignIn: _openSignIn,
              onFoodTypeChanged: (value) {
                _homeKey.currentState?.setWebFoodType(value);
                if (_navIndex != 0) _selectTab(0);
                setState(() {});
              },
              onSearchChanged: (value) {
                _homeKey.currentState?.setWebSearch(value);
                if (_navIndex != 0) _selectTab(0);
              },
            ),
            Expanded(child: pages),
            const WebCartDock(),
          ],
        ),
      );
    }
    return Scaffold(
      body: pages,
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _navIndex,
        kitchenAttentionCount: _kitchenAttentionCount,
        onTap: _selectTab,
      ),
    );
  }
}
