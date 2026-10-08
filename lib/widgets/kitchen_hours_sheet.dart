import 'package:flutter/material.dart';

import '../models/kitchen_hours.dart';
import 'simple_time_picker.dart';

class KitchenHoursDraft {
  const KitchenHoursDraft({this.opensAt, this.closesAt, this.clear = false});

  final String? opensAt;
  final String? closesAt;
  final bool clear;
}

class KitchenHoursSheet extends StatefulWidget {
  const KitchenHoursSheet({
    super.key,
    this.opensAt,
    this.closesAt,
  });

  final String? opensAt;
  final String? closesAt;

  @override
  State<KitchenHoursSheet> createState() => _KitchenHoursSheetState();
}

class _KitchenHoursSheetState extends State<KitchenHoursSheet> {
  late bool _alwaysOpen;
  late String _opensAt;
  late String _closesAt;

  @override
  void initState() {
    super.initState();
    _alwaysOpen = widget.opensAt == null && widget.closesAt == null;
    _opensAt = widget.opensAt ?? defaultKitchenOpensAt;
    _closesAt = widget.closesAt ?? defaultKitchenClosesAt;
  }

  Future<void> _pick({required bool open}) async {
    final current = open ? _opensAt : _closesAt;
    final picked = await showSimpleTimePicker(
      context,
      initialTime: timeOfDayFromClock(
        current,
        open ? const TimeOfDay(hour: 8, minute: 0) : const TimeOfDay(hour: 20, minute: 0),
      ),
    );
    if (picked == null) return;
    setState(() {
      _alwaysOpen = false;
      if (open) {
        _opensAt = clockFromTimeOfDay(picked);
      } else {
        _closesAt = clockFromTimeOfDay(picked);
      }
    });
  }

  void _save() {
    if (_alwaysOpen) {
      Navigator.pop(context, const KitchenHoursDraft(clear: true));
      return;
    }
    if (_opensAt == _closesAt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Close time must be different from open time')),
      );
      return;
    }
    Navigator.pop(
      context,
      KitchenHoursDraft(opensAt: _opensAt, closesAt: _closesAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kitchen hours',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Buyers cannot place any order outside these hours. This overrides listing availability.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Always open',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _alwaysOpen
                  ? 'ON — no fixed kitchen hours'
                  : 'OFF — set open and close times below',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
            ),
            value: _alwaysOpen,
            activeColor: const Color(0xFF0E5A47),
            onChanged: (value) => setState(() => _alwaysOpen = value),
          ),
          if (!_alwaysOpen) ...[
            const SizedBox(height: 8),
            _TimeRow(
              label: 'Open time',
              value: formatKitchenClock(_opensAt),
              onTap: () => _pick(open: true),
            ),
            const SizedBox(height: 10),
            _TimeRow(
              label: 'Close time',
              value: formatKitchenClock(_closesAt),
              onTap: () => _pick(open: false),
            ),
            const SizedBox(height: 8),
            const Text(
              'If close is earlier than open, the kitchen stays open past midnight.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF8A9491),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Save hours',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0E5E3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A4644),
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0E5A47),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF8A9491)),
            ],
          ),
        ),
      ),
    );
  }
}
