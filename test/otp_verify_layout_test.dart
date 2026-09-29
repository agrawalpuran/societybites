import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/widgets/otp_verify_heading.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHeading(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: width * 0.08),
            child: const OtpVerifyHeading(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('OTP heading stays one line on a narrow Android width', (
    tester,
  ) async {
    await pumpHeading(tester, 320);
    expect(find.text('Verify your number'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Verify your number'));
    expect(text.maxLines, 1);
    expect(otpVerifyHeadingFontSize, closeTo(38, 0.01));
    expect(otpVerifyHeadingFontSize, lessThan(52 * 0.8));
    expect(otpVerifyHeadingFontSize, greaterThan(52 * 0.65));
    expect(otpVerifyButtonHeight, 46);
    expect(otpVerifyButtonHeight, lessThan(64 * 0.8));
    expect(otpVerifyButtonHeight, greaterThanOrEqualTo(44));
  });

  testWidgets('OTP heading stays one line on a normal phone width', (
    tester,
  ) async {
    await pumpHeading(tester, 390);
    expect(find.text('Verify your number'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Verify your number'));
    expect(text.data, 'Verify your number');
    expect(text.maxLines, 1);
  });

  testWidgets('verify CTA stays above an iOS keyboard inset', (tester) async {
    const logical = Size(390, 844);
    tester.view.physicalSize = logical;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: OtpKeyboardSafeScaffold(
          gradientHeight: 180,
          horizontalPadding: 24,
          scrollChild: const SizedBox(height: 900, child: Text('otp fields')),
          bottomBar: SizedBox(
            key: const Key('otp-verify-continue'),
            height: otpVerifyButtonHeight,
            width: double.infinity,
            child: const ColoredBox(color: Color(0xFF0E5A47)),
          ),
        ),
      ),
    );
    await tester.pump();

    final button = tester.getRect(find.byKey(const Key('otp-verify-continue')));
    expect(button.bottom, lessThanOrEqualTo(logical.height - 336 + 1));
    expect(button.top, greaterThan(0));
    expect(find.text('otp fields'), findsOneWidget);
  });

  testWidgets('iOS keyboard leaves a gap for SMS OTP autofill', (tester) async {
    const logical = Size(390, 844);
    tester.view.physicalSize = logical;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: OtpKeyboardSafeScaffold(
          gradientHeight: 180,
          horizontalPadding: 24,
          scrollChild: const SizedBox(height: 900, child: Text('otp fields')),
          bottomBar: SizedBox(
            key: const Key('otp-verify-continue'),
            height: otpVerifyButtonHeight,
            width: double.infinity,
            child: const ColoredBox(color: Color(0xFF0E5A47)),
          ),
        ),
      ),
    );
    await tester.pump();

    final button = tester.getRect(find.byKey(const Key('otp-verify-continue')));
    expect(
      button.bottom,
      lessThanOrEqualTo(logical.height - 336 - otpIosAutofillBarGap + 2),
    );
    expect(button.top, greaterThan(0));
  });
}
