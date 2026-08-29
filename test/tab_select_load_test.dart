import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/tab_select_load.dart';

void main() {
  test('first visit fetches when nothing has loaded yet', () {
    expect(
      shouldFetchOnTabSelect(
        hasSuccessfullyLoaded: false,
        isLoadInProgress: false,
      ),
      isTrue,
    );
  });

  test('does not fetch again after a successful load', () {
    expect(
      shouldFetchOnTabSelect(
        hasSuccessfullyLoaded: true,
        isLoadInProgress: false,
      ),
      isFalse,
    );
  });

  test('does not start a second fetch while the first load is in progress', () {
    expect(
      shouldFetchOnTabSelect(
        hasSuccessfullyLoaded: false,
        isLoadInProgress: true,
      ),
      isFalse,
    );
  });

  test('failed load remains eligible for another fetch', () {
    expect(
      shouldFetchOnTabSelect(
        hasSuccessfullyLoaded: false,
        isLoadInProgress: false,
      ),
      isTrue,
    );
  });

  test('in-progress takes precedence over a later successful flag', () {
    expect(
      shouldFetchOnTabSelect(
        hasSuccessfullyLoaded: true,
        isLoadInProgress: true,
      ),
      isFalse,
    );
  });
}
