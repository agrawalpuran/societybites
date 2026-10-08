import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/cart_controller.dart';
import '../services/listing_publish_navigation.dart';
import '../services/order_push_coordinator.dart';
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
  const MainShellScreen({
    super.key,
    this.initialIndex = 0,
    this.focusOrderId,
  });

  final int initialIndex;

  /// Order from a notification tap — kitchen prefetches it before the full list.
  final String? focusOrderId;

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
    PushNotificationService.onForegroundOrderUpdate = _syncOrdersFromPush;
    CartController.instance.onShowOrdersAfterPlace = _showOrdersAfterCheckout;
    CartController.instance.onSelectShellTab = _selectTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.registerIfPossible();
    });
    unawaited(SessionService.warmAuthCache());
    ListingPublishNavigation.onPublished = _onListingPublishedToHome;
    _sessionCheck = _refreshSignedIn();
    _unreadPoll = Timer.periodic(const Duration(seconds: 12), (_) {
      _pollUnread();
    });
    if (widget.focusOrderId != null ||
        widget.initialIndex == 1 ||
        widget.initialIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncOrdersFromPush();
      });
    }
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

  void _onWebTab(int index) => _selectTab(index);

  void _onHomeReady() {
    unawaited(() async {
      await _sessionCheck;
      if (!mounted || (kIsWeb && _signedIn == false)) return;
      _preload.onHomeInitialLoadSuccess();
    }());
  }

  void _onListingPublishedToHome() {
    if (!mounted) return;
    _dashboardKey.currentState?.refresh();
    _homeKey.currentState?.refresh();
    _selectTab(0);
  }

  @override
  void dispose() {
    if (ListingPublishNavigation.onPublished == _onListingPublishedToHome) {
      ListingPublishNavigation.onPublished = null;
    }
    _preload.dispose();
    _unreadPoll?.cancel();
    if (PushNotificationService.onForegroundOrderUpdate == _syncOrdersFromPush) {
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
      _syncOrdersFromPush();
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
    setState(() {
      _navIndex = 1;
      _ordersMounted = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final placed = CartController.instance.takeBuyerOrderPaymentPatch();
      if (placed != null) {
        _ordersKey.currentState?.applyOrderFromPayment(placed);
      }
      _ordersKey.currentState?.refresh(lightweight: true);
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

  void _syncOrdersFromPush() {
    unawaited(_syncOrdersFromPushAsync());
  }

  Future<void> _syncOrdersFromPushAsync() async {
    await OrderPushCoordinator.ensureHydrated();
    if (!mounted) return;

    final hints = OrderPushCoordinator.pendingHints;
    final mountOrders =
        hints.isNotEmpty || (widget.focusOrderId?.isNotEmpty ?? false);
    final mountKitchen = mountOrders ||
        widget.initialIndex == 2 ||
        hints.any(_hintTargetsSellerKitchen);

    if (!_ordersMounted && mountOrders) {
      setState(() => _ordersMounted = true);
    }
    if (!_dashboardMounted && mountKitchen) {
      setState(() => _dashboardMounted = true);
    }

    if (mountOrders) await _awaitOrdersScreenState();
    if (mountKitchen) await _awaitDashboardScreenState();

    if (hints.isNotEmpty) {
      await _ordersKey.currentState?.applyPushHints(hints);
      _dashboardKey.currentState?.applyPushHints(hints);
    }

    unawaited(
      _ordersKey.currentState?.prefetchOrdersFromPush(
        focusOrderId: widget.focusOrderId,
      ),
    );
    unawaited(
      _dashboardKey.currentState?.prefetchOrdersFromPush(
        focusOrderId: widget.focusOrderId,
      ),
    );

    if (hints.isEmpty) {
      _homeKey.currentState?.refresh();
    }
    if (_ordersKey.currentState?.hasSuccessfullyLoaded == true) {
      _ordersKey.currentState?.refresh(lightweight: true);
    }
    final kitchen = _dashboardKey.currentState;
    if (kitchen != null && kitchen.hasSuccessfullyLoaded) {
      kitchen.refresh(lightweight: true);
    }
  }

  static bool _hintTargetsSellerKitchen(OrderPushHint hint) {
    final status = hint.status;
    if (status == 'pending') return true;
    if (hint.paymentStatus == 'buyer_marked_paid') return true;
    return status == 'cancelled' || status == 'picked_up';
  }

  Future<void> _awaitOrdersScreenState() async {
    for (var i = 0; i < 12; i++) {
      if (!mounted) return;
      if (_ordersKey.currentState != null) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _awaitDashboardScreenState() async {
    for (var i = 0; i < 12; i++) {
      if (!mounted) return;
      if (_dashboardKey.currentState != null) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _selectTab(int index) {
    if (kIsWeb && index != 0 && _signedIn != true) {
      unawaited(_openProtectedWebTab(index));
      return;
    }
    _showTab(index);
  }

  Future<void> _openProtectedWebTab(int index) async {
    await _sessionCheck;
    if (!mounted) return;
    if (_signedIn != true) {
      _openSignIn();
      return;
    }
    _showTab(index);
  }

  void _showTab(int index) {
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
                  priorityOrderId: widget.focusOrderId,
                  onInitialLoadSettled: _preload.onDashboardInitialLoadSettled,
                  onListingCreated: _onListingPublishedToHome,
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
