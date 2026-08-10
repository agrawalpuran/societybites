import 'package:flutter/material.dart';
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
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _flatController = TextEditingController();
  final TextEditingController _customBlockController = TextEditingController();

  List<Map<String, dynamic>> _societies = [];
  Map<String, dynamic>? _selectedSociety;
  String? _selectedBlock;
  String? _error;
  bool _isLoading = true;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    _loadSocieties();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _flatController.dispose();
    _customBlockController.dispose();
    super.dispose();
  }

  List<String> get _blockOptions {
    final blocks = _selectedSociety?['blocks'];
    if (blocks is! List) return const [];
    return blocks
        .map((b) => (b is Map ? b['name'] : null)?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  String get _unitLabel {
    final label = _selectedSociety?['unitLabel']?.toString().trim();
    if (label == null || label.isEmpty) return 'Block';
    return label;
  }

  String get _resolvedBlock {
    if (_blockOptions.isNotEmpty) {
      return (_selectedBlock ?? '').trim();
    }
    return _customBlockController.text.trim();
  }

  bool get _isValid =>
      _firstNameController.text.trim().isNotEmpty &&
      _selectedSociety != null &&
      _resolvedBlock.isNotEmpty &&
      _flatController.text.trim().isNotEmpty;

  Future<void> _loadSocieties() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getSocieties();
      if (!mounted) return;
      setState(() {
        _societies = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _cleanError(e);
      });
    }
  }

  String _cleanError(Object e) {
    var message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    return message;
  }

  void _onSocietyChanged(Map<String, dynamic>? society) {
    setState(() {
      _selectedSociety = society;
      _selectedBlock = null;
      _customBlockController.clear();
      final options = _blockOptions;
      if (options.isNotEmpty) {
        _selectedBlock = options.first;
      }
    });
  }

  Future<void> _joinSociety() async {
    if (!_isValid || _isJoining || _selectedSociety == null) return;

    setState(() {
      _error = null;
      _isJoining = true;
    });

    try {
      final societyId = _selectedSociety!['id'] as String;
      final flat = _flatController.text.trim();
      final block = _resolvedBlock;
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();

      final response = await ApiService.joinSociety(
        societyId: societyId,
        flatNumber: flat,
        block: block,
        firstName: firstName,
        lastName: lastName.isEmpty ? null : lastName,
      );

      final society = response['society'] as Map<String, dynamic>?;
      final flatData = response['flat'] as Map<String, dynamic>?;

      await SessionService.saveSociety(
        societyId: society?['id'] as String? ??
            response['societyId'] as String? ??
            societyId,
        societyName: society?['name'] as String? ??
            _selectedSociety!['name'] as String? ??
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
      setState(() => _error = _cleanError(e));
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
                          'Enter your name, select your community, then\n'
                          'add your block/wing and flat number.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF4A5A57),
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF0E5A47),
                              ),
                            ),
                          )
                        else
                          _InputCard(
                            firstNameController: _firstNameController,
                            lastNameController: _lastNameController,
                            societies: _societies,
                            selectedSociety: _selectedSociety,
                            onSocietyChanged: _onSocietyChanged,
                            blockOptions: _blockOptions,
                            selectedBlock: _selectedBlock,
                            onBlockChanged: (value) {
                              setState(() => _selectedBlock = value);
                            },
                            customBlockController: _customBlockController,
                            flatController: _flatController,
                            unitLabel: _unitLabel,
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
                                if (!_isLoading)
                                  TextButton(
                                    onPressed: _loadSocieties,
                                    child: const Text('Retry'),
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
    required this.firstNameController,
    required this.lastNameController,
    required this.societies,
    required this.selectedSociety,
    required this.onSocietyChanged,
    required this.blockOptions,
    required this.selectedBlock,
    required this.onBlockChanged,
    required this.customBlockController,
    required this.flatController,
    required this.unitLabel,
    required this.onChanged,
  });

  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final List<Map<String, dynamic>> societies;
  final Map<String, dynamic>? selectedSociety;
  final ValueChanged<Map<String, dynamic>?> onSocietyChanged;
  final List<String> blockOptions;
  final String? selectedBlock;
  final ValueChanged<String?> onBlockChanged;
  final TextEditingController customBlockController;
  final TextEditingController flatController;
  final String unitLabel;
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
                  Icons.apartment_rounded,
                  color: Color(0xFF0E5A47),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101617),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Name and your society location',
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
            'First Name *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5A57),
            ),
          ),
          const SizedBox(height: 6),
          _TextFieldBox(
            controller: firstNameController,
            hintText: 'e.g. Anita',
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 18),
          const Text(
            'Last Name (optional)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5A57),
            ),
          ),
          const SizedBox(height: 6),
          _TextFieldBox(
            controller: lastNameController,
            hintText: 'e.g. Sharma',
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 18),
          const Text(
            'Society',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A5A57),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6EBE9)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedSociety?['id'] as String?,
                hint: const Text(
                  'Select your society',
                  style: TextStyle(
                    color: Color(0xFFBCC4C1),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF0E5A47),
                ),
                items: societies.map((s) {
                  final id = s['id'] as String;
                  final name = s['name']?.toString() ?? 'Society';
                  final city = s['city']?.toString();
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(
                      city == null || city.isEmpty ? name : '$name · $city',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF223531),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (id) {
                  if (id == null) {
                    onSocietyChanged(null);
                    return;
                  }
                  Map<String, dynamic>? match;
                  for (final s in societies) {
                    if (s['id'] == id) {
                      match = s;
                      break;
                    }
                  }
                  onSocietyChanged(match);
                },
              ),
            ),
          ),
          if (selectedSociety != null) ...[
            const SizedBox(height: 18),
            Text(
              unitLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5A57),
              ),
            ),
            const SizedBox(height: 6),
            if (blockOptions.isNotEmpty)
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE6EBE9)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedBlock != null &&
                            blockOptions.contains(selectedBlock)
                        ? selectedBlock
                        : null,
                    hint: Text(
                      'Select $unitLabel',
                      style: const TextStyle(
                        color: Color(0xFFBCC4C1),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF0E5A47),
                    ),
                    items: blockOptions
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b,
                            child: Text(
                              '$unitLabel $b',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF223531),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onBlockChanged,
                  ),
                ),
              )
            else
              _TextFieldBox(
                controller: customBlockController,
                hintText: unitLabel == 'Wing' ? 'e.g. East' : 'e.g. C',
                onChanged: (_) => onChanged(),
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
            _TextFieldBox(
              controller: flatController,
              hintText: 'e.g. 3062',
              onChanged: (_) => onChanged(),
            ),
          ],
        ],
      ),
    );
  }
}

class _TextFieldBox extends StatelessWidget {
  const _TextFieldBox({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textCapitalization: textCapitalization,
        style: const TextStyle(
          fontSize: 18,
          color: Color(0xFF223531),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFFBCC4C1),
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 14,
          ),
        ),
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
