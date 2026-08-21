import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'otp_screen.dart';
import '../services/api_service.dart';
import '../services/auth_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSendingOtp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _phoneFocusNode.requestFocus();
      }
    });
  }

  String _normalizeIndianNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('91') && digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    if (digits.length > 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();

    final number = _normalizeIndianNumber(_phoneController.text);
    if (number.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit number.')),
      );
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      if (AuthConfig.usesTwoFactor) {
        await ApiService.sendOtp('+91$number');
        if (!mounted) return;
        setState(() => _isSendingOtp = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                OtpScreen(phoneNumber: '+91$number', verificationId: ''),
          ),
        );
        return;
      }

      if (kIsWeb) {
        final confirmationResult = await _auth.signInWithPhoneNumber(
          '+91$number',
        );
        if (!mounted) return;
        setState(() => _isSendingOtp = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              phoneNumber: '+91$number',
              verificationId: '',
              confirmationResult: confirmationResult,
            ),
          ),
        );
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: '+91$number',
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Phone number verified successfully.'),
              ),
            );
          } on FirebaseAuthException catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.message ?? 'Auto verification failed.')),
            );
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isSendingOtp = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Verification failed.')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() => _isSendingOtp = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                phoneNumber: '+91$number',
                verificationId: verificationId,
                resendToken: resendToken,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (_) {
          if (!mounted) return;
          setState(() => _isSendingOtp = false);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not send the OTP. Check your connection and try again.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    final horizontalPadding = size.width * 0.07;
    final sectionGap = size.height * 0.035;

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
                  height: size.height * 0.24,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF0D5745),
                        Color(0x660D5745),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: size.height * 0.03),
                        _HeaderSection(theme: theme),
                        SizedBox(height: sectionGap),
                        _InputSection(
                          controller: _phoneController,
                          focusNode: _phoneFocusNode,
                        ),
                        SizedBox(height: sectionGap),
                        _SendOtpButton(
                          isLoading: _isSendingOtp,
                          onTap: _isSendingOtp ? null : _sendOtp,
                        ),
                        SizedBox(height: sectionGap),
                        const _TrustIndicatorsRow(),
                      ],
                    ),
                  ),
                ),
                const _FooterLinks(),
                const SizedBox(height: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFF0E5A47),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0E5A47).withOpacity(0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'SocietyBites',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0A4638),
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Welcome back',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: const Color(0xFF101617),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Safe, secure, and exclusive to your\napartment community.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF4A5A57),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MOBILE NUMBER',
          style: TextStyle(
            color: Color(0xFF8A4B3B),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF2F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '+91',
                  style: TextStyle(
                    color: Color(0xFF283734),
                    fontWeight: FontWeight.w600,
                    fontSize: 21,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 10,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF2F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(
                    fontSize: 24,
                    color: Color(0xFF223531),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                  decoration: const InputDecoration(
                    hintText: '99999 00000',
                    hintStyle: TextStyle(
                      color: Color(0xFFBCC4C1),
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    counterText: '',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SendOtpButton extends StatelessWidget {
  const _SendOtpButton({required this.onTap, required this.isLoading});

  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ElevatedButton(
        onPressed: onTap,
        style:
            ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              elevation: 0,
              shadowColor: Colors.transparent,
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                Colors.white.withOpacity(0.07),
              ),
            ),
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0E5A47).withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
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
              : const Text(
                  'Send OTP  →',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _TrustIndicatorsRow extends StatelessWidget {
  const _TrustIndicatorsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        Expanded(
          child: _TrustItem(
            icon: Icons.shield_moon_rounded,
            label: 'ENCRYPTED',
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _TrustItem(icon: Icons.groups_rounded, label: 'SOCIETY\nONLY'),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _TrustItem(
            icon: Icons.verified_user_rounded,
            label: 'REGULATED',
          ),
        ),
      ],
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F3),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _IconBadge(icon: icon),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.1,
              color: Color(0xFF243532),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _HexagonClipper(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFE6F0ED),
          border: Border.all(color: const Color(0xFFD4E5E0), width: 1),
        ),
        child: Icon(icon, color: const Color(0xFF0E5A47), size: 18),
      ),
    );
  }
}

class _HexagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.5, 0);
    path.lineTo(w, h * 0.25);
    path.lineTo(w, h * 0.75);
    path.lineTo(w * 0.5, h);
    path.lineTo(0, h * 0.75);
    path.lineTo(0, h * 0.25);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _FooterLinkText(text: 'Terms of Service'),
              SizedBox(width: 22),
              _FooterLinkText(text: 'Privacy Policy'),
              SizedBox(width: 22),
              _FooterLinkText(text: 'Help Center'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '© 2024 SOCIETYBITES. ALL RIGHTS RESERVED.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFA4AEAB),
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLinkText extends StatelessWidget {
  const _FooterLinkText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF5E6A67),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
