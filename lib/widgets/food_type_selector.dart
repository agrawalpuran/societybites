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

  static const _trackWidth = 52.0;
  static const _trackHeight = 30.0;
  static const _thumbSize = 22.0;
  static const _animation = Duration(milliseconds: 200);

  bool get _isOn => selectedFoodType != null;

  String get _label {
    if (selectedFoodType == foodTypeVeg) return 'Veg';
    if (selectedFoodType == foodTypeNonVeg) return 'Non-Veg';
    return 'All';
  }

  Color get _trackColor {
    if (selectedFoodType == foodTypeVeg) return const Color(0xFF3D8B6E);
    if (selectedFoodType == foodTypeNonVeg) return const Color(0xFFC46B6B);
    return const Color(0xFFDDE3E0);
  }

  Color get _labelColor {
    if (selectedFoodType == foodTypeVeg) return const Color(0xFF0E5A47);
    if (selectedFoodType == foodTypeNonVeg) return const Color(0xFF9A4444);
    return const Color(0xFF6A7774);
  }

  String? _nextValue() {
    if (selectedFoodType == null) return foodTypeVeg;
    if (selectedFoodType == foodTypeVeg) return foodTypeNonVeg;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Food preference $_label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('home-food-type-toggle'),
          onTap: () => onChanged(_nextValue()),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: _animation,
                  curve: Curves.easeInOut,
                  width: _trackWidth,
                  height: _trackHeight,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _trackColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedAlign(
                    duration: _animation,
                    curve: Curves.easeInOut,
                    alignment: _isOn
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 62),
                  child: Text(
                    _label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _labelColor,
                    ),
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
