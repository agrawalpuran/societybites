import 'package:flutter/material.dart';

const _minuteSteps = [0, 15, 30, 45];

TimeOfDay snapToSimpleTime(TimeOfDay time) {
  var hour = time.hour;
  const candidates = [0, 15, 30, 45, 60];
  final nearest = candidates.reduce(
    (best, step) =>
        (step - time.minute).abs() < (best - time.minute).abs() ? step : best,
  );
  var minute = nearest;
  if (minute == 60) {
    hour = (hour + 1) % 24;
    minute = 0;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

Future<DateTime?> pickDateAndSimpleTime(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String? dateHelpText,
}) async {
  var initialDate = initial;
  if (initialDate.isBefore(firstDate)) initialDate = firstDate;
  if (initialDate.isAfter(lastDate)) initialDate = lastDate;
  final date = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: dateHelpText,
  );
  if (date == null || !context.mounted) return null;
  final time = await showSimpleTimePicker(
    context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<TimeOfDay?> showSimpleTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _SimpleTimeSheet(initialTime: snapToSimpleTime(initialTime)),
  );
}

class _SimpleTimeSheet extends StatefulWidget {
  const _SimpleTimeSheet({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_SimpleTimeSheet> createState() => _SimpleTimeSheetState();
}

class _SimpleTimeSheetState extends State<_SimpleTimeSheet> {
  late int _hour12;
  late int _minute;
  late bool _pm;

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hour;
    _pm = hour >= 12;
    _hour12 = hour % 12 == 0 ? 12 : hour % 12;
    _minute = widget.initialTime.minute;
  }

  TimeOfDay get _value {
    final hour24 = _pm
        ? (_hour12 == 12 ? 12 : _hour12 + 12)
        : (_hour12 == 12 ? 0 : _hour12);
    return TimeOfDay(hour: hour24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose time',
            key: Key('simple-time-picker'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick hour, minutes, and AM or PM.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _WheelField(
                  label: 'Hour',
                  value: _hour12,
                  items: List<int>.generate(12, (i) => i + 1),
                  onChanged: (value) => setState(() => _hour12 = value),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 18, 8, 0),
                child: Text(
                  ':',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              Expanded(
                child: _WheelField(
                  label: 'Min',
                  value: _minute,
                  items: _minuteSteps,
                  format: (value) => value.toString().padLeft(2, '0'),
                  onChanged: (value) => setState(() => _minute = value),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: ToggleButtons(
                  key: const Key('simple-time-ampm'),
                  isSelected: [!_pm, _pm],
                  borderRadius: BorderRadius.circular(12),
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
                  selectedColor: Colors.white,
                  fillColor: const Color(0xFF0E5A47),
                  color: const Color(0xFF0E5A47),
                  onPressed: (index) => setState(() => _pm = index == 1),
                  children: const [
                    Text('AM', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('PM', style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  key: const Key('simple-time-done'),
                  onPressed: () => Navigator.pop(context, _value),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WheelField extends StatelessWidget {
  const _WheelField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.format,
  });

  final String label;
  final int value;
  final List<int> items;
  final ValueChanged<int> onChanged;
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6A7774),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: value,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(
                  format?.call(item) ?? '$item',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }
}
