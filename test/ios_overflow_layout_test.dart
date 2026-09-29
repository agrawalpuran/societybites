import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/order_lifecycle.dart';
import 'package:societybites/widgets/order_status_tracker.dart';

List<String> _collectOverflows() {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = '${details.exception}\n${details.summary}';
    if (text.contains('A RenderFlex overflowed')) {
      overflows.add(text.split('\n').first);
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  return overflows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login trust chips wrap instead of overflowing when keyboard is up',
      (tester) async {
    final overflows = _collectOverflows();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const TextField(
                          autofocus: true,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: const [
                            Expanded(
                              child: _TrustChip(label: 'ENCRYPTED'),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _TrustChip(label: 'SOCIETY\nONLY'),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _TrustChip(label: 'REGULATED'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  testWidgets('narrow specials card wraps seller name instead of overflowing right',
      (tester) async {
    final overflows = _collectOverflows();
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 190,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        "By Priya's Homemade Kitchen",
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        ' • Flat 1204, Block C, Tower 3',
                        softWrap: true,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining("Priya's Homemade Kitchen"), findsOneWidget);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  testWidgets('order status steps wrap on a narrow iPhone width', (tester) async {
    final overflows = _collectOverflows();
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(18),
              child: const OrderStatusTracker(
                currentStep: 0,
                steps: BuyerOrderLifecycle.progressSteps,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ready for\nPickup'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.getSize(find.text('Confirmed')).height, lessThan(20));
    expect(tester.getSize(find.text('Completed')).height, lessThan(20));
    expect(tester.getSize(find.text('Order\nPlaced')).height, greaterThan(20));
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F3),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_moon_rounded, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.2,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
