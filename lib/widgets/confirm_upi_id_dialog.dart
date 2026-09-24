import 'package:flutter/material.dart';

const _green = Color(0xFF0E5A47);
const _text = Color(0xFF101617);
const _muted = Color(0xFF6A7774);

Future<bool> confirmUpiIdBeforeSave(
  BuildContext context, {
  required String upiId,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => ConfirmUpiIdDialog(upiId: upiId),
  );
  return result == true;
}

class ConfirmUpiIdDialog extends StatefulWidget {
  const ConfirmUpiIdDialog({super.key, required this.upiId});

  final String upiId;

  @override
  State<ConfirmUpiIdDialog> createState() => _ConfirmUpiIdDialogState();
}

class _ConfirmUpiIdDialogState extends State<ConfirmUpiIdDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('confirm-upi-id-dialog'),
      title: const Text('Confirm UPI ID'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: _green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Please make sure this UPI ID is correct and belongs to your account.\n\n'
                    'Buyers will use this UPI ID to make payments for your orders. An incorrect UPI ID may cause payments to be sent to the wrong account or payment confirmation issues.',
                    style: TextStyle(
                      color: _text,
                      height: 1.35,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'UPI ID',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.upiId,
                key: const Key('confirm-upi-id-value'),
                style: const TextStyle(
                  color: _green,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('confirm-upi-id-checkbox'),
              value: _confirmed,
              onChanged: (value) =>
                  setState(() => _confirmed = value == true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _green,
              title: const Text(
                'I confirm that this UPI ID is correct.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('confirm-upi-id-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('confirm-upi-id-save'),
          onPressed: _confirmed
              ? () => Navigator.pop(context, true)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFD7E0DC),
            disabledForegroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Confirm & Save'),
        ),
      ],
    );
  }
}
