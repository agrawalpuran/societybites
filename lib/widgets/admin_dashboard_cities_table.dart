import 'package:flutter/material.dart';

String _formatGmv(num? raw) {
  final amount = (raw ?? 0).toDouble();
  if (amount >= 100000) {
    return '₹${(amount / 100000).toStringAsFixed(1)}L';
  }
  if (amount >= 1000) {
    return '₹${(amount / 1000).toStringAsFixed(1)}K';
  }
  if (amount == amount.roundToDouble()) {
    return '₹${amount.toStringAsFixed(0)}';
  }
  return '₹${amount.toStringAsFixed(2)}';
}

class AdminDashboardCitiesTable extends StatelessWidget {
  const AdminDashboardCitiesTable({
    super.key,
    required this.rows,
    required this.totals,
    required this.periodDays,
    required this.selectedCityKey,
    required this.onSelectCity,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? totals;
  final int periodDays;
  final String? selectedCityKey;
  final ValueChanged<String?> onSelectCity;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: const Text(
            'Turn on serving cities in Settings to compare metros here.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
          ),
        ),
      );
    }

    Widget cell(String text, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: const Color(0xFF101617),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAEFED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(
                'Compare cities (last $periodDays days)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3A4644),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Orders = any status placed in period. Food GMV = completed food subtotal only.',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: Color(0xFF6A7774),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columns: const [
                  DataColumn(label: Text('City')),
                  DataColumn(label: Text('Societies')),
                  DataColumn(label: Text('Sellers')),
                  DataColumn(label: Text('Orders')),
                  DataColumn(label: Text('Food GMV')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final row in rows)
                    _dataRow(
                      row,
                      cell,
                      selectedCityKey == row['cityKey']?.toString(),
                      onSelectCity,
                    ),
                  if (totals != null)
                    _totalRow(totals!, cell, selectedCityKey == null, onSelectCity),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _dataRow(
    Map<String, dynamic> row,
    Widget Function(String, {bool bold}) cell,
    bool selected,
    ValueChanged<String?> onSelectCity,
  ) {
    final cityKey = row['cityKey']?.toString() ?? '';
    final name = row['displayName']?.toString() ?? cityKey;
    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (selected) return const Color(0xFFF0FAF6);
        return null;
      }),
      cells: [
        DataCell(cell(name)),
        DataCell(cell('${row['societies'] ?? 0}')),
        DataCell(cell('${row['sellers'] ?? 0}')),
        DataCell(cell('${row['orders7d'] ?? 0}')),
        DataCell(cell(_formatGmv(row['foodGmv7d'] as num?))),
        DataCell(
          TextButton(
            onPressed: () => onSelectCity(cityKey),
            child: Text(selected ? 'Viewing' : 'Open'),
          ),
        ),
      ],
    );
  }

  DataRow _totalRow(
    Map<String, dynamic> totals,
    Widget Function(String, {bool bold}) cell,
    bool selected,
    ValueChanged<String?> onSelectCity,
  ) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (selected) return const Color(0xFFF0FAF6);
        return null;
      }),
      cells: [
        DataCell(cell('All (total)', bold: true)),
        DataCell(cell('${totals['societies'] ?? 0}', bold: true)),
        DataCell(cell('${totals['sellers'] ?? 0}', bold: true)),
        DataCell(cell('${totals['orders7d'] ?? 0}', bold: true)),
        DataCell(cell(_formatGmv(totals['foodGmv7d'] as num?), bold: true)),
        DataCell(
          TextButton(
            onPressed: () => onSelectCity(null),
            child: Text(selected ? 'Viewing' : 'Clear filter'),
          ),
        ),
      ],
    );
  }
}