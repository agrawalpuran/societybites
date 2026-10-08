import 'package:flutter/material.dart';

import '../models/kitchen_hours.dart';
import 'kitchen_hours_sheet.dart';
import 'simple_time_picker.dart';

/// Inline kitchen hours for seller setup (no sheet / save buttons).
class KitchenHoursInlineEditor extends StatefulWidget {
  const KitchenHoursInlineEditor({
    super.key,
    this.opensAt,
    this.closesAt,
    this.explicitAlwaysOpen = false,
    required this.onChanged,
  });

  final String? opensAt;
  final String? closesAt;

  /// True when the seller chose “always open” (cleared hours), not merely unset.
  final bool explicitAlwaysOpen;
  final ValueChanged<KitchenHoursDraft> onChanged;

  @override
  State<KitchenHoursInlineEditor> createState() =>
      _KitchenHoursInlineEditorState();
}

class _KitchenHoursInlineEditorState extends State<KitchenHoursInlineEditor> {
  late bool _alwaysOpen;
  late String _opensAt;
  late String _closesAt;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant KitchenHoursInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opensAt != widget.opensAt ||
        oldWidget.closesAt != widget.closesAt ||
        oldWidget.explicitAlwaysOpen != widget.explicitAlwaysOpen) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    _alwaysOpen = widget.explicitAlwaysOpen;
    _opensAt = widget.opensAt ?? defaultKitchenOpensAt;
    _closesAt = widget.closesAt ?? defaultKitchenClosesAt;
  }

  void _emitScheduled() {
    if (_alwaysOpen) {
      widget.onChanged(const KitchenHoursDraft(clear: true));
      return;
    }
    if (_opensAt == _closesAt) return;
    widget.onChanged(KitchenHoursDraft(opensAt: _opensAt, closesAt: _closesAt));
  }

  Future<void> _pick({required bool open}) async {
    final current = open ? _opensAt : _closesAt;
    final picked = await showSimpleTimePicker(
      context,
      initialTime: timeOfDayFromClock(
        current,
        open
            ? const TimeOfDay(hour: 8, minute: 0)
            : const TimeOfDay(hour: 20, minute: 0),
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
    _emitScheduled();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          onChanged: (value) {
            setState(() => _alwaysOpen = value);
            _emitScheduled();
          },
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
          const SizedBox(height: 6),
          const Text(
            'If close is earlier than open, the kitchen stays open past midnight.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF8A9491),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
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
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF8A9491),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
