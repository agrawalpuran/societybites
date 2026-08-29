import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/tab_preload.dart';
import 'package:societybites/screens/tab_select_load.dart';
import 'package:societybites/widgets/app_bottom_nav.dart';

class _FakeTab extends StatefulWidget {
  const _FakeTab({
    super.key,
    required this.label,
    required this.loadCounts,
    this.failFirstLoad = false,
    this.hold,
    this.onInitialLoadSuccess,
    this.onInitialLoadSettled,
  });

  final String label;
  final Map<String, int> loadCounts;
  final bool failFirstLoad;
  final Future<void>? hold;
  final VoidCallback? onInitialLoadSuccess;
  final VoidCallback? onInitialLoadSettled;

  @override
  State<_FakeTab> createState() => _FakeTabState();
}

class _FakeTabState extends State<_FakeTab> {
  var _hasSuccessfullyLoaded = false;
  var _isLoading = true;
  var _failed = false;
  var _loadGeneration = 0;

  bool get hasSuccessfullyLoaded => _hasSuccessfullyLoaded;
  bool get isLoadInProgress => _isLoading;

  @override
  void initState() {
    super.initState();
    widget.loadCounts[widget.label] =
        (widget.loadCounts[widget.label] ?? 0) + 1;
    _loadGeneration = 1;
    if (widget.hold != null) {
      widget.hold!.then((_) {
        if (!mounted) return;
        setState(_applyInitialResult);
        _notifyInitial();
      });
    } else {
      _applyInitialResult();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _notifyInitial();
      });
    }
  }

  void _applyInitialResult() {
    final shouldFail =
        widget.failFirstLoad && widget.loadCounts[widget.label] == 1;
    _isLoading = false;
    _failed = shouldFail;
    if (!shouldFail) {
      _hasSuccessfullyLoaded = true;
    }
  }

  void _notifyInitial() {
    if (widget.label == 'Home') {
      if (!_failed) widget.onInitialLoadSuccess?.call();
    } else {
      widget.onInitialLoadSettled?.call();
    }
  }

  void refresh() {
    setState(() {
      widget.loadCounts[widget.label] =
          (widget.loadCounts[widget.label] ?? 0) + 1;
      _loadGeneration++;
      final shouldFail =
          widget.failFirstLoad && widget.loadCounts[widget.label] == 1;
      _isLoading = false;
      _failed = shouldFail;
      if (!shouldFail) {
        _hasSuccessfullyLoaded = true;
      }
    });
    if (widget.label == 'Home' && !_failed) {
      widget.onInitialLoadSuccess?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: Text('${widget.label} loading'));
    }
    if (_failed) {
      return Center(child: Text('${widget.label} failed'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        refresh();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('${widget.label} content $_loadGeneration'),
          const SizedBox(height: 800, child: Text('scroll filler')),
        ],
      ),
    );
  }
}

class _TestShell extends StatefulWidget {
  const _TestShell({
    super.key,
    this.failHomeFirst = false,
    this.failOrdersFirst = false,
    this.ordersHold,
    this.dashboardHold,
    required this.loadCounts,
  });

  final bool failHomeFirst;
  final bool failOrdersFirst;
  final Future<void>? ordersHold;
  final Future<void>? dashboardHold;
  final Map<String, int> loadCounts;

  @override
  State<_TestShell> createState() => _TestShellState();
}

class _TestShellState extends State<_TestShell> {
  var _index = 0;
  final _homeKey = GlobalKey<_FakeTabState>();
  final _ordersKey = GlobalKey<_FakeTabState>();
  final _dashboardKey = GlobalKey<_FakeTabState>();
  late final HomeFirstPreload _preload;
  var _ordersMounted = false;
  var _dashboardMounted = false;
  var _profileMounted = false;

  VoidCallback? onForegroundRefresh;

  @override
  void initState() {
    super.initState();
    onForegroundRefresh = _refreshVisibleTab;
    _preload = HomeFirstPreload(
      onMountOrders: () {
        if (!mounted || _ordersMounted) return;
        setState(() => _ordersMounted = true);
      },
      onMountDashboard: () {
        if (!mounted || _dashboardMounted) return;
        setState(() => _dashboardMounted = true);
      },
      log: (_) {},
    );
  }

  @override
  void dispose() {
    _preload.dispose();
    super.dispose();
  }

  void _refreshVisibleTab() {
    switch (_index) {
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
      _index = index;
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
        index: _index,
        children: [
          _FakeTab(
            key: _homeKey,
            label: 'Home',
            loadCounts: widget.loadCounts,
            failFirstLoad: widget.failHomeFirst,
            onInitialLoadSuccess: _preload.onHomeInitialLoadSuccess,
          ),
          _ordersMounted
              ? _FakeTab(
                  key: _ordersKey,
                  label: 'Orders',
                  loadCounts: widget.loadCounts,
                  failFirstLoad: widget.failOrdersFirst,
                  hold: widget.ordersHold,
                  onInitialLoadSettled: _preload.onOrdersInitialLoadSettled,
                )
              : const SizedBox.shrink(),
          _dashboardMounted
              ? _FakeTab(
                  key: _dashboardKey,
                  label: 'Dashboard',
                  loadCounts: widget.loadCounts,
                  hold: widget.dashboardHold,
                  onInitialLoadSettled: _preload.onDashboardInitialLoadSettled,
                )
              : const SizedBox.shrink(),
          _profileMounted
              ? const Center(child: Text('Profile content'))
              : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        selectedIndex: _index,
        onTap: _selectTab,
      ),
    );
  }
}

void main() {
  testWidgets('Home loads first and is not blocked by other tabs', (
    tester,
  ) async {
    final loads = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(home: _TestShell(loadCounts: loads)),
    );

    expect(find.text('Home content 1'), findsOneWidget);
    expect(loads['Home'], 1);
    expect(loads['Orders'], isNull);
    expect(loads['Dashboard'], isNull);
    expect(find.byType(_FakeTab, skipOffstage: false), findsOneWidget);
  });

  testWidgets('background preload starts after Home succeeds, sequentially', (
    tester,
  ) async {
    final loads = <String, int>{};
    final ordersHold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: _TestShell(loadCounts: loads, ordersHold: ordersHold.future),
      ),
    );

    expect(loads['Home'], 1);
    expect(loads['Orders'], isNull);

    await tester.pump();
    expect(loads['Orders'], 1);
    expect(loads['Dashboard'], isNull);
    expect(find.text('Orders loading', skipOffstage: false), findsOneWidget);

    ordersHold.complete();
    await tester.pump();
    await tester.pump();
    expect(loads['Dashboard'], 1);
    expect(find.text('Dashboard content 1', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Profile is not auto-preloaded', (tester) async {
    final loads = <String, int>{};
    await tester.pumpWidget(MaterialApp(home: _TestShell(loadCounts: loads)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Profile content', skipOffstage: false), findsNothing);

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pump();
    expect(find.text('Profile content'), findsOneWidget);
    expect(loads['Home'], 1);
    expect(loads['Orders'], 1);
    expect(loads['Dashboard'], 1);
  });

  testWidgets('completed Orders preload is shown immediately without refetch', (
    tester,
  ) async {
    final loads = <String, int>{};
    await tester.pumpWidget(MaterialApp(home: _TestShell(loadCounts: loads)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(loads['Orders'], 1);

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(find.text('Orders content 1'), findsOneWidget);
    expect(loads['Orders'], 1);
    expect(find.text('Orders loading'), findsNothing);
  });

  testWidgets('tapping Orders during preload does not start a second request', (
    tester,
  ) async {
    final loads = <String, int>{};
    final ordersHold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: _TestShell(loadCounts: loads, ordersHold: ordersHold.future),
      ),
    );
    await tester.pump();
    expect(loads['Orders'], 1);

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(find.text('Orders loading'), findsOneWidget);
    expect(loads['Orders'], 1);

    ordersHold.complete();
    await tester.pump();
    expect(find.text('Orders content 1'), findsOneWidget);
    expect(loads['Orders'], 1);
  });

  testWidgets('failed Orders preload can be retried by tapping Orders', (
    tester,
  ) async {
    final loads = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: _TestShell(failOrdersFirst: true, loadCounts: loads),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(loads['Orders'], 1);
    expect(
      find.text('Orders failed', skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(find.text('Orders content 2'), findsOneWidget);
    expect(loads['Orders'], 2);
  });

  testWidgets('tapping Dashboard during preload does not duplicate the request', (
    tester,
  ) async {
    final loads = <String, int>{};
    final dashboardHold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: _TestShell(loadCounts: loads, dashboardHold: dashboardHold.future),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(loads['Dashboard'], 1);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    expect(find.text('Dashboard loading'), findsOneWidget);
    expect(loads['Dashboard'], 1);

    dashboardHold.complete();
    await tester.pump();
    expect(find.text('Dashboard content 1'), findsOneWidget);
    expect(loads['Dashboard'], 1);
  });

  testWidgets('already-loaded tabs do not refetch on tap', (tester) async {
    final loads = <String, int>{};
    await tester.pumpWidget(MaterialApp(home: _TestShell(loadCounts: loads)));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(loads['Orders'], 1);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();
    expect(loads['Home'], 1);

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(loads['Orders'], 1);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    expect(loads['Dashboard'], 1);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    expect(loads['Dashboard'], 1);
  });

  testWidgets('pull-to-refresh and FCM-style refresh still fetch', (
    tester,
  ) async {
    final loads = <String, int>{};
    final shellKey = GlobalKey<_TestShellState>();
    await tester.pumpWidget(
      MaterialApp(home: _TestShell(key: shellKey, loadCounts: loads)),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(loads['Home'], 2);
    expect(find.text('Home content 2'), findsOneWidget);

    shellKey.currentState!.onForegroundRefresh?.call();
    await tester.pump();
    expect(loads['Home'], 3);
  });

  testWidgets('app-resume style refresh still fetches the visible tab', (
    tester,
  ) async {
    final loads = <String, int>{};
    final shellKey = GlobalKey<_TestShellState>();
    await tester.pumpWidget(
      MaterialApp(home: _TestShell(key: shellKey, loadCounts: loads)),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(loads['Orders'], 1);

    shellKey.currentState!.onForegroundRefresh?.call();
    await tester.pump();
    expect(loads['Orders'], 2);
  });

  testWidgets('failed home load can be retried by tapping Home again', (
    tester,
  ) async {
    final loads = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(home: _TestShell(failHomeFirst: true, loadCounts: loads)),
    );
    await tester.pump();

    expect(find.text('Home failed'), findsOneWidget);
    expect(loads['Home'], 1);
    expect(loads['Orders'], isNull);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('Home content 2'), findsOneWidget);
    expect(loads['Home'], 2);
  });

  testWidgets('disposing during Orders preload does not throw', (tester) async {
    final loads = <String, int>{};
    final ordersHold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: _TestShell(loadCounts: loads, ordersHold: ordersHold.future),
      ),
    );
    await tester.pump();
    expect(loads['Orders'], 1);

    await tester.pumpWidget(const SizedBox.shrink());
    ordersHold.complete();
    await tester.pump();
  });
}
