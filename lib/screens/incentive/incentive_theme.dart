import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const incentiveGreen = Color(0xFF0E5A47);
const incentiveInk = Color(0xFF101617);
const incentiveMuted = Color(0xFF6A7774);
const incentiveLine = Color(0xFFE4ECE9);
const incentiveCanvas = Color(0xFFF8FAF9);

class IncentiveCard extends StatelessWidget {
  const IncentiveCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: incentiveLine),
      ),
      child: child,
    );
  }
}

class IncentiveNotice extends StatelessWidget {
  const IncentiveNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return IncentiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: incentiveInk, height: 1.4)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

Future<void> copyIncentiveText(BuildContext context, String value, String label) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
}

String incentiveRewardLabel(Object? type) {
  switch (type?.toString()) {
    case 'FIXED_COUPON':
      return 'Fixed coupon';
    case 'PERCENTAGE_COUPON':
      return 'Percentage coupon';
    case 'PROMOTIONAL_CREDIT':
      return 'Promotional credit';
    case 'POINTS':
      return 'Points';
    default:
      return 'Reward type unavailable';
  }
}

String incentiveWhen(Object? value) {
  if (value == null || value.toString().isEmpty) return '—';
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) return value.toString();
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
