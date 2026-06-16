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

class _ParsedFlat {
  final String block;
  final String floor;
  final String flat;

  const _ParsedFlat({
    required this.block,
    required this.floor,
    required this.flat,
  });
}

class _SocietySelectionScreenState extends State<SocietySelectionScreen> {
  static const String _societyName = SessionService.defaultSocietyName;
  static const String _societyId = SessionService.defaultSocietyId;
  static const Map<int, String> _blockMap = {
    1: 'A',
    2: 'B',
    3: 'C',
    4: 'D',
    5: 'E',
  };

  final TextEditingController _flatController = TextEditingController();
  _ParsedFlat? _parsed;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _flatController.addListener(_onFlatChanged);
  }

  @override
  void dispose() {
    _flatController.removeListener(_onFlatChanged);
    _flatController.dispose();
    super.dispose();
  }

  void _onFlatChanged() {
    final text = _flatController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsed = null;
        _error = null;
      });
      return;
    }

    if (text.length < 4) {
      setState(() {
        _parsed = null;
        _error = null;
      });
      return;
    }

    if (text.length > 4) {
      setState(() {
        _parsed = null;
        _error = 'Flat number must be exactly 4 digits.';
      });
      return;
    }

    final blockDigit = int.tryParse(text[0]);
    if (blockDigit == null || !_blockMap.containsKey(blockDigit)) {
      setState(() {
        _parsed = null;
        _error = 'Invalid block. First digit must be 1–5.';
      });
      return;
    }

    final floorStr = text.substring(1, 3);
    final flatStr = text[3];

    setState(() {
      _error = null;
      _parsed = _ParsedFlat(
        block: _blockMap[blockDigit]!,
        floor: floorStr,
        flat: flatStr,
      );
    });
  }

  bool get _isValid => _parsed != null && _error == null;

  Future<void> _saveAndContinue() async {
    if (!_isValid || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final flatNumber = _flatController.text.trim();
      final validation = await ApiService.validateFlat(
        societyId: _societyId,
        flatNumber: flatNumber,
      );

      final flat = Map<String, dynamic>.from(validation['flat'] as Map);
      final userId = await SessionService.getUserId();

      if (userId == null) {
        throw Exception('User session expired. Please log in again.');
      }

      await ApiService.updateUserProfile(
        userId,
        societyId: _societyId,
        flatId: flat['id'] as String,
      );

      await SessionService.saveSociety(
        societyId: _societyId,
        societyName: _societyName,
        flatId: flat['id'] as String,
        flatNumber: flat['flatNumber'] as String? ?? flatNumber,
      );

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainShellScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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
                        const _StepBadge(),
                        const SizedBox(height: 16),
                        const Text(
                          'Find your community',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101617),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Join the vibrant network of residents and local\n'
                          'artisans in your immediate neighborhood.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF4A5A57),
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _FlatNumberInput(
                          controller: _flatController,
                          error: _error,
                        ),
                        const SizedBox(height: 16),
                        if (_parsed != null) _DetectedInfo(parsed: _parsed!),
                        if (_parsed != null) const SizedBox(height: 24),
                        if (_parsed != null)
                          _DeliveryAddressCard(
                            society: _societyName,
                            parsed: _parsed!,
                            flatNumber: _flatController.text.trim(),
                          ),
                        if (_parsed != null) const SizedBox(height: 20),
                        const _PrivacyCard(),
                        const SizedBox(height: 28),
                        _EnterButton(
                          isValid: _isValid,
                          isLoading: _isSaving,
                          onTap: _isValid && !_isSaving ? _saveAndContinue : null,
                        ),
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'By entering, you agree to our Community Guidelines.',
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

class _StepBadge extends StatelessWidget {
  const _StepBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE5D6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'STEP 01: IDENTIFICATION',
        style: TextStyle(
          color: Color(0xFF4E2A20),
          fontSize: 11,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FlatNumberInput extends StatelessWidget {
  const _FlatNumberInput({required this.controller, this.error});

  final TextEditingController controller;
  final String? error;

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
                  Icons.search_rounded,
                  color: Color(0xFF0E5A47),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter Flat Number',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101617),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Your 4-digit flat code (e.g. 3062)',
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
          const SizedBox(height: 16),
          Container(
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: error != null
                    ? const Color(0xFFD94F4F)
                    : const Color(0xFFE6EBE9),
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              style: const TextStyle(
                fontSize: 22,
                color: Color(0xFF223531),
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
              decoration: const InputDecoration(
                hintText: 'e.g. 3062',
                hintStyle: TextStyle(
                  color: Color(0xFFBCC4C1),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                counterText: '',
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(
                color: Color(0xFFD94F4F),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetectedInfo extends StatelessWidget {
  const _DetectedInfo({required this.parsed});
  final _ParsedFlat parsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4E8DF)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF0E5A47),
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            'Block ${parsed.block}  •  Floor ${parsed.floor}  •  Flat ${parsed.flat}',
            style: const TextStyle(
              color: Color(0xFF0E5A47),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({
    required this.society,
    required this.parsed,
    required this.flatNumber,
  });

  final String society;
  final _ParsedFlat parsed;
  final String flatNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E5A47), Color(0xFF14755E)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                'DELIVERY ADDRESS',
                style: TextStyle(
                  color: Colors.white.withAlpha(180),
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Block ${parsed.block}, Flat $flatNumber',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Floor ${parsed.floor}, $society',
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.verified_rounded, color: Color(0xFF7AECC2), size: 18),
              const SizedBox(width: 6),
              Text(
                'Society verified for fresh delivery',
                style: TextStyle(
                  color: Colors.white.withAlpha(210),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
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

class _EnterButton extends StatelessWidget {
  const _EnterButton({
    required this.isValid,
    required this.isLoading,
    required this.onTap,
  });

  final bool isValid;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isValid
              ? const Color(0xFF0E5A47)
              : const Color(0xFFB5C4BF),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          elevation: 0,
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
                'Enter Marketplace  →',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
