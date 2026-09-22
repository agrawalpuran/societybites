import 'package:flutter/material.dart';

/// Display size for the OTP heading before FittedBox scaling on narrow screens.
const otpVerifyHeadingFontSize = 38.0;

/// Reduced primary CTA height; still above a 44pt touch target.
const otpVerifyButtonHeight = 46.0;

class OtpVerifyHeading extends StatelessWidget {
  const OtpVerifyHeading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'Verify your number',
          maxLines: 1,
          style: TextStyle(
            fontSize: otpVerifyHeadingFontSize,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
