import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/tab_preload.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('does not start preload until Home succeeds', () async {
    var orders = 0;
    var dashboard = 0;
    final preload = HomeFirstPreload(
      onMountOrders: () => orders++,
      onMountDashboard: () => dashboard++,
      log: (_) {},
    );

    await _flush();
    expect(orders, 0);
    expect(dashboard, 0);
    expect(preload.hasStarted, isFalse);

    preload.dispose();
  });

  test('after Home succeeds, Orders mounts before Dashboard', () async {
    var orders = 0;
    var dashboard = 0;
    final logs = <String>[];
    final preload = HomeFirstPreload(
      onMountOrders: () => orders++,
      onMountDashboard: () => dashboard++,
      log: logs.add,
    );

    preload.onHomeInitialLoadSuccess();
    await _flush();

    expect(preload.hasStarted, isTrue);
    expect(orders, 1);
    expect(dashboard, 0);
    expect(logs, contains('BACKGROUND PRELOAD START'));
    expect(logs, contains('ORDERS PRELOAD START'));
    expect(logs, isNot(contains('DASHBOARD PRELOAD START')));

    preload.onOrdersInitialLoadSettled();
    await _flush();

    expect(dashboard, 1);
    expect(logs, contains('ORDERS PRELOAD COMPLETE'));
    expect(logs, contains('DASHBOARD PRELOAD START'));

    preload.onDashboardInitialLoadSettled();
    await _flush();
    expect(logs, contains('DASHBOARD PRELOAD COMPLETE'));

    preload.dispose();
  });

  test('a second Home success does not restart preload', () async {
    var orders = 0;
    final preload = HomeFirstPreload(
      onMountOrders: () => orders++,
      onMountDashboard: () {},
      log: (_) {},
    );

    preload.onHomeInitialLoadSuccess();
    await _flush();
    preload.onHomeInitialLoadSuccess();
    await _flush();
    expect(orders, 1);

    preload.dispose();
  });

  test('early Orders settle (user opened the tab) does not remount Orders',
      () async {
    var orders = 0;
    var dashboard = 0;
    final preload = HomeFirstPreload(
      onMountOrders: () => orders++,
      onMountDashboard: () => dashboard++,
      log: (_) {},
    );

    preload.onOrdersInitialLoadSettled();
    preload.onHomeInitialLoadSuccess();
    await _flush();

    expect(orders, 1);
    expect(dashboard, 1);

    preload.dispose();
  });

  test('dispose while Orders is in-flight does not hang or throw', () async {
    final preload = HomeFirstPreload(
      onMountOrders: () {},
      onMountDashboard: () {},
      log: (_) {},
    );

    preload.onHomeInitialLoadSuccess();
    await _flush();
    preload.dispose();
    await _flush();

    expect(preload.isDisposed, isTrue);
  });
}
