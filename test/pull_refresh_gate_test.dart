import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/widgets/pull_refresh_gate.dart';

void main() {
  test('pull refresh dismisses before the reload finishes', () async {
    final gate = PullRefreshGate(
      dismissAfter: const Duration(milliseconds: 30),
    );
    var finished = false;
    final shown = gate.run(() async {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      finished = true;
    });

    await shown;
    expect(finished, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(finished, isTrue);
  });

  test('a second pull does not start another reload', () async {
    final gate = PullRefreshGate(
      dismissAfter: const Duration(milliseconds: 20),
    );
    var calls = 0;
    Future<void> reload() async {
      calls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    await Future.wait([gate.run(reload), gate.run(reload)]);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, 1);
  });
}
