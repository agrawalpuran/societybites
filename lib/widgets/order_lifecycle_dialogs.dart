import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/order_lifecycle.dart';

class RejectOrderResult {
  const RejectOrderResult({required this.reason, this.note});

  final String reason;
  final String? note;
}

Future<RejectOrderResult?> confirmRejectOrder(BuildContext context) async {
  RejectOrderResult? selected;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _RejectOrderSheet(
      onCancel: () => Navigator.pop(sheetContext),
      onConfirm: (value) {
        selected = value;
        Navigator.pop(sheetContext);
      },
    ),
  );
  return selected;
}

class _RejectOrderSheet extends StatefulWidget {
  const _RejectOrderSheet({
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final ValueChanged<RejectOrderResult> onConfirm;

  @override
  State<_RejectOrderSheet> createState() => _RejectOrderSheetState();
}

class _RejectOrderSheetState extends State<_RejectOrderSheet> {
  String? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reject Order?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Why can't you fulfil this order?",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3A4644),
            ),
          ),
          const SizedBox(height: 8),
          for (final reason in BuyerOrderVisibility.rejectReasons)
            ListTile(
              key: Key('reject-reason-$reason'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                _reason == reason
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: const Color(0xFF0E5A47),
                size: 22,
              ),
              title: Text(
                reason,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => setState(() => _reason = reason),
            ),
          const SizedBox(height: 8),
          const Text(
            'Optional note',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A9491),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('reject-note-field'),
            controller: _note,
            maxLength: 200,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a short note for the buyer',
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF8FAF9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFEAEFED)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  key: const Key('reject-order-confirm'),
                  onPressed: _reason == null
                      ? null
                      : () {
                          final note = _note.text.trim();
                          widget.onConfirm(
                            RejectOrderResult(
                              reason: _reason!,
                              note: note.isEmpty ? null : note,
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD94F4F),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE8EDEB),
                  ),
                  child: const Text('Reject Order'),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
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

class OrderRejectReasonBlock extends StatelessWidget {
  const OrderRejectReasonBlock({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final reason = BuyerOrderVisibility.rejectReasonLabel(order.rejectReason);
    final note = BuyerOrderVisibility.rejectNote(order.rejectReason);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            BuyerOrderLifecycle.detail('rejected')!,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8A3030),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD4D4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reason:\n$reason',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8A3030),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Seller note:\n$note',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8A3030),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool> confirmEarlierThanUsualLead(
  BuildContext context, {
  required DateTime requestedReadyAt,
  required String usualLeadLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Earlier than your usual lead time'),
      content: Text(
        'The buyer requested this order by:\n'
        '${Order.formatNeedBy(requestedReadyAt)}\n\n'
        'Your usual preparation time is:\n'
        '$usualLeadLabel\n\n'
        'Can you fulfil this order by the requested time?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('accept-confirm-early-need-by'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Accept & Confirm'),
        ),
      ],
    ),
  );
  return result == true;
}
