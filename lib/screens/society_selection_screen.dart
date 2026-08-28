import 'dart:async';

import 'package:flutter/material.dart';
import 'main_shell_screen.dart';
import '../widgets/app_header.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/society_search.dart';

typedef SocietyListLoader = Future<List<Map<String, dynamic>>> Function();
typedef SocietySearchCall = Future<List<Map<String, dynamic>>> Function(String query);
typedef SocietyPreviewCall = Future<Map<String, dynamic>> Function(String placeId);
typedef SocietyJoinCall =
    Future<Map<String, dynamic>> Function({
      String? societyId,
      String? googlePlaceId,
      required String flatNumber,
      required String block,
      required String firstName,
      String? lastName,
    });

enum _OnboardingStep { search, confirm, details }

class SocietySelectionScreen extends StatefulWidget {
  const SocietySelectionScreen({
    super.key,
    this.loadSocieties,
    this.searchSocieties,
    this.previewPlace,
    this.joinSociety,
  });

  final SocietyListLoader? loadSocieties;
  final SocietySearchCall? searchSocieties;
  final SocietyPreviewCall? previewPlace;
  final SocietyJoinCall? joinSociety;

  @override
  State<SocietySelectionScreen> createState() => _SocietySelectionScreenState();
}

class _SocietySelectionScreenState extends State<SocietySelectionScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _flatController = TextEditingController();
  final TextEditingController _customBlockController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selectedSociety;
  String? _selectedBlock;
  String? _error;
  String _appliedQuery = '';
  bool _isSearching = false;
  bool _isConfirming = false;
  bool _isJoining = false;
  int _searchSeq = 0;
  _OnboardingStep _step = _OnboardingStep.search;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _searchController.dispose();
    _flatController.dispose();
    _customBlockController.dispose();
    _searchFocus.dispose();
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
      _nameController.text.trim().isNotEmpty &&
      _selectedSociety != null &&
      _resolvedBlock.isNotEmpty &&
      _flatController.text.trim().isNotEmpty;

  Future<List<Map<String, dynamic>>> _search(String query) async {
    if (widget.searchSocieties != null) {
      return widget.searchSocieties!(query);
    }
    if (widget.loadSocieties != null) {
      final list = await widget.loadSocieties!();
      return filterSocieties(societies: list, query: query);
    }
    return ApiService.searchSocieties(query);
  }

  String _cleanError(Object e) {
    var message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    if (message.toLowerCase().contains('api key') ||
        message.toLowerCase().contains('google')) {
      return 'Society search is temporarily unavailable.';
    }
    return message;
  }

  bool get _canRetrySearch =>
      _error == 'Could not load societies.' ||
      _error == 'Society search is temporarily unavailable.';

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    final seq = ++_searchSeq;

    if (query.length < 2) {
      setState(() {
        _appliedQuery = query;
        _results = [];
        _isSearching = false;
        if (_canRetrySearch) _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _appliedQuery = query;
      if (_canRetrySearch) _error = null;
    });

    try {
      final list = await _search(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = list;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [];
        _isSearching = false;
        _error = 'Society search is temporarily unavailable.';
      });
    }
  }

  void _selectSociety(Map<String, dynamic> society) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedSociety = society;
      _selectedBlock = null;
      _customBlockController.clear();
      _flatController.clear();
      _error = null;
      _step = _OnboardingStep.confirm;
    });
  }

  Future<void> _confirmSociety() async {
    if (_isConfirming || _selectedSociety == null) return;

    final placeId = _selectedSociety!['placeId']?.toString().trim() ?? '';
    if (placeId.isEmpty) {
      setState(() {
        _error = null;
        _selectedBlock = _blockOptions.length == 1 ? _blockOptions.first : null;
        _step = _OnboardingStep.details;
      });
      return;
    }

    setState(() {
      _isConfirming = true;
      _error = null;
    });

    try {
      final previewer = widget.previewPlace ?? ApiService.previewSocietyPlace;
      final preview = await previewer(placeId);
      if (!mounted) return;

      final place = preview['place'] is Map
          ? Map<String, dynamic>.from(preview['place'] as Map)
          : <String, dynamic>{};
      final society = preview['society'] is Map
          ? Map<String, dynamic>.from(preview['society'] as Map)
          : null;

      setState(() {
        _selectedSociety = {
          ...?_selectedSociety,
          ...place,
          ...?society,
          'placeId': placeId,
        };
        _selectedBlock = null;
        if ((_selectedSociety!['blocks'] is List) &&
            _blockOptions.length == 1) {
          _selectedBlock = _blockOptions.first;
        }
        _isConfirming = false;
        _step = _OnboardingStep.details;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConfirming = false;
        _error = _cleanError(e);
      });
    }
  }

  void _chooseDifferentSociety() {
    setState(() {
      _selectedSociety = null;
      _selectedBlock = null;
      _customBlockController.clear();
      _error = null;
      _isConfirming = false;
      _step = _OnboardingStep.search;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  Future<void> _joinSociety() async {
    if (!_isValid || _isJoining || _selectedSociety == null) return;

    setState(() {
      _error = null;
      _isJoining = true;
    });

    try {
      final societyId = _selectedSociety!['id']?.toString().trim();
      final googlePlaceId = _selectedSociety!['placeId']?.toString().trim();
      final flat = _flatController.text.trim();
      final block = _resolvedBlock;
      final fullName = _nameController.text.trim();

      final join = widget.joinSociety ?? ApiService.joinSociety;
      final response = await join(
        societyId: (societyId != null && societyId.isNotEmpty)
            ? societyId
            : null,
        googlePlaceId: (googlePlaceId != null && googlePlaceId.isNotEmpty)
            ? googlePlaceId
            : null,
        flatNumber: flat,
        block: block,
        firstName: fullName,
      );

      final society = response['society'] as Map<String, dynamic>?;
      final flatData = response['flat'] as Map<String, dynamic>?;

      await SessionService.saveSociety(
        societyId:
            society?['id'] as String? ??
            response['societyId'] as String? ??
            societyId ??
            '',
        societyName:
            society?['name'] as String? ??
            _selectedSociety!['name'] as String? ??
            'Society',
        flatId:
            flatData?['id'] as String? ?? response['flatId'] as String? ?? '',
        flatNumber: flatData?['flatNumber'] as String? ?? flat,
      );
      await SessionService.saveUserName(fullName);
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
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

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
                  height: size.height * 0.18,
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
                    padding: EdgeInsets.fromLTRB(hp, 20, hp, 20 + keyboard),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppHeader(),
                        const SizedBox(height: 20),
                        if (_step == _OnboardingStep.search) ..._buildSearchStep(),
                        if (_step == _OnboardingStep.confirm) ..._buildConfirmStep(),
                        if (_step == _OnboardingStep.details) ..._buildDetailsStep(),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBanner(
                            message: _error!,
                            onRetry: _canRetrySearch
                                ? () => _runSearch(_searchController.text)
                                : null,
                          ),
                        ],
                        if (_step != _OnboardingStep.confirm) ...[
                          const SizedBox(height: 16),
                          const _PrivacyCard(),
                        ],
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

  List<Widget> _buildSearchStep() {
    return [
      const Text(
        'Where do you live?',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFF101617),
          height: 1.1,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Find your society to discover food from\nyour neighbourhood.',
        style: TextStyle(
          fontSize: 15,
          color: Color(0xFF4A5A57),
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 28),
      const _FieldLabel('Your Name'),
      const SizedBox(height: 6),
      _TextFieldBox(
        controller: _nameController,
        hintText: 'e.g. Puran Agrawal',
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 18),
      const _FieldLabel('Search your society'),
      const SizedBox(height: 6),
      _TextFieldBox(
        key: const ValueKey('society-search-field'),
        controller: _searchController,
        focusNode: _searchFocus,
        hintText: 'Search apartment or society...',
        prefixIcon: Icons.search_rounded,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
      ),
      const SizedBox(height: 16),
      if (_isSearching)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Color(0xFF0E5A47),
              ),
            ),
          ),
        )
      else if (_appliedQuery.length < 2)
        const _HintCard(
          icon: Icons.apartment_rounded,
          title: 'Search for your apartment, society or community.',
        )
      else if (_results.isEmpty)
        const _HintCard(
          icon: Icons.search_off_rounded,
          title: 'No societies found.',
          subtitle: 'Try searching with a different name or spelling.',
        )
      else
        ..._results.map(
          (society) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SocietyResultCard(
              society: society,
              onTap: () => _selectSociety(society),
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildConfirmStep() {
    final society = _selectedSociety!;
    final name = society['name']?.toString() ?? 'Society';
    final location = societyLocationLabel(society);

    return [
      const Text(
        'Confirm Your Society',
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFF101617),
          height: 1.1,
        ),
      ),
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE6EBE9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: Color(0xFF0E5A47),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      location.replaceAll(', ', '\n'),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Color(0xFF4A5A57),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Is this your society?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101617),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isConfirming ? null : _confirmSociety,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0E5A47),
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            elevation: 0,
            disabledBackgroundColor: const Color(0xFF0E5A47),
            disabledForegroundColor: Colors.white,
          ),
          child: _isConfirming
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Confirm & Continue',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: TextButton(
          onPressed: _isConfirming ? null : _chooseDifferentSociety,
          child: const Text(
            '← Choose Different Society',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E5A47),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDetailsStep() {
    return [
      Text(
        _selectedSociety?['name']?.toString() ?? 'Your Home Details',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: Color(0xFF101617),
          height: 1.1,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Add your block/tower and flat number.',
        style: TextStyle(
          fontSize: 15,
          color: Color(0xFF4A5A57),
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 24),
      _FieldLabel(_unitLabel),
      const SizedBox(height: 6),
      if (_blockOptions.isNotEmpty)
        _BlockDropdown(
          unitLabel: _unitLabel,
          options: _blockOptions,
          value: _selectedBlock,
          onChanged: (value) => setState(() => _selectedBlock = value),
        )
      else
        _TextFieldBox(
          controller: _customBlockController,
          hintText: _unitLabel == 'Wing' ? 'e.g. East' : 'e.g. C',
          onChanged: (_) => setState(() {}),
        ),
      const SizedBox(height: 18),
      const _FieldLabel('Flat / House No.'),
      const SizedBox(height: 6),
      _TextFieldBox(
        controller: _flatController,
        hintText: 'e.g. 3062',
        keyboardType: TextInputType.text,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isValid && !_isJoining ? _joinSociety : null,
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
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Save & Continue',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: _isJoining ? null : _chooseDifferentSociety,
          child: const Text(
            '← Choose Different Society',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E5A47),
            ),
          ),
        ),
      ),
    ];
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4A5A57),
      ),
    );
  }
}

class _TextFieldBox extends StatelessWidget {
  const _TextFieldBox({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.focusNode,
    this.prefixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.keyboardType,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final IconData? prefixIcon;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;

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
        focusNode: focusNode,
        onChanged: onChanged,
        textCapitalization: textCapitalization,
        textInputAction: textInputAction,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF223531),
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFFBCC4C1),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, color: const Color(0xFF0E5A47)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

class _SocietyResultCard extends StatelessWidget {
  const _SocietyResultCard({required this.society, required this.onTap});

  final Map<String, dynamic> society;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = society['name']?.toString() ?? 'Society';
    final location = societyLocationLabel(society);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6EBE9)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.apartment_rounded,
                color: Color(0xFF0E5A47),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101617),
                      ),
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF0E5A47),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4A5A57),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF0E5A47),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockDropdown extends StatelessWidget {
  const _BlockDropdown({
    required this.unitLabel,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String unitLabel;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          value: value != null && options.contains(value) ? value : null,
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
          items: options
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
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF0E5A47)),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD4D4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFD94F4F), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFD94F4F),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try Again')),
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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_rounded, color: Color(0xFFE07B3C), size: 22),
          SizedBox(width: 14),
          Expanded(
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
                  'Your flat number is only shared with verified vendors within your society circle.',
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
