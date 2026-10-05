import 'package:flutter/material.dart';

import 'web_breakpoints.dart';

class WebCategoryRow extends StatelessWidget {
  const WebCategoryRow({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.counts,
    required this.onSelected,
    this.activeLabels,
  });

  final List<String> categories;
  final String? selectedCategory;
  final Map<String, int> counts;
  final ValueChanged<String?> onSelected;

  /// When set, these labels are the highlighted filters.
  /// Food categories and order-type chips can both be active.
  final Set<String>? activeLabels;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final label = categories[index];
          final value = label == 'All' ? null : label;
          final selected = activeLabels != null
              ? activeLabels!.contains(label)
              : selectedCategory == value ||
                    (selectedCategory == null && label == 'All');
          final count = counts[label];
          return _CategoryCard(
            label: label,
            count: count,
            selected: selected,
            icon: _iconFor(label),
            onTap: () => onSelected(value),
          );
        },
      ),
    );
  }
}

IconData _iconFor(String label) {
  switch (label) {
    case 'Just Added':
      return Icons.auto_awesome_outlined;
    case 'Breakfast':
      return Icons.free_breakfast_outlined;
    case 'Lunch':
      return Icons.lunch_dining_outlined;
    case 'Dinner':
      return Icons.dinner_dining_outlined;
    case 'Made to Order':
      return Icons.soup_kitchen_outlined;
    case 'Pre-order':
      return Icons.event_available_outlined;
    case 'Snacks':
      return Icons.cookie_outlined;
    case 'Desserts':
      return Icons.cake_outlined;
    case 'Beverages':
      return Icons.local_cafe_outlined;
    case 'Healthy':
      return Icons.eco_outlined;
    case 'Jain':
      return Icons.spa_outlined;
    case 'Kids':
      return Icons.child_care_outlined;
    case 'Homemade Specials':
      return Icons.favorite_border_rounded;
    default:
      return Icons.grid_view_rounded;
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE7F3EC) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? webGreen : webLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: webGreen),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: webInk,
                    ),
                  ),
                  if (count != null)
                    Text(
                      count == 1 ? '1 listing' : '$count listings',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: webMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
