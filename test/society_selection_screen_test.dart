import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/screens/society_selection_screen.dart';

final _societies = [
  {
    'id': 'prestige-notting-hill',
    'name': 'Prestige Notting Hill',
    'city': 'Bangalore',
    'address': 'Bannerghatta Road',
    'unitLabel': 'Block',
    'blocks': [
      {'name': 'A'},
      {'name': 'C'},
    ],
  },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> openScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SocietySelectionScreen(loadSocieties: () async => _societies),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('does not list societies until the user searches', (tester) async {
    await openScreen(tester);

    expect(find.text('Where do you live?'), findsOneWidget);
    expect(
      find.text('Search for your apartment, society or community.'),
      findsOneWidget,
    );
    expect(find.text('Prestige Notting Hill'), findsNothing);
  });

  testWidgets('search finds a society and confirm can be cancelled', (
    tester,
  ) async {
    await openScreen(tester);

    await tester.enterText(
      find.byKey(const ValueKey('society-search-field')),
      'prestige',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Prestige Notting Hill'), findsOneWidget);
    await tester.tap(find.text('Prestige Notting Hill'));
    await tester.pump();

    expect(find.text('Confirm Your Society'), findsOneWidget);
    expect(find.text('Save & Continue'), findsNothing);

    await tester.tap(find.text('← Choose Different Society'));
    await tester.pump();

    expect(find.text('Where do you live?'), findsOneWidget);
    expect(find.text('Confirm Your Society'), findsNothing);
  });

  testWidgets('unknown search shows an empty state', (tester) async {
    await openScreen(tester);

    await tester.enterText(
      find.byKey(const ValueKey('society-search-field')),
      'XYZABC123',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('No societies found.'), findsOneWidget);
    expect(
      find.text('Try searching with a different name or spelling.'),
      findsOneWidget,
    );
  });

  testWidgets('save stays disabled until name, block and flat are provided', (
    tester,
  ) async {
    var joined = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SocietySelectionScreen(
          loadSocieties: () async => _societies,
          joinSociety: ({
            societyId,
            googlePlaceId,
            required flatNumber,
            required block,
            required firstName,
            lastName,
          }) async {
            joined = true;
            return {
              'id': 'user-1',
              'societyId': societyId,
              'flatId': 'flat-1',
              'name': firstName,
              'society': {'id': societyId, 'name': 'Prestige Notting Hill'},
              'flat': {'id': 'flat-1', 'flatNumber': flatNumber},
            };
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('society-search-field')),
      'notting',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('Prestige Notting Hill'));
    await tester.pump();
    await tester.tap(find.text('Confirm & Continue'));
    await tester.pump();

    expect(find.text('Save & Continue'), findsOneWidget);
    await tester.tap(find.text('Save & Continue'));
    await tester.pump();
    expect(joined, isFalse);
  });

  testWidgets('Google place confirm does not join and can be cancelled', (
    tester,
  ) async {
    var previewed = false;
    var joined = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SocietySelectionScreen(
          searchSocieties: (query) async {
            if (!query.toLowerCase().contains('spring')) return [];
            return [
              {
                'placeId': 'ChIJ-spring-valley',
                'name': 'Spring Valley Apartments',
                'address': 'Sarjapur Road, Bengaluru',
              },
            ];
          },
          previewPlace: (placeId) async {
            previewed = true;
            expect(placeId, 'ChIJ-spring-valley');
            return {
              'isNew': true,
              'society': null,
              'place': {
                'placeId': placeId,
                'name': 'Spring Valley Apartments',
                'address': 'Sarjapur Road, Bengaluru',
                'city': 'Bengaluru',
              },
            };
          },
          joinSociety: ({
            societyId,
            googlePlaceId,
            required flatNumber,
            required block,
            required firstName,
            lastName,
          }) async {
            joined = true;
            return {};
          },
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('society-search-field')),
      'spring',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Spring Valley Apartments'), findsOneWidget);
    await tester.tap(find.text('Spring Valley Apartments'));
    await tester.pump();
    expect(previewed, isFalse);

    await tester.tap(find.text('Confirm & Continue'));
    await tester.pump();
    await tester.pump();
    expect(previewed, isTrue);
    expect(joined, isFalse);
    expect(find.text('Save & Continue'), findsOneWidget);

    await tester.tap(find.text('← Choose Different Society'));
    await tester.pump();
    expect(find.text('Where do you live?'), findsOneWidget);
    expect(joined, isFalse);
  });
}
