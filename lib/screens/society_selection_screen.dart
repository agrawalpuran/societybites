import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main_shell_screen.dart';
import '../widgets/app_header.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class SocietySelectionScreen extends StatefulWidget {
  const SocietySelectionScreen({super.key});

  @override
  State<SocietySelectionScreen> createState() => _SocietySelectionScreenState();
}

class _SocietySelectionScreenState extends State<SocietySelectionScreen> {
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _flatController = TextEditingController();
  String? _error;
  bool _isJoining = false;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _flatController.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _inviteCodeController.text.trim().isNotEmpty &&
      _flatController.text.trim().isNotEmpty;

  Future<void> _joinSociety() async {
    if (!_isValid || _isJoining) return;

    setState(() {
      _error = null;
      _isJoining = true;
    });

    try {
      final code = _inviteCodeController.text.trim();
      final flat = _flatController.text.trim();

      final response = await ApiService.joinSociety(
        inviteCode: code,
        flatNumber: flat,
      );

      final society = response['society'] as Map<String, dynamic>?;
      final flatData = response['flat'] as Map<String, dynamic>?;

      await SessionService.saveSociety(
        societyId: society?['id'] as String? ??
            response['societyId'] as String? ??
            SessionService.defaultSocietyId,
        societyName: society?['name'] as String? ??
            SessionService.defaultSocietyName,
        flatId: flatData?['id'] as String? ??
            response['flatId'] as String? ??
            '',
        flatNumber: flatData?['flatNumber'] as String? ?? flat,
      );

      await SessionService.cacheProfileFromApi(response);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }
      setState(() => _error = message);
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hp = size.width * 0.07;

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
                  height: size.height * 0.22,
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
                    padding: EdgeInsets.symmetric(horizontal: hp, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        const AppHeader(),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE5D6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'ONBOARDING',
                            style: TextStyle(
                              color: Color(0xFF4E2A20),
                              fontSize: 11,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Join Your Society',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101617),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Enter the invite code shared by your\n'
                          'apartment community',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF4A5A57),
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _InputCard(
                          inviteCodeController: _inviteCodeController,
                          flatController: _flatController,
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        if (_error != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFFD4D4),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFD94F4F),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Color(0xFFD94F4F),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        const _PrivacyCard(),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 62,
                          child: ElevatedButton(
                            onPressed: _isValid && !_isJoining
                                ? _joinSociety
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isValid
                                  ? const Color(0xFF0E5A47)
                                  : const Color(0xFFB5C4BF),
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              elevation: 0,
                              disabledBackgroundColor: const Color(0xFFB5C4BF),
                              disabledForegroundColor: Colors.white,
                            ),
                            child: _isJoining
                                ? const SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Join Society  →',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'By joining, you agree to our Community Guidelines.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8A9491),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.inviteCodeController,
    required this.flatController,
    required this.onChanged,
  });

  final TextEditingController inviteCodeController;
  final TextEditingController flatController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFF0E5A47),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Society Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101617),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Ask your community admin for the code',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7A8885),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Invite Code',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5A57),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6EBE9)),
            ),
            child: TextField(
              controller: inviteCodeController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              onChanged: (_) => onChanged(),
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF223531),
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              decoration: const InputDecoration(
                hintText: 'e.g. PRESTIGE2026',
                hintStyle: TextStyle(
                  color: Color(0xFFBCC4C1),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Flat Number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5A57),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6EBE9)),
            ),
            child: TextField(
              controller: flatController,
              onChanged: (_) => onChanged(),
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF223531),
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              decoration: const InputDecoration(
                hintText: 'e.g. 3062',
                hintStyle: TextStyle(
                  color: Color(0xFFBCC4C1),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5EE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFE0CC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Color(0xFFE07B3C),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy First',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3A2115),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Your flat number is only shared with verified vendors\n'
                  'within your society circle.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF7A5A42),
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
