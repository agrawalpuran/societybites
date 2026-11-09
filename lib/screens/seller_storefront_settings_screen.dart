import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import '../widgets/photo_source_sheet.dart';

const _defaultAccent = '#0E5A47';

/// Curated accents for kitchen branding (hex without relying on sellers typing codes).
const _accentPalette = <({String label, String hex})>[
  (label: 'SocietyEats green', hex: '#0E5A47'),
  (label: 'Deep teal', hex: '#0A6E5C'),
  (label: 'Forest', hex: '#2D6A4F'),
  (label: 'Terracotta', hex: '#8B4513'),
  (label: 'Maroon', hex: '#7B2D3B'),
  (label: 'Plum', hex: '#5C3D6E'),
  (label: 'Navy', hex: '#1E3A5F'),
  (label: 'Royal blue', hex: '#2B4C8C'),
  (label: 'Slate', hex: '#3D4F5F'),
  (label: 'Amber', hex: '#B8860B'),
  (label: 'Saffron', hex: '#C45C00'),
  (label: 'Charcoal', hex: '#3A3A3A'),
];

/// Seller-facing editor for kitchen page branding (tagline, colors, banner).
class SellerStorefrontSettingsScreen extends StatefulWidget {
  const SellerStorefrontSettingsScreen({super.key});

  @override
  State<SellerStorefrontSettingsScreen> createState() =>
      _SellerStorefrontSettingsScreenState();
}

class _SellerStorefrontSettingsScreenState
    extends State<SellerStorefrontSettingsScreen> {
  final _taglineController = TextEditingController();
  final _accentController = TextEditingController();
  final _bannerController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingBanner = false;
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    _bannerController.addListener(_onBannerFieldChanged);
  }

  void _onBannerFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _taglineController.dispose();
    _accentController.dispose();
    _bannerController
      ..removeListener(_onBannerFieldChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final profile = await ApiService.getMe();
      if (!mounted) return;
      _applyProfile(profile);
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  void _applyProfile(Map<String, dynamic> profile) {
    final tagline = profile['storefrontTagline']?.toString() ?? '';
    final accent = profile['storefrontAccentColor']?.toString().trim() ?? '';
    final banner = profile['storefrontBannerUrl']?.toString() ?? '';
    _taglineController.text = tagline;
    _accentController.text = accent.isNotEmpty ? accent : _defaultAccent;
    _bannerController.text = banner;
    _profilePhotoUrl = profile['profilePhotoUrl']?.toString();
    _alignAccentToPalette();
  }

  void _alignAccentToPalette() {
    final current = _normalizedAccentHex(_accentController.text);
  final match = _accentPalette.any((o) => o.hex.toUpperCase() == current);
    if (!match) {
      _accentController.text = current.isEmpty ? _defaultAccent : _defaultAccent;
    }
  }

  void _selectAccent(String hex) {
    setState(() {
      _accentController.text = hex.toUpperCase();
    });
  }

  String _normalizedAccentHex(String raw) {
    final parsed = _parseHex(raw);
    if (parsed == null) return '';
    final rgb = parsed.value & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color? _parseHex(String raw) {
    final text = raw.trim();
    final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(text);
    if (match == null) return null;
    final value = int.parse(match.group(1)!, radix: 16);
    return Color(0xFF000000 | value);
  }

  void _removeBanner() {
    setState(() => _bannerController.clear());
    _showMessage(
      'Banner cleared. Tap Save to show food photos on your kitchen page.',
    );
  }

  Future<void> _pickBanner() async {
    if (_uploadingBanner) return;
    final source = await showPhotoSourceSheet(context, title: 'Banner image');
    if (source == null || !mounted) return;
  try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 88,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      setState(() => _uploadingBanner = true);
      final url = await ApiService.uploadListingImage(bytes: bytes);
      if (!mounted) return;
      setState(() {
        _bannerController.text = url;
        _uploadingBanner = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingBanner = false);
      _showError(error);
    }
  }

  Future<void> _save() async {
    final accent = _normalizedAccentHex(_accentController.text);
    if (_parseHex(_accentController.text) == null) {
      _showMessage('Pick an accent color from the palette');
      return;
    }

    setState(() => _saving = true);
    try {
      final tagline = _taglineController.text.trim();
      final banner = _bannerController.text.trim();
      final updated = await ApiService.updateMyProfile(
        storefrontAccentColor:
            accent == _defaultAccent ? null : accent,
        clearStorefrontAccentColor: accent == _defaultAccent,
        storefrontBannerUrl: banner.isEmpty ? null : banner,
        clearStorefrontBannerUrl: banner.isEmpty,
        storefrontTagline: tagline.isEmpty ? null : tagline,
        clearStorefrontTagline: tagline.isEmpty,
      );
      await SessionService.cacheProfileFromApi(updated);
      if (!mounted) return;
      _applyProfile(updated);
      setState(() => _saving = false);
      _showMessage('Kitchen website updated');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(error);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(Object error) {
    _showMessage(ApiService.userFacingError(error));
  }

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        body: SafeArea(
          child: Column(
            children: [
              const AppHeader(
                showCart: false,
                leading: BackButton(color: Color(0xFF101617)),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: [
                          const Text(
                            'Kitchen website',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101617),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tagline, accent color, and banner for your kitchen page. '
                            'Does not change the main SocietyEats marketplace.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6A7774),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const _FieldLabel('Tagline'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _taglineController,
                            maxLength: 120,
                            decoration: InputDecoration(
                              hintText: 'e.g. Agrawal\'s Kitchen',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const _FieldLabel('Accent color'),
                          const SizedBox(height: 4),
                          const Text(
                            'Buttons and headings on your kitchen page.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6A7774),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _AccentColorPalette(
                            options: _accentPalette,
                            selectedHex:
                                _normalizedAccentHex(_accentController.text),
                            onSelected: _selectAccent,
                          ),
                          const SizedBox(height: 20),
                          const _FieldLabel('Hero banner (wide image)'),
                          const SizedBox(height: 4),
                          const Text(
                            'Optional cover photo on your kitchen page. Logo uses '
                            'Profile photo.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6A7774),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_bannerController.text.trim().isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 2.4,
                                child: Image.network(
                                  _bannerController.text.trim(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const ColoredBox(
                                    color: Color(0xFFE3E8E4),
                                    child: Center(
                                      child: Icon(Icons.broken_image_outlined),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          TextField(
                            controller: _bannerController,
                            readOnly: true,
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: 'No banner — food photos show in hero',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixIcon: _bannerController.text
                                      .trim()
                                      .isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Remove banner',
                                      onPressed: _removeBanner,
                                      icon: const Icon(Icons.close_rounded),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed:
                                      _uploadingBanner ? null : _pickBanner,
                                  icon: _uploadingBanner
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.upload_rounded),
                                  label: const Text('Upload banner'),
                                ),
                              ),
                              if (_bannerController.text.trim().isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _removeBanner,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFB44D3A),
                                    ),
                                    label: const Text(
                                      'Remove',
                                      style: TextStyle(
                                        color: Color(0xFFB44D3A),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Color(0xFFE8C9C3),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_profilePhotoUrl != null &&
                              _profilePhotoUrl!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const _FieldLabel('Kitchen logo'),
                            const SizedBox(height: 6),
                            const Text(
                              'Change under Profile → photo (shown in header).',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving || _loading ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E5A47),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      maxWidth: 720,
    );
  }
}

class _AccentColorPalette extends StatelessWidget {
  const _AccentColorPalette({
    required this.options,
    required this.selectedHex,
    required this.onSelected,
  });

  final List<({String label, String hex})> options;
  final String selectedHex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in options)
          _AccentSwatch(
            label: option.label,
            hex: option.hex,
            selected: selectedHex == option.hex.toUpperCase(),
            onTap: () => onSelected(option.hex),
          ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.label,
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 108,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF0E5A47) : const Color(0xFFE3E8E4),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE3E8E4)),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: const Color(0xFF101617),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
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
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: Color(0xFF3E514B),
      ),
    );
  }
}
