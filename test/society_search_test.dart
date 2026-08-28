import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/services/society_search.dart';

const _pnh = {
  'id': 'prestige-notting-hill',
  'name': 'Prestige Notting Hill',
  'city': 'Bangalore',
  'address': 'Bannerghatta Road',
  'state': 'Karnataka',
};

const _brigade = {
  'id': 'brigade-gateway',
  'name': 'Brigade Gateway',
  'city': 'Bangalore',
  'address': 'Rajajinagar',
};

void main() {
  test('does not list societies until the query is long enough', () {
    expect(
      filterSocieties(societies: [_pnh, _brigade], query: ''),
      isEmpty,
    );
    expect(
      filterSocieties(societies: [_pnh, _brigade], query: 'p'),
      isEmpty,
    );
  });

  test('matches society name, city and address case-insensitively', () {
    final societies = [_pnh, _brigade];

    expect(
      filterSocieties(societies: societies, query: 'prestige').single['id'],
      'prestige-notting-hill',
    );
    expect(
      filterSocieties(societies: societies, query: 'NOTTING').single['id'],
      'prestige-notting-hill',
    );
    expect(
      filterSocieties(societies: societies, query: 'BANNERGHATTA').single['id'],
      'prestige-notting-hill',
    );
    expect(
      filterSocieties(societies: societies, query: 'XYZABC123'),
      isEmpty,
    );
  });

  test('builds a compact location label without duplicating city/state', () {
    expect(
      societyLocationLabel(_pnh),
      'Bannerghatta Road, Bangalore, Karnataka',
    );
  });
}
