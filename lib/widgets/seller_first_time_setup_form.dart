import 'package:flutter/material.dart';

import '../models/seller_fulfilment.dart';
import '../models/seller_payment_preference.dart';
import '../models/selling_reach.dart';
import 'selling_reach_radius_slider.dart';
import 'kitchen_hours_inline_editor.dart';
import 'kitchen_hours_sheet.dart';

class SellerFirstTimeSetupForm extends StatefulWidget {
  const SellerFirstTimeSetupForm({
    super.key,
    required this.paymentPreference,
    required this.onPaymentChanged,
    required this.upiId,
    required this.upiDisplayName,
    required this.onUpiChanged,
    this.onUpiConfirmed,
    this.onUpiConfirmationInvalidated,
    this.upiIdConfirmed = false,
    required this.sellingReachPreference,
    required this.sellingReach,
    required this.onReachPreferenceChanged,
    required this.fulfilment,
    required this.onFulfilmentChanged,
    required this.kitchenOpensAt,
    required this.kitchenClosesAt,
    this.kitchenExplicitAlwaysOpen = false,
    required this.onKitchenChanged,
  });

  final SellerPaymentPreference paymentPreference;
  final ValueChanged<SellerPaymentPreference> onPaymentChanged;
  final String? upiId;
  final String? upiDisplayName;
  final void Function(String upiId, String displayName) onUpiChanged;
  final VoidCallback? onUpiConfirmed;
  final VoidCallback? onUpiConfirmationInvalidated;
  final bool upiIdConfirmed;
  final SellerReachPreference sellingReachPreference;
  final SellingReach sellingReach;
  final ValueChanged<SellerReachPreference> onReachPreferenceChanged;
  final SellerFulfilment fulfilment;
  final ValueChanged<SellerFulfilment> onFulfilmentChanged;
  final String? kitchenOpensAt;
  final String? kitchenClosesAt;
  final bool kitchenExplicitAlwaysOpen;
  final ValueChanged<KitchenHoursDraft> onKitchenChanged;

  @override
  State<SellerFirstTimeSetupForm> createState() =>
      _SellerFirstTimeSetupFormState();
}

class _SellerFirstTimeSetupFormState extends State<SellerFirstTimeSetupForm> {
  late final TextEditingController _upiController;
  late final TextEditingController _upiNameController;
  late FulfilmentMode _fulfilmentMode;
  late final TextEditingController _inSocietyCharge;
  late final TextEditingController _nearbyCharge;
  late final TextEditingController _extendedCharge;

  @override
  void initState() {
    super.initState();
    _upiController = TextEditingController(text: widget.upiId ?? '');
    _upiNameController = TextEditingController(
      text: widget.upiDisplayName ?? '',
    );
    _fulfilmentMode = widget.fulfilment.mode;
    _inSocietyCharge = TextEditingController(
      text: _chargeText(widget.fulfilment.inSocietyCharge),
    );
    _nearbyCharge = TextEditingController(
      text: _chargeText(widget.fulfilment.nearbyCharge),
    );
    _extendedCharge = TextEditingController(
      text: _chargeText(widget.fulfilment.extendedCharge),
    );
  }

  @override
  void didUpdateWidget(covariant SellerFirstTimeSetupForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.upiId != widget.upiId &&
        _upiController.text != (widget.upiId ?? '')) {
      _upiController.text = widget.upiId ?? '';
    }
    if (oldWidget.upiDisplayName != widget.upiDisplayName &&
        _upiNameController.text != (widget.upiDisplayName ?? '')) {
      _upiNameController.text = widget.upiDisplayName ?? '';
    }
    if (oldWidget.fulfilment != widget.fulfilment) {
      _fulfilmentMode = widget.fulfilment.mode;
      _inSocietyCharge.text =
          _chargeText(widget.fulfilment.inSocietyCharge);
      _nearbyCharge.text = _chargeText(widget.fulfilment.nearbyCharge);
      _extendedCharge.text =
          _chargeText(widget.fulfilment.extendedCharge);
    }
  }

  @override
  void dispose() {
    _upiController.dispose();
    _upiNameController.dispose();
    _inSocietyCharge.dispose();
    _nearbyCharge.dispose();
    _extendedCharge.dispose();
    super.dispose();
  }

  String _chargeText(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toInt().toString()
        : amount.toString();
  }

  void _syncUpiDraftToParent() {
    widget.onUpiChanged(
      _upiController.text.trim(),
      _upiNameController.text.trim(),
    );
  }

  void _handleUpiTextChanged(String _) {
    // Editing after a prior confirm requires confirming again on Continue.
    if (widget.upiIdConfirmed) {
      widget.onUpiConfirmationInvalidated?.call();
    }
    // Keep parent draft in sync so Continue works even without tab/blur.
    _syncUpiDraftToParent();
    setState(() {});
  }

  void _handleDisplayNameChanged(String _) {
    _syncUpiDraftToParent();
  }

  bool get _showUpiConfirmed {
    final upi = _upiController.text.trim();
    return widget.upiIdConfirmed &&
        upi.isNotEmpty &&
        upi.contains('@') &&
        upi == (widget.upiId?.trim() ?? '');
  }

  void _commitFulfilment() {
    final mode = _fulfilmentMode;
    double parse(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return 0;
      return double.tryParse(t) ?? 0;
    }

    final inSociety = parse(_inSocietyCharge.text);
    final nearby = parse(_nearbyCharge.text);
    final extended = parse(_extendedCharge.text);
    widget.onFulfilmentChanged(
      SellerFulfilment(
        mode: mode,
        deliveryCharge: nearby,
        deliveryChargeInSociety: inSociety,
        deliveryChargeNearby: nearby,
        deliveryChargeExtended: extended,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('PAYMENTS'),
        const SizedBox(height: 10),
        ...SellerPaymentPreference.values.map((option) {
          final selected = option == widget.paymentPreference;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RadioCard(
              selected: selected,
              title: option.optionTitle,
              subtitle: option.optionSubtitle,
              onTap: () => widget.onPaymentChanged(option),
            ),
          );
        }),
        const SizedBox(height: 12),
        TextField(
          key: const Key('seller-setup-upi-id'),
          controller: _upiController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: _handleUpiTextChanged,
          onEditingComplete: _syncUpiDraftToParent,
          decoration: _fieldDecoration(
            label: 'UPI ID',
            hint: 'yourname@oksbi',
            required: true,
          ),
        ),
        if (_showUpiConfirmed) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: Color(0xFF0E5A47)),
              SizedBox(width: 6),
              Text(
                'UPI ID confirmed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0E5A47),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          key: const Key('seller-setup-upi-display-name'),
          controller: _upiNameController,
          textInputAction: TextInputAction.done,
          onChanged: _handleDisplayNameChanged,
          onEditingComplete: _syncUpiDraftToParent,
          onTapOutside: (_) => _syncUpiDraftToParent(),
          decoration: _fieldDecoration(
            label: 'Display name on UPI',
            hint: 'Name shown to buyers',
            required: true,
          ),
        ),
        const SizedBox(height: 24),
        const _SectionLabel('SELLING'),
        const SizedBox(height: 6),
        const Text(
          'Who can see your listings',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6A7774),
          ),
        ),
        const SizedBox(height: 10),
        _RadioCard(
          selected: widget.sellingReachPreference.mySocietyOnly,
          title: 'My society',
          subtitle: 'Only residents of your society',
          onTap: () => widget.onReachPreferenceChanged(
            SellerReachPreference(
              mySocietyOnly: true,
              radiusKm: widget.sellingReachPreference.radiusKm,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _RadioCard(
          selected: !widget.sellingReachPreference.mySocietyOnly,
          enabled: widget.sellingReach.beyondSocietyAvailable,
          title: 'Beyond your society',
          subtitle: widget.sellingReach.beyondSocietyAvailable
              ? 'Choose how far buyers can discover you'
              : 'Not available in your city yet',
          onTap: widget.sellingReach.beyondSocietyAvailable
              ? () => widget.onReachPreferenceChanged(
                    SellerReachPreference(
                      mySocietyOnly: false,
                      radiusKm: widget.sellingReachPreference.radiusKm,
                    ),
                  )
              : null,
        ),
        if (!widget.sellingReachPreference.mySocietyOnly &&
            widget.sellingReach.beyondSocietyAvailable) ...[
          const SizedBox(height: 12),
          SellingReachRadiusSlider(
            value: widget.sellingReachPreference.radiusKm,
            minKm: 1,
            maxKm: widget.sellingReach.maxRadiusKm,
            onChanged: (km) => widget.onReachPreferenceChanged(
              SellerReachPreference(mySocietyOnly: false, radiusKm: km),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Fulfilment',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 8),
        ...FulfilmentMode.values.map((mode) {
          final selected = mode == _fulfilmentMode;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RadioCard(
              selected: selected,
              title: mode.optionTitle,
              subtitle: mode.optionSubtitle,
              onTap: () {
                setState(() => _fulfilmentMode = mode);
                _commitFulfilment();
              },
            ),
          );
        }),
        if (_fulfilmentMode.showsDeliveryCharge) ...[
          const SizedBox(height: 8),
          _chargeField('In society', _inSocietyCharge, _commitFulfilment),
          _chargeField('Nearby', _nearbyCharge, _commitFulfilment),
          _chargeField('Extended', _extendedCharge, _commitFulfilment),
        ],
        const SizedBox(height: 16),
        const Text(
          'Kitchen hours',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 8),
        KitchenHoursInlineEditor(
          opensAt: widget.kitchenOpensAt,
          closesAt: widget.kitchenClosesAt,
          explicitAlwaysOpen: widget.kitchenExplicitAlwaysOpen,
          onChanged: widget.onKitchenChanged,
        ),
      ],
    );
  }

  Widget _chargeField(
    String label,
    TextEditingController controller,
    VoidCallback onCommit,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onEditingComplete: onCommit,
        onTapOutside: (_) => onCommit(),
        decoration: _fieldDecoration(label: label, hint: '0', prefix: '₹ '),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    String? prefix,
    bool required = false,
  }) {
    return InputDecoration(
      label: required
          ? Text.rich(
              TextSpan(
                text: label,
                style: const TextStyle(color: Color(0xFF6A7774)),
                children: const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          : null,
      labelText: required ? null : label,
      hintText: hint,
      prefixText: prefix,
      filled: true,
      fillColor: const Color(0xFFF5F7F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8A9491),
      ),
    );
  }
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  final bool selected;
  final bool enabled;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F7F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: enabled
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFFADB5B2),
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
