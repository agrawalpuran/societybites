import 'package:flutter/material.dart';

import '../models/data.dart';

class RequestedReadySummary extends StatelessWidget {
  const RequestedReadySummary({
    super.key,
    required this.order,
    required this.isSellerView,
  });

  final Order order;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    final requested = order.requestedReadyAt;
    if (requested == null) return const SizedBox.shrink();

    final lead = order.usualLeadTimeLabel;
    final earlier = isSellerView && order.requestedEarlierThanUsualLead;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isSellerView ? 'Buyer requested by' : 'Need by',
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A9491),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          Order.formatNeedBy(requested),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF101617),
          ),
        ),
        if (isSellerView && lead.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'Your usual lead time: $lead',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7774),
            ),
          ),
        ],
        if (earlier) ...[
          const SizedBox(height: 4),
          const Text(
            '⚠ Earlier than your usual lead time',
            key: Key('earlier-than-lead-warning'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC27803),
            ),
          ),
        ],
      ],
    );
  }
}

class NeedByCheckoutField extends StatelessWidget {
  const NeedByCheckoutField({
    super.key,
    required this.specified,
    required this.value,
    required this.onSpecifiedChanged,
    required this.onPickDateTime,
  });

  final bool specified;
  final DateTime? value;
  final ValueChanged<bool> onSpecifiedChanged;
  final VoidCallback onPickDateTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'When do you need it?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: Color(0xFF6A7774),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            key: const Key('need-by-none'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              specified ? Icons.radio_button_off : Icons.radio_button_checked,
              color: const Color(0xFF0E5A47),
              size: 22,
            ),
            title: const Text(
              'No specific date',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101617),
              ),
            ),
            onTap: () => onSpecifiedChanged(false),
          ),
          ListTile(
            key: const Key('need-by-specific'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              specified ? Icons.radio_button_checked : Icons.radio_button_off,
              color: const Color(0xFF0E5A47),
              size: 22,
            ),
            title: const Text(
              'I need it by',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF101617),
              ),
            ),
            onTap: () => onSpecifiedChanged(true),
          ),
          if (specified) ...[
            const SizedBox(height: 4),
            OutlinedButton(
              key: const Key('need-by-pick'),
              onPressed: onPickDateTime,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0E5A47),
                side: const BorderSide(color: Color(0xFFD4E8DF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                value == null
                    ? 'Select date/time'
                    : Order.formatNeedBy(value!),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Seller will confirm whether this date is possible.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8A9491),
            ),
          ),
        ],
      ),
    );
  }
}
