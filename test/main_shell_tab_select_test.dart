import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/tab_select_load.dart';
import 'package:societybites/widgets/app_bottom_nav.dart';

class _FakeTab extends StatefulWidget {
  const _FakeTab({
    super.key,
    required this.label,
    required this.loadCounts,
    this.failFirstLoad = false,
  });

  final String label;
  final Map<String, int> loadCounts;
  final bool failFirstLoad;

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
    _completeLoad();
  }

  void refresh() {
    setState(_completeLoad);
  }

  void _completeLoad() {
    widget.loadCounts[widget.label] = (widget.loadCounts[widget.label] ?? 0) + 1;
    _loadGeneration++;
    final shouldFail =
        widget.failFirstLoad && widget.loadCounts[widget.label] == 1;
    _isLoading = false;
    _failed = shouldFail;
    if (!shouldFail) {
      _hasSuccessfullyLoaded = true;
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
    required this.loadCounts,
  });

  final bool failHomeFirst;
  final Map<String, int> loadCounts;

  @override
  State<_TestShell> createState() => _TestShellState();
}

class _TestShellState extends State<_TestShell> {
  var _index = 0;
  final _homeKey = GlobalKey<_FakeTabState>();
  final _ordersKey = GlobalKey<_FakeTabState>();
  final _dashboardKey = GlobalKey<_FakeTabState>();

  VoidCallback? onForegroundRefresh;

  @override
  void initState() {
    super.initState();
    onForegroundRefresh = _refreshVisibleTab;
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
    setState(() => _index = index);
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
          ),
          _FakeTab(
            key: _ordersKey,
            label: 'Orders',
            loadCounts: widget.loadCounts,
          ),
          _FakeTab(
            key: _dashboardKey,
            label: 'Dashboard',
            loadCounts: widget.loadCounts,
          ),
          const Center(child: Text('Profile content')),
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
  testWidgets('tab taps keep loaded data and do not refetch', (tester) async {
    final loads = <String, int>{};
    final shellKey = GlobalKey<_TestShellState>();
    await tester.pumpWidget(
      MaterialApp(home: _TestShell(key: shellKey, loadCounts: loads)),
    );
    await tester.pump();

    expect(find.byType(IndexedStack), findsOneWidget);
    expect(find.text('Home content 1'), findsOneWidget);
    expect(loads['Home'], 1);
    expect(loads['Orders'], 1);
    expect(loads['Dashboard'], 1);

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(find.text('Orders content 1'), findsOneWidget);
    expect(loads['Orders'], 1);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();
    expect(find.text('Home content 1'), findsOneWidget);
    expect(loads['Home'], 1);

    await tester.tap(find.byIcon(Icons.shopping_bag_rounded));
    await tester.pump();
    expect(find.text('Orders content 1'), findsOneWidget);
    expect(loads['Orders'], 1);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    expect(find.text('Dashboard content 1'), findsOneWidget);
    expect(loads['Dashboard'], 1);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pump();
    expect(loads['Dashboard'], 1);
    expect(find.byType(_FakeTab, skipOffstage: false), findsNWidgets(3));

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(loads['Home'], 2);
    expect(find.text('Home content 2'), findsOneWidget);

    shellKey.currentState!.onForegroundRefresh?.call();
    await tester.pump();
    await tester.pump();
    expect(loads['Home'], 3);
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

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('Home content 2'), findsOneWidget);
    expect(loads['Home'], 2);
  });

  testWidgets('profile tab does not fetch home/orders/dashboard', (tester) async {
    final loads = <String, int>{};
    await tester.pumpWidget(MaterialApp(home: _TestShell(loadCounts: loads)));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pump();
    expect(find.text('Profile content'), findsOneWidget);
    expect(loads['Home'], 1);
    expect(loads['Orders'], 1);
    expect(loads['Dashboard'], 1);
  });
}
