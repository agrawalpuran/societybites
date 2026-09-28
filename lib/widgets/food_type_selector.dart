import 'package:flutter/material.dart';

import '../models/food_type.dart';

class FoodTypeSelector extends StatelessWidget {
  const FoodTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FoodTypeChoice(
            selected: value == foodTypeVeg,
            label: '🥬 Vegetarian',
            onTap: () => onChanged(foodTypeVeg),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FoodTypeChoice(
            selected: value == foodTypeNonVeg,
            label: '🍗 Non-Vegetarian',
            onTap: () => onChanged(foodTypeNonVeg),
          ),
        ),
      ],
    );
  }
}

class _FoodTypeChoice extends StatelessWidget {
  const _FoodTypeChoice({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFD6F0E4) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFFE0E5E3),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xFF0E5A47)
                  : const Color(0xFF3A4644),
            ),
          ),
        ),
      ),
    );
  }
}

class FoodTypeFilterChips extends StatelessWidget {
  const FoodTypeFilterChips({
    super.key,
    required this.selectedFoodType,
    required this.onChanged,
  });

  /// Null means All.
  final String? selectedFoodType;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterChoice(
            label: 'All',
            selected: selectedFoodType == null,
            selectedColor: const Color(0xFF0E5A47),
            onTap: () => onChanged(null),
          ),
          _FilterChoice(
            label: 'Veg',
            markColor: const Color(0xFF14804A),
            selected: selectedFoodType == foodTypeVeg,
            selectedColor: const Color(0xFF0E5A47),
            onTap: () => onChanged(foodTypeVeg),
          ),
          _FilterChoice(
            label: 'Non-veg',
            markColor: const Color(0xFFC0392B),
            selected: selectedFoodType == foodTypeNonVeg,
            selectedColor: const Color(0xFF9A4444),
            onTap: () => onChanged(foodTypeNonVeg),
          ),
        ],
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
    this.markColor,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;
  final Color? markColor;

  @override
  Widget build(BuildContext context) {
    final labelColor = selected ? Colors.white : const Color(0xFF6A7774);
    return Material(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        key: ValueKey('home-food-type-$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (markColor != null) ...[
                  _FoodMark(color: selected ? Colors.white : markColor!),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The small square-and-dot mark used on Indian menus: green for veg, red for non-veg.
class _FoodMark extends StatelessWidget {
  const _FoodMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 11,
      height: 11,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1.5),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Center(
          child: Container(
            width: 4.5,
            height: 4.5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
