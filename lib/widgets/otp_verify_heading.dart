import 'package:flutter/material.dart';

/// Display size for the OTP heading before FittedBox scaling on narrow screens.
const otpVerifyHeadingFontSize = 38.0;

/// Reduced primary CTA height; still above a 44pt touch target.
const otpVerifyButtonHeight = 48.0;

/// Compact OTP cells on web (centered row). Height 2× legacy 44px; width 75% of height.
const otpBoxHeight = 88.0;
const otpBoxWidth = 66.0;
const otpBoxGap = 16.0;
const otpBoxBorderRadius = 20.0;
const otpBoxFontSize = 36.0;

/// Mobile uses full-width squares; gap between digit cells.
const otpBoxGapMobile = 8.0;

/// Extra space above the iOS keyboard so the SMS OTP autofill chip stays tappable.
const otpIosAutofillBarGap = 52.0;

class OtpVerifyHeading extends StatelessWidget {
  const OtpVerifyHeading({super.key, this.fontSize});

  /// Defaults to [otpVerifyHeadingFontSize]; web OTP uses [otpVerifyHeadingFontSizeWeb].
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final size = fontSize ?? otpVerifyHeadingFontSize;
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'Verify your number',
          maxLines: 1,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF101617),
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// Keeps the verify CTA pinned above the keyboard. iOS autofocuses the OTP
/// boxes, so a single scrolling column hides the button behind the keyboard.
class OtpKeyboardSafeScaffold extends StatelessWidget {
  const OtpKeyboardSafeScaffold({
    super.key,
    required this.gradientHeight,
    required this.horizontalPadding,
    required this.scrollChild,
    required this.bottomBar,
  });

  final double gradientHeight;
  final double horizontalPadding;
  final Widget scrollChild;
  final Widget bottomBar;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final bottomPad = keyboardOpen && isIos ? otpIosAutofillBarGap : 16.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: gradientHeight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0D5745),
                        Color(0x550D5745),
                        Color(0x00F8FAF9),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      20,
                      horizontalPadding,
                      16,
                    ),
                    child: scrollChild,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    8,
                    horizontalPadding,
                    bottomPad,
                  ),
                  child: bottomBar,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
