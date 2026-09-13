import 'package:flutter/material.dart';

Future<bool> confirmRejectOrder(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reject this order?'),
      content: const Text(
        'The buyer will be notified that the order could not be fulfilled.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFD94F4F)),
          child: const Text('Reject Order'),
        ),
      ],
    ),
  );
  return result == true;
}

Future<bool> confirmCompleteOrder(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Complete this order?'),
      content: const Text(
        'Please confirm that the food has been handed over to the buyer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF0E5A47)),
          child: const Text('Complete Order'),
        ),
      ],
    ),
  );
  return result == true;
}
