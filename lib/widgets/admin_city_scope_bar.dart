import 'package:flutter/material.dart';

import '../models/serving_city.dart';

class AdminCityScopeBar extends StatelessWidget {
  const AdminCityScopeBar({
    super.key,
    required this.activeCities,
    required this.selectedCityKey,
    required this.onSelected,
  });

  final List<ServingCity> activeCities;
  final String? selectedCityKey;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (activeCities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'City',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6A7774),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CityChip(
              label: 'All cities',
              selected: selectedCityKey == null,
              onTap: () => onSelected(null),
            ),
            for (final city in activeCities)
              _CityChip(
                label: city.displayName,
                selected: selectedCityKey == city.cityKey,
                onTap: () => onSelected(city.cityKey),
              ),
          ],
        ),
      ],
    );
  }
}

class _CityChip extends StatelessWidget {
  const _CityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFE8F5EE) : Colors.white;
    final border = selected ? const Color(0xFF0E5A47) : const Color(0xFFC5D4CF);
    final fg = selected ? const Color(0xFF0E5A47) : const Color(0xFF3A4644);

    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}