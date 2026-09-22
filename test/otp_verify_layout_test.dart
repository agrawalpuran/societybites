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
}
