import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'society_selection_screen.dart';
import 'main_shell_screen.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

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
  static const int _otpLength = 6;
  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(_otpLength, (_) => FocusNode());

  late String _verificationId;
  int? _resendToken;
  ConfirmationResult? _confirmationResult;
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _confirmationResult = widget.confirmationResult;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Something went wrong: $e')),
    );
  } finally {
    if (mounted) {
      setState(() => _isVerifying = false);
    }
  }
}

  Future<void> _completeLogin() async {
    try {
      final user = await ApiService.loginUser(widget.phoneNumber);
      await SessionService.saveUser(
        userId: user['id'] as String,
        phone: widget.phoneNumber,
      );

      final profile = await ApiService.getUser(user['id'] as String);
      final hasFlat = profile['flatId'] != null && profile['societyId'] != null;

      if (profile['societyId'] != null && profile['flatId'] != null) {
        final society = profile['society'] as Map<String, dynamic>?;
        final flat = profile['flat'] as Map<String, dynamic>?;
        await SessionService.saveSociety(
          societyId: profile['societyId'] as String,
          societyName: society?['name'] as String? ??
              SessionService.defaultSocietyName,
          flatId: profile['flatId'] as String,
          flatNumber: flat?['flatNumber'] as String?,
        );
      }

      await SessionService.cacheProfileFromApi(profile);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              hasFlat ? const MainShellScreen() : const SocietySelectionScreen(),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Phone verified, but backend login failed: $e',
          ),
        ),
      );
    }
  }

  Future<void> _resendOtp() async {
    setState(() => _isResending = true);
    try {
      if (kIsWeb) {
        _confirmationResult = await _auth.signInWithPhoneNumber(widget.phoneNumber);
        if (!mounted) return;
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OTP resent successfully.')),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _otpLength && i < digits.length; i++) {
        _controllers[i].text = digits[i];
      }
      if (digits.length >= _otpLength) {
        _focusNodes[_otpLength - 1].requestFocus();
        FocusScope.of(context).unfocus();
        if (!_isVerifying) {
          _verifyOtp();
        }
      } else if (digits.isNotEmpty) {
        _focusNodes[digits.length.clamp(0, _otpLength - 1)].requestFocus();
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
    final size = MediaQuery.of(context).size;
    final horizontalPadding = size.width * 0.08;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: size.height * 0.23,
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
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BackButton(onTap: () => Navigator.pop(context)),
                  const SizedBox(height: 22),
                  _SecurityBadge(),
                  const SizedBox(height: 18),
                  const Text(
                    'Verify your number',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                      height: 1,
                    ),
                  ),
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
                  const SizedBox(height: 42),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      _OtpScreenState._otpLength,
                      (index) => SizedBox(
                        width: (size.width - (horizontalPadding * 2) - (_OtpScreenState._otpLength - 1) * 8) / _OtpScreenState._otpLength,
                        child: _OtpInputBox(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          autoFocus: index == 0,
                          onChanged: (value) => _onOtpChanged(index, value),
                          isPrimary: index == 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  _PrimaryActionButton(
                    text: 'Verify & Continue  →',
                    isLoading: _isVerifying,
                    onTap: _isVerifying ? null : _verifyOtp,
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
                      onTap: _isResending ? null : _resendOtp,
                    ),
                  ),
                  const SizedBox(height: 64),
                  const _SecurityInfoCard(),
                ],
              ),
            ),
          ],
        ),
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

class _OtpInputBox extends StatelessWidget {
  const _OtpInputBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.isPrimary,
    this.autoFocus = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autoFocus;
  final ValueChanged<String> onChanged;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autoFocus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 1,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1D2E2B),
      ),
      decoration: InputDecoration(
        counterText: '',
        filled: true,
        fillColor: Colors.white.withOpacity(0.78),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(
            color: isPrimary ? const Color(0xFF2D7BFF) : const Color(0xFFE8ECEA),
            width: isPrimary ? 1.4 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(
            color: Color(0xFF2D7BFF),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.text,
    required this.onTap,
    required this.isLoading,
  });

  final String text;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
        ),
        child: isLoading
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _ResendOtpButton extends StatelessWidget {
  const _ResendOtpButton({required this.onTap, required this.isLoading});

  final VoidCallback? onTap;
  final bool isLoading;

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
          : const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF0E5A47),
            ),
      label: Text(
        isLoading ? 'Resending...' : 'Resend OTP',
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
                  'Your data is encrypted and never shared. '
                  'We take community safety seriously at SocietyBites.',
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
