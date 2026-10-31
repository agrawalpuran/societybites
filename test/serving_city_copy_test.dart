import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/app_settings.dart';

void main() {
  test('settings without a city list still say Bengaluru', () {
    final settings = AppSettings.fromJson({'platformFee': 0});
    expect(settings.servingCityLabel, 'Bengaluru');
    expect(settings.servingCities, ['Bengaluru']);
  });

  test('settings use the serving city label from the server', () {
    final settings = AppSettings.fromJson({
      'servingCities': ['Bengaluru', 'Pune'],
      'servingCityLabel': 'Bengaluru and Pune',
    });
    expect(settings.servingCityLabel, 'Bengaluru and Pune');
    expect(settings.servingCities, ['Bengaluru', 'Pune']);
  });
}
