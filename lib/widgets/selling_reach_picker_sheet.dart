import 'package:flutter/material.dart';

import '../models/selling_reach.dart';
import '../services/api_service.dart';
import 'selling_reach_radius_slider.dart';

/// Mode A: My society only, or beyond society with 1–max km slider.
class SellingReachPickerSheet extends StatefulWidget {
  const SellingReachPickerSheet({
    super.key,
    required this.reach,
    required this.initial,
  });

  final SellingReach reach;
  final SellerReachPreference initial;

  static Future<SellerReachPreference?> show(
    BuildContext context, {
    required SellingReach reach,
    required SellerReachPreference initial,
  }) {
    return showModalBottomSheet<SellerReachPreference>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SellingReachPickerSheet(reach: reach, initial: initial),
    );
  }

  @override
  State<SellingReachPickerSheet> createState() => _SellingReachPickerSheetState();
}

class _SellingReachPickerSheetState extends State<SellingReachPickerSheet> {
  static const _green = Color(0xFF0E5A47);

  late bool _mySocietyOnly;
  late int _radiusKm;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mySocietyOnly = widget.initial.mySocietyOnly;
    _radiusKm = widget.initial.radiusKm;
  }

  SellerReachPreference _draft() {
    return SellerReachPreference(
      mySocietyOnly: _mySocietyOnly,
      radiusKm: _radiusKm,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final pref = _draft();
    final level = pref.mySocietyOnly
        ? SellingReachLevel.mySociety.apiValue
        : SellingReachLevel.beyondSociety.apiValue;

    setState(() => _saving = true);
    try {
      final preview = await ApiService.previewSellingReachChange(
        sellingReachLevel: level,
        sellingReachRadiusKm: pref.mySocietyOnly ? null : pref.radiusKm,
      );
      if (!mounted) return;

      if (preview['allowed'] != true) {
        final message = preview['message']?.toString() ??
            'You cannot reduce reach while those orders are open.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      if (preview['requiresConfirmation'] == true) {
        final body = preview['confirmationMessage']?.toString() ??
            'This only affects new buyers. Your current orders stay unchanged.';
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reduce selling reach?'),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }

      Navigator.pop(context, pref);
    } catch (e) {
      if (!mounted) return;
      var message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final beyondAvailable = widget.reach.beyondSocietyAvailable;
    final sheet = Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Selling reach',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Who can discover and order from you?',
            style: TextStyle(fontSize: 14, color: Color(0xFF6A7774)),
          ),
          const SizedBox(height: 18),
          _option(
            selected: _mySocietyOnly,
            title: 'My society',
            subtitle: 'Only residents of your society',
            onTap: () => setState(() => _mySocietyOnly = true),
          ),
          const SizedBox(height: 10),
          _option(
            selected: !_mySocietyOnly,
            enabled: beyondAvailable,
            title: 'Beyond your society',
            subtitle: beyondAvailable
                ? 'Residents in other societies within your chosen distance'
                : 'Not available in your city yet',
            onTap: beyondAvailable
                ? () => setState(() => _mySocietyOnly = false)
                : null,
          ),
          if (!_mySocietyOnly && beyondAvailable) ...[
            const SizedBox(height: 20),
            SellingReachRadiusSlider(
              value: _radiusKm,
              minKm: 1,
              maxKm: widget.reach.maxRadiusKm,
              onChanged: (km) => setState(() => _radiusKm = km),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: sheet,
      ),
    );
  }

  Widget _option({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Material(
      color: const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: enabled ? _green : const Color(0xFFADB5B2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? const Color(0xFF101617)
                            : const Color(0xFF8A9491),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: enabled
                            ? const Color(0xFF6A7774)
                            : const Color(0xFF8A9491),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
