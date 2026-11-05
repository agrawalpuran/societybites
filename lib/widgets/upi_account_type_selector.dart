import 'package:flutter/material.dart';

import '../models/upi_account_type.dart';

/// Personal vs merchant UPI radios with an ⓘ help sheet.
class UpiAccountTypeSelector extends StatelessWidget {
  const UpiAccountTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final UpiAccountType value;
  final ValueChanged<UpiAccountType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'UPI type',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
            ),
            IconButton(
              key: const Key('upi-account-type-info'),
              tooltip: 'What do these mean?',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _showHelp(context),
              icon: const Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: Color(0xFF6A7774),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final option in UpiAccountType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _UpiTypeRadioCard(
              key: Key('upi-account-type-${option.apiValue.toLowerCase()}'),
              selected: option == value,
              title: option.optionTitle,
              subtitle: option.optionSubtitle,
              onTap: () => onChanged(option),
            ),
          ),
      ],
    );
  }

  Future<void> _showHelp(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personal vs Merchant UPI',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 14),
              for (final option in UpiAccountType.values) ...[
                Text(
                  option.optionTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E5A47),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  option.helpText,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpiTypeRadioCard extends StatelessWidget {
  const _UpiTypeRadioCard({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
                color: const Color(0xFF0E5A47),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6A7774),
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
