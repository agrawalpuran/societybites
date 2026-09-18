import 'package:flutter/material.dart';

import '../models/listing_categories.dart';

class AvailableInSelector extends StatelessWidget {
  const AvailableInSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final allSelected = isAllListingCategoriesSelected(selected);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          label: allListingCategoriesLabel,
          isSelected: allSelected,
          onSelected: (value) {
            onChanged(
              toggleListingCategory(
                selected,
                option: allListingCategoriesLabel,
                selected: value,
              ),
            );
          },
        ),
        ...listingFoodCategories.map((category) {
          return _chip(
            label: category,
            isSelected: selected.contains(category),
            onSelected: (value) {
              onChanged(
                toggleListingCategory(
                  selected,
                  option: category,
                  selected: value,
                ),
              );
            },
          );
        }),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      selectedColor: const Color(0xFFD6F0E4),
      checkmarkColor: const Color(0xFF0E5A47),
      backgroundColor: const Color(0xFFF5F7F6),
      side: BorderSide(
        color: isSelected ? const Color(0xFF0E5A47) : const Color(0xFFE0E5E3),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isSelected ? const Color(0xFF0E5A47) : const Color(0xFF3A4644),
      ),
    );
  }
}
