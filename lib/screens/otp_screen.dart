import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'society_selection_screen.dart';
import 'main_shell_screen.dart';
import '../services/api_service.dart';
import '../services/auth_config.dart';
import '../services/session_service.dart';
import '../web/web_auth_aside.dart';
import '../web/web_breakpoints.dart';
import '../widgets/otp_verify_heading.dart';

export '../widgets/otp_verify_heading.dart';

/// Splits an SMS/autofill/paste value into OTP boxes. Kept as digits, never an int.
const int kOtpLength = 6;

List<String> splitOtpDigits(String value, {int length = kOtpLength}) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return List<String>.generate(
    length,
    (i) => i < digits.length ? digits[i] : '',
  );
}

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.confirmationResult,
  });

  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final ConfirmationResult? confirmationResult;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const int _otpLength = kOtpLength;
  final List<TextEditingController> _controllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );

  late String _verificationId;
  int? _resendToken;
  ConfirmationResult? _confirmationResult;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _applyingOtp = false;
  Timer? _resendTimer;
  int _resendSecondsRemaining = 60;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _confirmationResult = widget.confirmationResult;
    _startResendCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendSecondsRemaining = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _resendSecondsRemaining = 0);
      } else {
        setState(() => _resendSecondsRemaining--);
      }
    });
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();

    if (_otp.length != _otpLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the 6-digit OTP.')),
      );
      return;
    }

    setState(() => _isVerifying = true);

    try {
      if (AuthConfig.usesTwoFactor) {
        final result = await ApiService.verifyOtp(
          phone: widget.phoneNumber,
          otp: _otp,
        );
        await _persistLogin(result, provider: '2factor');
        return;
      }

      if (kIsWeb && _confirmationResult != null) {
        await _confirmationResult!.confirm(_otp);
        await _completeLogin();
        return;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otp,
      );

      await _auth.signInWithCredential(credential);
      await _completeLogin();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Invalid OTP. Please try again.')),
      );
    } catch (e) {
      if (!mounted) return;

      final message = e.toString().toLowerCase();
      final invalidOtp =
          message.contains('invalid otp') ||
          message.contains('expired') ||
          message.contains('attempt');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            invalidOtp
                ? 'The OTP is incorrect or expired. Please try again.'
                : 'We could not verify the OTP. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Future<void> _completeLogin() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        throw Exception('Firebase user not found after verification');
      }

      final idToken = await firebaseUser.getIdToken();
      if (idToken == null) {
        throw Exception('Could not retrieve Firebase ID token');
      }

      final result = await ApiService.firebaseLogin(idToken);
      await _persistLogin(result, provider: 'firebase');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone verified, but backend login failed: $e')),
      );
    }
  }

  Future<void> _persistLogin(
    Map<String, dynamic> result, {
    required String provider,
  }) async {
    final token = result['token'] as String;
    final refreshToken = result['refreshToken'] as String?;
    final user = Map<String, dynamic>.from(result['user'] as Map);

    await SessionService.saveAuthSession(
      accessToken: token,
      refreshToken: refreshToken,
      provider: provider,
    );
    await SessionService.saveUser(
      userId: user['id'] as String,
      phone: user['phone'] as String,
    );

    final hasFlat = user['flatId'] != null && user['societyId'] != null;

    if (user['societyId'] != null && user['flatId'] != null) {
      final society = user['society'] as Map<String, dynamic>?;
      final flat = user['flat'] as Map<String, dynamic>?;
      await SessionService.saveSociety(
        societyId: user['societyId'] as String,
        societyName: society?['name'] as String? ?? 'Society',
        flatId: user['flatId'] as String,
        flatNumber: flat?['flatNumber'] as String?,
      );
    }

    await SessionService.cacheProfileFromApi(user);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            hasFlat ? const MainShellScreen() : const SocietySelectionScreen(),
      ),
      (_) => false,
    );
  }

  Future<void> _resendOtp() async {
    if (_resendSecondsRemaining > 0) return;
    setState(() => _isResending = true);
    try {
      if (AuthConfig.usesTwoFactor) {
        await ApiService.sendOtp(widget.phoneNumber);
        if (!mounted) return;
        _startResendCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully.')),
        );
        return;
      }

      if (kIsWeb) {
        _confirmationResult = await _auth.signInWithPhoneNumber(
          widget.phoneNumber,
        );
        if (!mounted) return;
        _startResendCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP resent successfully.')),
        );
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Failed to resend OTP.')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _startResendCountdown();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP resent successfully.')),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not resend the OTP. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  void _applyOtpBoxes(List<String> boxes) {
    _applyingOtp = true;
    for (var i = 0; i < _otpLength; i++) {
      if (_controllers[i].text != boxes[i]) {
        _controllers[i].value = TextEditingValue(
          text: boxes[i],
          selection: TextSelection.collapsed(offset: boxes[i].length),
        );
      }
    }
    _applyingOtp = false;
  }

  void _onOtpChanged(int index, String value) {
    if (_applyingOtp) return;

    if (value.length > 1) {
      final boxes = splitOtpDigits(value, length: _otpLength);
      _applyOtpBoxes(boxes);
      final filled = boxes.where((d) => d.isNotEmpty).length;
      if (filled >= _otpLength) {
        _focusNodes[_otpLength - 1].unfocus();
        FocusScope.of(context).unfocus();
        if (!_isVerifying) {
          _verifyOtp();
        }
      } else if (filled > 0) {
        _focusNodes[filled.clamp(0, _otpLength - 1)].requestFocus();
      }
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (_otp.length == _otpLength && !_isVerifying) {
      FocusScope.of(context).unfocus();
      _verifyOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebOtp();
    final size = MediaQuery.of(context).size;
    final horizontalPadding = size.width * 0.08;

    return OtpKeyboardSafeScaffold(
      gradientHeight: size.height * 0.23,
      horizontalPadding: horizontalPadding,
      scrollChild: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BackButton(onTap: () => Navigator.pop(context)),
          const SizedBox(height: 22),
          _SecurityBadge(),
          const SizedBox(height: 18),
          const OtpVerifyHeading(),
          const SizedBox(height: 12),
          Text(
            'Enter the code sent to your mobile.\n'
            'We\'ve sent a 6-digit verification code to\n'
            '${widget.phoneNumber}.',
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF3B4745),
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: _OtpDigitRow(
              controllers: _controllers,
              focusNodes: _focusNodes,
              onChanged: _onOtpChanged,
            ),
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text(
              'Didn\'t receive the code?',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF2F3D3A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: _ResendOtpButton(
              isLoading: _isResending,
              secondsRemaining: _resendSecondsRemaining,
              onTap: _isResending || _resendSecondsRemaining > 0
                  ? null
                  : _resendOtp,
            ),
          ),
          const SizedBox(height: 40),
          const _SecurityInfoCard(),
        ],
      ),
      bottomBar: _PrimaryActionButton(
        isLoading: _isVerifying,
        onTap: _isVerifying ? null : _verifyOtp,
      ),
    );
  }

  Widget _buildWebOtp() {
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: webLine),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140E5A47),
              blurRadius: 28,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: webInk),
                ),
              ),
              const OtpVerifyHeading(),
              const SizedBox(height: 12),
              Text(
                'Enter the 6-digit code sent to ${widget.phoneNumber}.',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Color(0xFF3B4745),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: _OtpDigitRow(
                  controllers: _controllers,
                  focusNodes: _focusNodes,
                  onChanged: _onOtpChanged,
                ),
              ),
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  'Didn\'t receive the code?',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF2F3D3A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _ResendOtpButton(
                  isLoading: _isResending,
                  secondsRemaining: _resendSecondsRemaining,
                  onTap: _isResending || _resendSecondsRemaining > 0
                      ? null
                      : _resendOtp,
                ),
              ),
              const SizedBox(height: 22),
              _PrimaryActionButton(
                isLoading: _isVerifying,
                onTap: _isVerifying ? null : _verifyOtp,
              ),
              const SizedBox(height: 18),
              const _SecurityInfoCard(),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: webPageBackground,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 980) {
            return SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: form,
                ),
              ),
            );
          }
          return Row(
            children: [
              const Expanded(child: WebAuthAside()),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 32,
                    ),
                    child: form,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        color: const Color(0xFF243532),
      ),
    );
  }
}

class _SecurityBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'SECURITY',
        style: TextStyle(
          color: Color(0xFF4E2A20),
          fontSize: 12,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OtpDigitRow extends StatelessWidget {
  const _OtpDigitRow({
    required this.controllers,
    required this.focusNodes,
    required this.onChanged,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final void Function(int index, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < kOtpLength; index++) ...[
            if (index > 0) const SizedBox(width: otpBoxGap),
            _OtpInputBox(
              controller: controllers[index],
              focusNode: focusNodes[index],
              autoFocus: index == 0,
              enableOtpAutofill: index == 0,
              onChanged: (value) => onChanged(index, value),
              isPrimary: index == 0,
            ),
          ],
        ],
      ),
    );
  }
}

class _OtpInputBox extends StatelessWidget {
  const _OtpInputBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.isPrimary,
    this.autoFocus = false,
    this.enableOtpAutofill = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autoFocus;
  final bool enableOtpAutofill;
  final ValueChanged<String> onChanged;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(otpBoxBorderRadius);
    return SizedBox(
      width: otpBoxSize,
      height: otpBoxSize,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autoFocus,
        keyboardType: TextInputType.number,
        textInputAction: enableOtpAutofill
            ? TextInputAction.done
            : TextInputAction.next,
        textAlign: TextAlign.center,
        // Allow the full 6-digit SMS code so OS autofill is not truncated to 1.
        maxLength: kOtpLength,
        autofillHints: enableOtpAutofill
            ? const [AutofillHints.oneTimeCode]
            : null,
        autocorrect: false,
        // iOS shows the SMS OTP chip on the QuickType bar only if suggestions stay on.
        enableSuggestions: enableOtpAutofill,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: const TextStyle(
          fontSize: otpBoxFontSize,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1D2E2B),
          height: 1,
        ),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          filled: true,
          fillColor: Colors.white.withOpacity(0.78),
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(
              color: isPrimary
                  ? const Color(0xFF2D7BFF)
                  : const Color(0xFFE8ECEA),
              width: isPrimary ? 1.4 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: const BorderSide(color: Color(0xFF2D7BFF), width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.onTap,
    required this.isLoading,
  });

  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: otpVerifyButtonHeight,
      child: ElevatedButton(
        key: const Key('otp-verify-continue'),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Verify & continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.15,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
      ),
    );
  }
}

class _ResendOtpButton extends StatelessWidget {
  const _ResendOtpButton({
    required this.onTap,
    required this.isLoading,
    required this.secondsRemaining,
  });

  final VoidCallback? onTap;
  final bool isLoading;
  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, color: Color(0xFF0E5A47)),
      label: Text(
        isLoading
            ? 'Resending...'
            : secondsRemaining > 0
            ? 'Resend OTP in ${secondsRemaining}s'
            : 'Resend OTP',
        style: const TextStyle(
          color: Color(0xFF0E5A47),
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _SecurityInfoCard extends StatelessWidget {
  const _SecurityInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Color(0xFF0E5A47),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Verification',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101617),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your data is safe and secure and never shared. '
                  'We take community safety seriously at SocietyEats.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFF3A4644),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
