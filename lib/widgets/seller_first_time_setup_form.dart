import 'package:flutter/material.dart';

import '../models/seller_fulfilment.dart';
import '../models/seller_payment_preference.dart';
import '../models/selling_reach.dart';
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
    required this.sellingReachLevel,
    required this.sellingReach,
    required this.onReachChanged,
    required this.fulfilment,
    required this.onFulfilmentChanged,
    required this.kitchenOpensAt,
    required this.kitchenClosesAt,
    required this.onKitchenChanged,
    required this.fssaiSubtitle,
    required this.fssaiRequirementEnabled,
    required this.fssaiAllowsEnableSelling,
    required this.onOpenFssai,
  });

  final SellerPaymentPreference paymentPreference;
  final ValueChanged<SellerPaymentPreference> onPaymentChanged;
  final String? upiId;
  final String? upiDisplayName;
  final void Function(String upiId, String displayName) onUpiChanged;
  final SellingReachLevel sellingReachLevel;
  final SellingReach sellingReach;
  final ValueChanged<SellingReachLevel> onReachChanged;
  final SellerFulfilment fulfilment;
  final ValueChanged<SellerFulfilment> onFulfilmentChanged;
  final String? kitchenOpensAt;
  final String? kitchenClosesAt;
  final ValueChanged<KitchenHoursDraft> onKitchenChanged;
  final String fssaiSubtitle;
  final bool fssaiRequirementEnabled;
  final bool fssaiAllowsEnableSelling;
  final VoidCallback onOpenFssai;

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

  void _commitUpi() {
    widget.onUpiChanged(
      _upiController.text.trim(),
      _upiNameController.text.trim(),
    );
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
          controller: _upiController,
          keyboardType: TextInputType.emailAddress,
          onEditingComplete: _commitUpi,
          onTapOutside: (_) => _commitUpi(),
          decoration: _fieldDecoration(
            label: 'UPI ID',
            hint: 'yourname@oksbi',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _upiNameController,
          onEditingComplete: _commitUpi,
          onTapOutside: (_) => _commitUpi(),
          decoration: _fieldDecoration(
            label: 'Display name on UPI (optional)',
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
        ...SellingReachLevel.values.map((level) {
          final enabled = widget.sellingReach.isSelectable(level);
          final selected = level == widget.sellingReachLevel;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RadioCard(
              selected: selected,
              enabled: enabled,
              title: level.title,
              subtitle: widget.sellingReach.setupHintFor(level),
              onTap: enabled ? () => widget.onReachChanged(level) : null,
            ),
          );
        }),
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
          onChanged: widget.onKitchenChanged,
        ),
        const SizedBox(height: 24),
        const _SectionLabel('FOOD & COMPLIANCE'),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEAEFED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.badge_outlined, color: Color(0xFF0E5A47)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'FSSAI details',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _FssaiRequirementChip(
                      required: widget.fssaiRequirementEnabled,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.fssaiRequirementEnabled
                      ? 'FSSAI is required on SocietyBites before you can enable selling. '
                          'Submit your registration for review, then return here.'
                      : 'FSSAI is optional for now. You can enable selling and add or defer '
                          'details later.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A9491),
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.fssaiSubtitle,
                  style: const TextStyle(
                    color: Color(0xFF6A7774),
                    height: 1.35,
                  ),
                ),
                if (widget.fssaiRequirementEnabled &&
                    !widget.fssaiAllowsEnableSelling) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Submit your FSSAI registration for review before you can enable selling.',
                    style: TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.onOpenFssai,
                    child: Text(
                      widget.fssaiRequirementEnabled
                          ? 'Complete FSSAI'
                          : 'Add or update FSSAI',
                    ),
                  ),
                ),
              ],
            ),
          ),
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
  }) {
    return InputDecoration(
      labelText: label,
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

class _FssaiRequirementChip extends StatelessWidget {
  const _FssaiRequirementChip({required this.required});

  final bool required;

  @override
  Widget build(BuildContext context) {
    final bg = required ? const Color(0xFFFDECEC) : const Color(0xFFE8F5EE);
    final fg = required ? const Color(0xFFC62828) : const Color(0xFF0E5A47);
    final label = required ? 'Required' : 'Optional';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: fg,
        ),
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
