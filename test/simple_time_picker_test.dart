import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/widgets/simple_time_picker.dart';

void main() {
  test('snaps minutes to the nearest 15-minute slot', () {
    expect(
      snapToSimpleTime(const TimeOfDay(hour: 14, minute: 7)),
      const TimeOfDay(hour: 14, minute: 0),
    );
    expect(
      snapToSimpleTime(const TimeOfDay(hour: 14, minute: 8)),
      const TimeOfDay(hour: 14, minute: 15),
    );
    expect(
      snapToSimpleTime(const TimeOfDay(hour: 14, minute: 52)),
      const TimeOfDay(hour: 14, minute: 45),
    );
    expect(
      snapToSimpleTime(const TimeOfDay(hour: 14, minute: 53)),
      const TimeOfDay(hour: 15, minute: 0),
    );
  });

  testWidgets('time sheet uses hour, minutes, and AM/PM instead of a clock', (
    tester,
  ) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showSimpleTimePicker(
                  context,
                  initialTime: const TimeOfDay(hour: 14, minute: 0),
                );
              },
              child: const Text('open-time'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-time'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('simple-time-picker')), findsOneWidget);
    expect(find.text('Hour'), findsOneWidget);
    expect(find.text('Min'), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);

    await tester.tap(find.byKey(const Key('simple-time-done')));
    await tester.pumpAndSettle();
    expect(picked, const TimeOfDay(hour: 14, minute: 0));
  });
}
